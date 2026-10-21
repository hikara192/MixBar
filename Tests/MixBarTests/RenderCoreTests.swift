import XCTest
import CoreAudio
import CAtomic
@testable import MixBarCore

/// Data plane tests: the mixing math must be exact and silence-safe.
/// The allocation-guard idea (fitness function 2) is documented in
/// ARCHITECTURE.md §12 — the pure render path has no allocation sites by
/// construction (only pointer arithmetic and CAtomic helpers).
final class RenderCoreTests: XCTestCase {

    private struct TestGraph {
        let slots: UnsafeMutablePointer<cat_slot_t>
        let active: UnsafeMutablePointer<cat_flag_t>
        let context: UnsafeMutablePointer<RenderContext>
        func deallocate() {
            context.deallocate()
            active.deallocate()
            slots.deallocate()
        }
    }

    private func makeGraph(capacity: Int = 4, active: Int, rampFrames: UInt32 = 480) -> TestGraph {
        let slots = UnsafeMutablePointer<cat_slot_t>.allocate(capacity: capacity)
        for i in 0..<capacity {
            slots[i] = cat_slot_t()
            (slots + i).pointee.current_milli = 1000
        }
        let activePtr = UnsafeMutablePointer<cat_flag_t>.allocate(capacity: 1)
        activePtr.pointee = cat_flag_t()
        cat_flag_set(activePtr, UInt32(active))
        let ctx = UnsafeMutablePointer<RenderContext>.allocate(capacity: 1)
        ctx.pointee = RenderContext(slots: slots, capacity: capacity,
                                    activeSlots: activePtr, rampFrames: rampFrames)
        return TestGraph(slots: slots, active: activePtr, context: ctx)
    }

    private func setSlot(_ graph: TestGraph, _ index: Int, target: UInt16, current: UInt32) {
        cat_slot_set_target(graph.slots + index, target)
        (graph.slots + index).pointee.current_milli = current
    }

    private func fill(_ list: InterleavedBufferList, buffer: Int, value: Float) {
        let base = list.channelData(buffer: buffer)
        let frames = list.frameCount(buffer: buffer, channels: 2)
        for f in 0..<frames {
            base[2 * f] = value
            base[2 * f + 1] = value
        }
    }

    // MARK: - Mixing

    func test_mixWithConstantGains() {
        let g = makeGraph(active: 2)
        defer { g.deallocate() }
        setSlot(g, 0, target: 1000, current: 1000)   // unity
        setSlot(g, 1, target: 500, current: 500)     // 50%

        let input = InterleavedBufferList(bufferCount: 2, frames: 64, channels: 2)
        fill(input, buffer: 0, value: 0.5)
        fill(input, buffer: 1, value: 0.5)
        let output = InterleavedBufferList(bufferCount: 1, frames: 64, channels: 2)

        let status = RenderCore.render(g.context, input: input.list, output: output.list)
        XCTAssertEqual(status, noErr)

        let out = output.channelData(buffer: 0)
        XCTAssertEqual(out[0], 0.75, accuracy: 1e-5)      // 0.5 * 1.0 + 0.5 * 0.5
        XCTAssertEqual(out[2 * 63], 0.75, accuracy: 1e-5)
    }

    func test_rampReachesTargetWithoutClick() {
        let g = makeGraph(active: 1, rampFrames: 480)
        defer { g.deallocate() }
        setSlot(g, 0, target: 500, current: 0)   // ramps 0 -> 500 over ~480 frames

        let input = InterleavedBufferList(bufferCount: 1, frames: 240, channels: 2)
        fill(input, buffer: 0, value: 0.8)
        let output = InterleavedBufferList(bufferCount: 1, frames: 240, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        let out = output.channelData(buffer: 0)
        // After 240 frames the ramp (2.083 milli/frame) has reached ~500:
        // last sample = 0.8 * ~0.498
        XCTAssertEqual(out[2 * 239], 0.398, accuracy: 0.02)
    }

    func test_clampToUnity() {
        let g = makeGraph(active: 2)
        defer { g.deallocate() }
        setSlot(g, 0, target: 1000, current: 1000)
        setSlot(g, 1, target: 1000, current: 1000)

        let input = InterleavedBufferList(bufferCount: 2, frames: 32, channels: 2)
        fill(input, buffer: 0, value: 0.9)
        fill(input, buffer: 1, value: 0.9)
        let output = InterleavedBufferList(bufferCount: 1, frames: 32, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        let out = output.channelData(buffer: 0)
        for f in 0..<32 {
            XCTAssertEqual(out[2 * f], 1.0, accuracy: 1e-6)   // 1.8 clamped
        }
    }

    func test_zeroInputRendersZeroOutput() {
        let g = makeGraph(active: 1)
        defer { g.deallocate() }
        setSlot(g, 0, target: 1000, current: 1000)

        let input = InterleavedBufferList(bufferCount: 1, frames: 16, channels: 2)  // zeroed
        let output = InterleavedBufferList(bufferCount: 1, frames: 16, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        let out = output.channelData(buffer: 0)
        for f in 0..<16 {
            XCTAssertEqual(out[2 * f], 0, accuracy: 1e-9)
            XCTAssertEqual(out[2 * f + 1], 0, accuracy: 1e-9)
        }
    }

    func test_layoutMismatchRendersSilenceNeverGarbage() {
        let g = makeGraph(active: 2)
        defer { g.deallocate() }
        // active = 2 expects 2 (interleaved) or 4 (non-interleaved) buffers;
        // 3 is unexpected -> silence, never garbage (error taxonomy row 9).
        let input = InterleavedBufferList(bufferCount: 3, frames: 16, channels: 2)
        fill(input, buffer: 0, value: 0.9)
        fill(input, buffer: 1, value: 0.9)
        fill(input, buffer: 2, value: 0.9)
        let output = InterleavedBufferList(bufferCount: 1, frames: 16, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        let out = output.channelData(buffer: 0)
        for f in 0..<16 {
            XCTAssertEqual(out[2 * f], 0, accuracy: 1e-9)
        }
    }

    func test_nonInterleavedPairs() {
        let g = makeGraph(active: 2)
        defer { g.deallocate() }
        setSlot(g, 0, target: 1000, current: 1000)
        setSlot(g, 1, target: 500, current: 500)

        // Non-interleaved stereo: 2 mono buffers per slot.
        let input = InterleavedBufferList(bufferCount: 4, frames: 32, channels: 1)
        for b in 0..<4 {
            let base = input.channelData(buffer: b)
            for f in 0..<32 { base[f] = 0.5 }
        }
        let output = InterleavedBufferList(bufferCount: 2, frames: 32, channels: 1)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        let outL = output.channelData(buffer: 0)
        let outR = output.channelData(buffer: 1)
        XCTAssertEqual(outL[0], 0.75, accuracy: 1e-5)
        XCTAssertEqual(outR[31], 0.75, accuracy: 1e-5)
    }

    func test_peakPublishingIsPostGain() {
        let g = makeGraph(active: 1)
        defer { g.deallocate() }
        setSlot(g, 0, target: 500, current: 500)

        let input = InterleavedBufferList(bufferCount: 1, frames: 64, channels: 2)
        fill(input, buffer: 0, value: 0.8)
        let output = InterleavedBufferList(bufferCount: 1, frames: 64, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        XCTAssertEqual(cat_slot_read_peak(g.slots + 0), 0.4, accuracy: 1e-5)
    }

    func test_inputPeakTracksPreGainInputWhenMuted() {
        let g = makeGraph(active: 1)
        defer { g.deallocate() }
        setSlot(g, 0, target: 0, current: 0)   // muted / 0%

        let input = InterleavedBufferList(bufferCount: 1, frames: 64, channels: 2)
        fill(input, buffer: 0, value: 0.8)
        let output = InterleavedBufferList(bufferCount: 1, frames: 64, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)

        // Output is silent (user asked for mute), but the tap is alive: the
        // pre-gain peak must stay non-zero so the permission heuristic does
        // not mistake a mute for a dead capture.
        XCTAssertEqual(cat_slot_read_peak(g.slots + 0), 0, accuracy: 1e-6)
        XCTAssertEqual(cat_slot_read_input_peak(g.slots + 0), 0.8, accuracy: 1e-5)
        XCTAssertEqual(output.channelData(buffer: 0)[0], 0, accuracy: 1e-9)
    }

    func test_inactiveSlotsAreIgnored() {
        let g = makeGraph(capacity: 4, active: 1)
        defer { g.deallocate() }
        setSlot(g, 0, target: 1000, current: 1000)

        let input = InterleavedBufferList(bufferCount: 1, frames: 16, channels: 2)
        fill(input, buffer: 0, value: 0.7)
        let output = InterleavedBufferList(bufferCount: 1, frames: 16, channels: 2)

        _ = RenderCore.render(g.context, input: input.list, output: output.list)
        XCTAssertEqual(cat_slot_read_peak(g.slots + 0), 0.7, accuracy: 1e-5)
        XCTAssertEqual(cat_slot_read_peak(g.slots + 1), 0, accuracy: 1e-9)   // untouched
        let out = output.channelData(buffer: 0)
        XCTAssertEqual(out[0], 0.7, accuracy: 1e-5)
    }
}

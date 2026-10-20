import Foundation
import CoreAudio
import CAtomic

/// Fake backend for the walking skeleton and CI (ARCHITECTURE.md §12).
///
/// Instead of stubbing the engine, the fake drives the REAL RenderCore:
/// a background thread synthesizes per-slot stereo buffers at ~30 Hz and
/// calls RenderCore.render through the same RenderContext the real IOProc
/// would use. Gain, ramps, clamping and peak publishing are therefore
/// exercised for real — only the Core Audio plumbing is fake.
public final class FakeAudioSystem: AudioSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var nextID: AudioObjectID = 1000
    private var renderThread: Thread?
    private var context: UnsafeMutablePointer<RenderContext>?
    public private(set) var renderTicks: Int = 0

    public init() {}

    public func processObjects() throws -> [DiscoveredProcess] { [] }
    public func defaultOutputDevice() throws -> OutputDeviceInfo {
        OutputDeviceInfo(id: 1, uid: "fake-output-uid", name: "Fake Output")
    }

    public func createTap(processes: [AudioObjectID]) throws -> TapHandle {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return TapHandle(id: nextID, uuid: UUID())
    }

    public func destroyTap(_ tap: TapHandle) throws {}

    public func tapFormat(_ tap: TapHandle) throws -> StreamFormat {
        StreamFormat(channels: 2, sampleRate: 48000)
    }

    public func createAggregate(outputUID: String, taps: [TapHandle]) throws -> AggregateHandle {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        return AggregateHandle(id: nextID)
    }

    public func destroyAggregate(_ aggregate: AggregateHandle) throws {
        try? stopRenderLoop(on: aggregate)
    }

    public func aggregateFormat(_ aggregate: AggregateHandle) throws -> StreamFormat {
        StreamFormat(channels: 2, sampleRate: 48000)
    }

    public func installRenderLoop(on aggregate: AggregateHandle,
                                  context: UnsafeMutablePointer<RenderContext>) throws {
        lock.lock(); defer { lock.unlock() }
        self.context = context
    }

    public func startRenderLoop(on aggregate: AggregateHandle) throws {
        lock.lock(); defer { lock.unlock() }
        guard renderThread == nil, let ctx = context else { return }
        let thread = Thread { [weak self] in
            self?.renderLoop(ctx)
        }
        thread.name = "mixbar-fake-render"
        thread.start()
        renderThread = thread
    }

    public func stopRenderLoop(on aggregate: AggregateHandle) throws {
        lock.lock(); defer { lock.unlock() }
        renderThread?.cancel()
        renderThread = nil
    }

    // MARK: - Synthetic render loop

    private func renderLoop(_ ctx: UnsafeMutablePointer<RenderContext>) {
        let capacity = Int(ctx.pointee.capacity)
        let frames = 512
        let phase = UnsafeMutablePointer<Float>.allocate(capacity: max(1, capacity))
        phase.initialize(repeating: 0, count: max(1, capacity))
        defer { phase.deallocate() }

        while !Thread.current.isCancelled {
            let active = Int(cat_flag_get(ctx.pointee.activeSlots))
            if active > 0 {
                let input = InterleavedBufferList(bufferCount: active, frames: frames, channels: 2)
                for s in 0..<active {
                    let base = input.channelData(buffer: s)
                    for f in 0..<frames {
                        let w = 2 * Float.pi * Float(110 * (s + 1)) / 48000
                        phase[s] += w
                        let sample = sin(phase[s]) * 0.8
                        base[2 * f] = sample
                        base[2 * f + 1] = sample
                    }
                }
                let output = InterleavedBufferList(bufferCount: 1, frames: frames, channels: 2)
                _ = RenderCore.render(ctx, input: input.list, output: output.list)
            }
            lock.lock(); renderTicks += 1; lock.unlock()
            Thread.sleep(forTimeInterval: 1.0 / 30.0)
        }
    }
}

import CoreAudio
import CAtomic
import Darwin

/// Real-time mixing core: read tap buffers, ramp gains, mix, clamp, publish
/// peaks. Pure function over preallocated memory.
///
/// RT rules (ADR-004): no allocation, no locks, no Objective-C/Swift messages,
/// no logging, no I/O.
///
/// Buffer mapping (ASSUMPTION, pinned by spike S2): the aggregate exposes one
/// input stream per tap.
/// - Interleaved:   mNumberBuffers == active, each buffer 2 channels.
/// - Non-interleaved: mNumberBuffers == active * 2, mono pairs per tap.
/// Output is stereo: 1 interleaved buffer or 2 mono buffers.
/// Any other layout renders digital silence (never garbage); that is a bug
/// to resolve in S2 (error taxonomy row 9).
public enum RenderCore {

    public static func render(_ ctx: UnsafePointer<RenderContext>,
                              input: UnsafePointer<AudioBufferList>,
                              output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let out = UnsafeMutableAudioBufferListPointer(output)

        // Resolve output layout (stereo).
        var outL: UnsafeMutablePointer<Float>!
        var outR: UnsafeMutablePointer<Float>!
        var outInterleaved = false
        var outFrames = 0
        if out.count == 1, out[0].mNumberChannels == 2, let data = out[0].mData {
            let base = data.assumingMemoryBound(to: Float.self)
            outInterleaved = true
            outL = base
            outR = base + 1
            outFrames = Int(out[0].mDataByteSize) / (2 * MemoryLayout<Float>.size)
        } else if out.count == 2, out[0].mNumberChannels == 1, out[1].mNumberChannels == 1,
                  let d0 = out[0].mData, let d1 = out[1].mData {
            outL = d0.assumingMemoryBound(to: Float.self)
            outR = d1.assumingMemoryBound(to: Float.self)
            outFrames = Int(out[0].mDataByteSize) / MemoryLayout<Float>.size
        } else {
            zero(output)
            return noErr
        }
        guard outFrames > 0 else {
            zero(output)
            return noErr
        }

        // Resolve input layout.
        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let active = Int(cat_flag_get(ctx.pointee.activeSlots))
        guard active > 0 else {
            zero(output)
            return noErr
        }

        var inInterleaved: Bool
        if inList.count == active {
            inInterleaved = true
        } else if inList.count == active * 2 {
            inInterleaved = false
        } else {
            // Unexpected layout: silence, never garbage (S2 pins mapping).
            zero(output)
            return noErr
        }

        var frames = outFrames
        if inInterleaved {
            for b in 0..<inList.count {
                frames = min(frames, Int(inList[b].mDataByteSize) / (2 * MemoryLayout<Float>.size))
            }
        } else {
            for b in 0..<inList.count {
                frames = min(frames, Int(inList[b].mDataByteSize) / MemoryLayout<Float>.size)
            }
        }
        guard frames > 0 else {
            zero(output)
            return noErr
        }

        let rampStep: Float = 1000.0 / Float(max(1, ctx.pointee.rampFrames))

        for f in 0..<frames {
            var sumL: Float = 0
            var sumR: Float = 0
            for s in 0..<active {
                let li = inInterleaved ? s : 2 * s
                let ri = inInterleaved ? s : 2 * s + 1
                guard li < inList.count, ri < inList.count,
                      let ld = inList[li].mData, let rd = inList[ri].mData else { continue }

                let slot = ctx.pointee.slots + s
                let target = Float(cat_slot_get_target(slot))
                var cur = Float(slot.pointee.current_milli)
                if cur < target {
                    cur = min(target, cur + rampStep)
                } else if cur > target {
                    cur = max(target, cur - rampStep)
                }
                slot.pointee.current_milli = UInt32(cur)
                let gain = cur / 1000.0

                let inL = ld.assumingMemoryBound(to: Float.self)
                let inR = rd.assumingMemoryBound(to: Float.self)
                let idx = inInterleaved ? 2 * f : f
                let rawL = inL[idx]
                let rawR = inR[idx]

                // Pre-gain level: the permission heuristic must see that a
                // tap is alive even when the user muted the slot (gain 0).
                let inputMag = max(abs(rawL), abs(rawR))
                if inputMag > slot.pointee.input_peak { slot.pointee.input_peak = inputMag }

                let l = rawL * gain
                let r = rawR * gain
                sumL += l
                sumR += r

                let mag = max(abs(l), abs(r))
                if mag > slot.pointee.peak { slot.pointee.peak = mag }
            }
            let o = outInterleaved ? 2 * f : f
            outL[o] = min(1, max(-1, sumL))
            outR[o] = min(1, max(-1, sumR))
        }

        // Publish per-slot peaks (lock-free): post-gain for the UI meters,
        // pre-gain for the permission heuristic.
        for s in 0..<active {
            let slot = ctx.pointee.slots + s
            cat_slot_publish_peak(slot, slot.pointee.peak)
            cat_slot_publish_input_peak(slot, slot.pointee.input_peak)
            slot.pointee.peak = 0
            slot.pointee.input_peak = 0
        }
        return noErr
    }

    private static func zero(_ output: UnsafeMutablePointer<AudioBufferList>) {
        let abp = UnsafeMutableAudioBufferListPointer(output)
        for i in 0..<abp.count {
            guard let data = abp[i].mData else { continue }
            memset(data, 0, Int(abp[i].mDataByteSize))
        }
    }
}

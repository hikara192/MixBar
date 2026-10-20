import Foundation
import CoreAudio
import AudioToolbox
import Darwin
import CAtomic

// Spike S1 (ARCHITECTURE.md §15): tap a real process, feed it through a
// private aggregate, and measure that gain actually reaches the output.
// Throwaway tool — no AppKit, no UI, textual diagnostics only.

setvbuf(stdout, nil, _IONBF, 0)

let systemObject = AudioObjectID(kAudioObjectSystemObject)

enum SpikeError: Error, CustomStringConvertible {
    case os(OSStatus, String)
    case usage(String)

    var description: String {
        switch self {
        case .os(let status, let call): return "Core Audio error \(status) in \(call)"
        case .usage(let text): return text
        }
    }
}

func check(_ status: OSStatus, _ call: String) throws {
    guard status == noErr else { throw SpikeError.os(status, call) }
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                               mElement: kAudioObjectPropertyElementMain)
}

func readScalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
    var addr = address(selector, scope)
    var size = UInt32(MemoryLayout<T>.size)
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { buffer.deallocate() }
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, buffer),
              "read \(selector)")
    return buffer.pointee
}

func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                  scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [T] {
    var addr = address(selector, scope)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size),
              "size of \(selector)")
    let count = Int(size) / MemoryLayout<T>.size
    guard count > 0 else { return [] }
    let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
    defer { buffer.deallocate() }
    var dataSize = size
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &dataSize, buffer),
              "read \(selector)")
    return Array(UnsafeBufferPointer(start: buffer, count: count))
}

struct ProcessRow {
    let object: AudioObjectID
    let pid: pid_t
    let bundle: String?
    let running: Bool
}

func processObjects() throws -> [ProcessRow] {
    let ids: [AudioObjectID] = try readArray(systemObject,
                                             kAudioHardwarePropertyProcessObjectList)
    var rows: [ProcessRow] = []
    for id in ids {
        let pid: pid_t = (try? readScalar(id, kAudioProcessPropertyPID)) ?? -1
        guard pid > 0 else { continue }
        let bundle: CFString? = try? readScalar(id, kAudioProcessPropertyBundleID)
        let running: UInt32 = (try? readScalar(id, kAudioProcessPropertyIsRunningOutput)) ?? 0
        rows.append(ProcessRow(object: id, pid: pid,
                               bundle: bundle as String?,
                               running: running != 0))
    }
    return rows
}

func defaultOutput() throws -> (id: AudioObjectID, uid: String, name: String) {
    let id: AudioObjectID = try readScalar(systemObject, kAudioHardwarePropertyDefaultOutputDevice)
    let uid: CFString = try readScalar(id, kAudioDevicePropertyDeviceUID)
    let name: CFString = try readScalar(id, kAudioObjectPropertyName)
    return (id, uid as String, name as String)
}

func outputChannels(_ object: AudioObjectID) throws -> Int {
    var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size),
              "stream config size")
    guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                               alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { raw.deallocate() }
    try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw),
              "stream config")
    let list = raw.assumingMemoryBound(to: AudioBufferList.self)
    let abp = UnsafeMutableAudioBufferListPointer(list)
    return abp.reduce(0) { $0 + Int($1.mNumberChannels) }
}

func fourCC(_ value: UInt32) -> String {
    let bytes = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                 UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08x", value)
}

func rms(_ value: Float) -> Float {
    value.squareRoot()
}

// MARK: - IOProc state

final class SpikeState {
    let slot = UnsafeMutablePointer<cat_slot_t>.allocate(capacity: 1)
    var callbacks = 0
    var inRMS: Float = 0
    var outRMS: Float = 0
    var inBuffers: UInt32 = 0
    var inChannels0: UInt32 = 0
    var inBytes0: UInt32 = 0
    var outBuffers: UInt32 = 0
    var outChannels0: UInt32 = 0
    var outBytes0: UInt32 = 0
    var frames: UInt32 = 0

    init() {
        slot.initialize(to: cat_slot_t())
        cat_slot_set_target(slot, 1000)
    }

    deinit {
        slot.deinitialize(count: 1)
        slot.deallocate()
    }
}

// MARK: - Main

func run() throws {
    let args = CommandLine.arguments

    if args.contains("--list") {
        let rows = try processObjects()
        print("pid\tobject\tplaying\tbundle")
        for row in rows.sorted(by: { $0.pid < $1.pid }) {
            print("\(row.pid)\t\(row.object)\t\(row.running ? "yes" : "no")\t\(row.bundle ?? "-")")
        }
        return
    }

    var requestedPID: pid_t? = nil
    if let index = args.firstIndex(of: "--pid"), index + 1 < args.count {
        requestedPID = pid_t(args[index + 1])
    }

    let rows = try processObjects()
    let target: ProcessRow
    if let pid = requestedPID {
        guard let row = rows.first(where: { $0.pid == pid }) else {
            throw SpikeError.usage("No audio process with pid \(pid). Try --list while audio is playing.")
        }
        target = row
    } else {
        guard let row = rows.first(where: { $0.running }) else {
            throw SpikeError.usage("No process is producing audio. Start playback, then retry (or pass --pid).")
        }
        target = row
    }

    print("target: pid \(target.pid), object \(target.object), bundle \(target.bundle ?? "-"), playing \(target.running)")

    let output = try defaultOutput()
    print("output: \(output.name) (uid \(output.uid)), id \(output.id)")

    guard #available(macOS 14.2, *) else {
        throw SpikeError.usage("process taps require macOS 14.2+")
    }

    // 1. Tap
    let desc = CATapDescription(stereoMixdownOfProcesses: [target.object])
    desc.uuid = UUID()
    desc.muteBehavior = .mutedWhenTapped
    var tapID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateProcessTap(desc, &tapID), "AudioHardwareCreateProcessTap")
    defer { _ = AudioHardwareDestroyProcessTap(tapID) }
    print("tap created: \(tapID), uuid \(desc.uuid.uuidString)")

    if let format: AudioStreamBasicDescription = try? readScalar(tapID, kAudioTapPropertyFormat) {
        let isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        print("tap format: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) ch, " +
              "\(format.mBitsPerChannel) bit, \(fourCC(format.mFormatID)), float \(isFloat), " +
              "bytes/frame \(format.mBytesPerFrame)")
    } else {
        print("tap format: unavailable")
    }

    // 2. Aggregate
    let dict: [String: Any] = [
        kAudioAggregateDeviceNameKey: "MixBar Spike",
        kAudioAggregateDeviceUIDKey: "com.mixbar.spike." + UUID().uuidString,
        kAudioAggregateDeviceMainSubDeviceKey: output.uid,
        kAudioAggregateDeviceIsPrivateKey: 1,
        kAudioAggregateDeviceIsStackedKey: 0,
        kAudioAggregateDeviceTapAutoStartKey: 1,
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
        kAudioAggregateDeviceTapListKey: [[
            kAudioSubTapUIDKey: desc.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: 1,
        ]],
    ]
    var aggID = AudioObjectID(kAudioObjectUnknown)
    try check(AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID),
              "AudioHardwareCreateAggregateDevice")
    defer { _ = AudioHardwareDestroyAggregateDevice(aggID) }

    let rate: Float64 = (try? readScalar(aggID, kAudioDevicePropertyNominalSampleRate,
                                         scope: kAudioDevicePropertyScopeOutput)) ?? 0
    let channels = (try? outputChannels(aggID)) ?? 0
    print("aggregate created: \(aggID), \(rate) Hz, \(channels) ch")

    // 3. IOProc
    let state = SpikeState()
    let ioProc: AudioDeviceIOProc = { _, _, inData, _, outData, _, clientData in
        guard let clientData else { return noErr }
        let state = Unmanaged<SpikeState>.fromOpaque(clientData).takeUnretainedValue()
        state.callbacks += 1

        let inList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
        let outList = UnsafeMutableAudioBufferListPointer(outData)
        state.inBuffers = UInt32(inList.count)
        state.outBuffers = UInt32(outList.count)
        if inList.count > 0 {
            state.inChannels0 = inList[0].mNumberChannels
            state.inBytes0 = inList[0].mDataByteSize
        }
        if outList.count > 0 {
            state.outChannels0 = outList[0].mNumberChannels
            state.outBytes0 = outList[0].mDataByteSize
        }

        let gain = Float(cat_slot_get_target(state.slot)) / 1000.0

        var inL: UnsafePointer<Float>? = nil
        var inR: UnsafePointer<Float>? = nil
        var inStride = 1
        if inList.count == 1, inList[0].mNumberChannels == 2, let data = inList[0].mData {
            let base = UnsafePointer(data.assumingMemoryBound(to: Float.self))
            inL = base
            inR = base + 1
            inStride = 2
        } else if inList.count >= 2, let d0 = inList[0].mData, let d1 = inList[1].mData {
            inL = UnsafePointer(d0.assumingMemoryBound(to: Float.self))
            inR = UnsafePointer(d1.assumingMemoryBound(to: Float.self))
            inStride = 1
        }

        var outL: UnsafeMutablePointer<Float>? = nil
        var outR: UnsafeMutablePointer<Float>? = nil
        var outStride = 1
        var outFrames = 0
        if outList.count == 1, outList[0].mNumberChannels == 2, let data = outList[0].mData {
            let base = data.assumingMemoryBound(to: Float.self)
            outL = base
            outR = base + 1
            outStride = 2
            outFrames = Int(outList[0].mDataByteSize) / (2 * MemoryLayout<Float>.size)
        } else if outList.count >= 2, let d0 = outList[0].mData, let d1 = outList[1].mData {
            outL = d0.assumingMemoryBound(to: Float.self)
            outR = d1.assumingMemoryBound(to: Float.self)
            outFrames = Int(outList[0].mDataByteSize) / MemoryLayout<Float>.size
        }

        guard let ol = outL, let or = outR, outFrames > 0 else { return noErr }

        var frames = outFrames
        if inList.count > 0 {
            let inBytes = Int(inList[0].mDataByteSize)
            let perFrame = inStride == 2 ? 2 * MemoryLayout<Float>.size
                                         : MemoryLayout<Float>.size
            frames = min(frames, inBytes / perFrame)
        }
        state.frames = UInt32(frames)

        var sumIn: Float = 0
        var sumOut: Float = 0
        for f in 0..<frames {
            let rawL = inL?[f * inStride] ?? 0
            let rawR = inR?[f * inStride] ?? 0
            let l = rawL * gain
            let r = rawR * gain
            ol[f * outStride] = l
            or[f * outStride] = r
            sumIn += rawL * rawL + rawR * rawR
            sumOut += l * l + r * r
        }
        if frames > 0 {
            let norm = Float(2 * frames)
            state.inRMS = rms(sumIn / norm)
            state.outRMS = rms(sumOut / norm)
        }
        return noErr
    }

    var procID: AudioDeviceIOProcID?
    let clientData = Unmanaged.passUnretained(state).toOpaque()
    try check(AudioDeviceCreateIOProcID(aggID, ioProc, clientData, &procID),
              "AudioDeviceCreateIOProcID")
    guard let procID else { throw SpikeError.usage("IOProc was not created") }
    defer {
        _ = AudioDeviceStop(aggID, procID)
        _ = AudioDeviceDestroyIOProcID(aggID, procID)
    }

    try check(AudioDeviceStart(aggID, procID), "AudioDeviceStart")
    print("render loop started (Ctrl-C is safe: HAL destroys taps and restores audio)\n")

    // 4. Gain phases
    for (index, milli) in [1000, 500, 0, 1000].enumerated() {
        cat_slot_set_target(state.slot, UInt16(milli))
        Thread.sleep(forTimeInterval: 1.0)
        let gain = Float(milli) / 1000.0
        let ratio = state.inRMS > 0.0001 ? state.outRMS / state.inRMS : 0
        print(String(format: "phase %d  gain %.3f  inRMS %.5f  outRMS %.5f  out/in %.3f  callbacks %d",
                     index + 1, gain, state.inRMS, state.outRMS, ratio, state.callbacks))
    }

    print("")
    print("layout: input \(state.inBuffers) buffer(s), first \(state.inChannels0) ch, \(state.inBytes0) bytes; " +
          "output \(state.outBuffers) buffer(s), first \(state.outChannels0) ch, \(state.outBytes0) bytes; " +
          "frames/callback \(state.frames)")
    print("(buffer order hypothesis: 1 buffer = interleaved stereo, 2 buffers = non-interleaved L/R)")
    print("cleanup: stop IOProc -> destroy aggregate -> destroy tap")
}

do {
    try run()
    print("DONE")
    exit(0)
} catch {
    print("FAILED: \(error)")
    exit(1)
}

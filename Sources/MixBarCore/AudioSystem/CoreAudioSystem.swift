import CoreAudio
import AudioToolbox
import Foundation
import os

/// Real Core Audio backend, ADR-001 topology A.
///
/// STATUS: compiles against the macOS SDK, runtime behavior is UNVALIDATED
/// until spikes S1–S4 pass (ARCHITECTURE.md §15). The app selects this
/// backend only when MIXBAR_ENGINE=core is set (see README).
///
/// All calls run on the GraphOwner queue (blocking is fine there, never on
/// the main thread — ARCHITECTURE.md Q8).
public final class CoreAudioSystem: AudioSystem, @unchecked Sendable {
    private let log = Logger(subsystem: "com.mixbar.core", category: "core-audio")
    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var ioProcID: AudioDeviceIOProcID?
    private var renderTarget: AggregateHandle?

    public init() {}

    // MARK: - Discovery

    public func processObjects() throws -> [DiscoveredProcess] {
        let ids: [AudioObjectID] = try readArray(systemObject,
                                                 kAudioHardwarePropertyProcessObjectList)
        var result: [DiscoveredProcess] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            let pid: pid_t = (try? readScalar(id, kAudioProcessPropertyPID)) ?? -1
            guard pid > 0 else { continue }
            let bundleID: CFString? = try? readScalar(id, kAudioProcessPropertyBundleID)
            let running: UInt32 = (try? readScalar(id, kAudioProcessPropertyIsRunningOutput)) ?? 0
            result.append(DiscoveredProcess(objectID: id, pid: pid,
                                            bundleID: bundleID as String?,
                                            isRunningOutput: running != 0))
        }
        return result
    }

    public func defaultOutputDevice() throws -> OutputDeviceInfo {
        let id: AudioObjectID = try readScalar(systemObject,
                                               kAudioHardwarePropertyDefaultOutputDevice)
        let uid: CFString = try readScalar(id, kAudioDevicePropertyDeviceUID)
        let name: CFString = try readScalar(id, kAudioObjectPropertyName)
        return OutputDeviceInfo(id: id, uid: uid as String, name: name as String)
    }

    // MARK: - Taps

    public func createTap(processes: [AudioObjectID]) throws -> TapHandle {
        guard #available(macOS 14.2, *) else {
            throw AudioSystemError.unsupported("process taps require macOS 14.2 or later")
        }
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.uuid = UUID()
        desc.muteBehavior = .mutedWhenTapped
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(desc, &tapID), "AudioHardwareCreateProcessTap")
        return TapHandle(id: tapID, uuid: desc.uuid)
    }

    public func destroyTap(_ tap: TapHandle) throws {
        guard #available(macOS 14.2, *) else { return }
        try check(AudioHardwareDestroyProcessTap(tap.id), "AudioHardwareDestroyProcessTap")
    }

    public func tapFormat(_ tap: TapHandle) throws -> StreamFormat {
        let asbd: AudioStreamBasicDescription =
            try readScalar(tap.id, kAudioTapPropertyFormat)
        return StreamFormat(channels: Int(asbd.mChannelsPerFrame),
                             sampleRate: asbd.mSampleRate)
    }

    // MARK: - Aggregate

    public func createAggregate(outputUID: String, taps: [TapHandle]) throws -> AggregateHandle {
        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "MixBar",
            kAudioAggregateDeviceUIDKey: "com.mixbar.aggregate." + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: 1,
            kAudioAggregateDeviceIsStackedKey: 0,
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: taps.map { tap in
                [kAudioSubTapUIDKey: tap.uuid.uuidString,
                 kAudioSubTapDriftCompensationKey: 1]
            },
        ]
        var aggID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID),
                  "AudioHardwareCreateAggregateDevice")
        return AggregateHandle(id: aggID)
    }

    public func destroyAggregate(_ aggregate: AggregateHandle) throws {
        if let procID = ioProcID {
            _ = AudioDeviceStop(aggregate.id, procID)
            _ = AudioDeviceDestroyIOProcID(aggregate.id, procID)
            ioProcID = nil
        }
        try check(AudioHardwareDestroyAggregateDevice(aggregate.id),
                  "AudioHardwareDestroyAggregateDevice")
        if renderTarget == aggregate { renderTarget = nil }
    }

    public func aggregateFormat(_ aggregate: AggregateHandle) throws -> StreamFormat {
        let rate: Float64 = try readScalar(aggregate.id, kAudioDevicePropertyNominalSampleRate,
                                           scope: kAudioDevicePropertyScopeOutput)
        let channels = try totalOutputChannels(aggregate.id)
        return StreamFormat(channels: channels, sampleRate: rate)
    }

    // MARK: - Render loop

    public func installRenderLoop(on aggregate: AggregateHandle,
                                  context: UnsafeMutablePointer<RenderContext>) throws {
        let callback: AudioDeviceIOProc = { _, _, inInputData, _, outOutputData, _, inClientData in
            guard let inClientData else { return noErr }
            let ctx = inClientData.assumingMemoryBound(to: RenderContext.self)
            return RenderCore.render(ctx, input: inInputData, output: outOutputData)
        }
        var procID = AudioDeviceIOProcID?.none
        try check(AudioDeviceCreateIOProcID(aggregate.id, callback, context, &procID),
                  "AudioDeviceCreateIOProcID")
        ioProcID = procID
        renderTarget = aggregate
    }

    public func startRenderLoop(on aggregate: AggregateHandle) throws {
        guard let procID = ioProcID else {
            throw AudioSystemError.unsupported("render loop not installed")
        }
        try check(AudioDeviceStart(aggregate.id, procID), "AudioDeviceStart")
    }

    public func stopRenderLoop(on aggregate: AggregateHandle) throws {
        guard let procID = ioProcID else { return }
        _ = AudioDeviceStop(aggregate.id, procID)
    }

    deinit {
        // Best effort: taps are process-owned; HAL destroys them on exit and
        // mutedWhenTapped auto-restores audio (the never-silence invariant).
        if let target = renderTarget {
            if let procID = ioProcID {
                _ = AudioDeviceStop(target.id, procID)
                _ = AudioDeviceDestroyIOProcID(target.id, procID)
            }
            _ = AudioHardwareDestroyAggregateDevice(target.id)
        }
    }

    // MARK: - Property helpers

    private func addr(_ selector: AudioObjectPropertySelector,
                      _ scope: AudioObjectPropertyScope) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func check(_ status: OSStatus, _ call: String) throws {
        guard status == noErr else {
            log.error("\(call, privacy: .public) failed: \(status)")
            throw AudioSystemError.osStatus(status, call)
        }
    }

    private func readScalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> T {
        var address = addr(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer),
                  "read \(selector)")
        return buffer.pointee
    }

    private func readArray<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> [T] {
        var address = addr(selector, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size),
                  "size of \(selector)")
        let count = Int(size) / MemoryLayout<T>.size
        guard count > 0 else { return [] }
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        defer { buffer.deallocate() }
        var dataSize = size
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &dataSize, buffer),
                  "read \(selector)")
        return Array(UnsafeBufferPointer(start: buffer, count: count))
    }

    private func totalOutputChannels(_ object: AudioObjectID) throws -> Int {
        var address = addr(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size),
                  "StreamConfiguration size")
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, raw),
                  "StreamConfiguration")
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let abp = UnsafeMutableAudioBufferListPointer(list)
        return abp.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

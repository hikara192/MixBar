import CoreAudio

/// Handles for graph resources. Opaque value types; only AudioSystem creates them.
public struct TapHandle: Sendable, Equatable {
    public let id: AudioObjectID
    public let uuid: UUID
    public init(id: AudioObjectID, uuid: UUID) {
        self.id = id
        self.uuid = uuid
    }
}

public struct AggregateHandle: Sendable, Equatable {
    public let id: AudioObjectID
    public init(id: AudioObjectID) { self.id = id }
}

public struct StreamFormat: Sendable, Equatable {
    public let channels: Int
    public let sampleRate: Float64
    public init(channels: Int, sampleRate: Float64) {
        self.channels = channels
        self.sampleRate = sampleRate
    }
}

public struct DiscoveredProcess: Sendable, Equatable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let isRunningOutput: Bool

    public init(objectID: AudioObjectID, pid: pid_t, bundleID: String?, isRunningOutput: Bool) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.isRunningOutput = isRunningOutput
    }
}

public struct OutputDeviceInfo: Sendable, Equatable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String
    public init(id: AudioObjectID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

public enum AudioSystemError: Error, Sendable, CustomStringConvertible {
    case osStatus(OSStatus, String)
    case unsupported(String)

    public var description: String {
        switch self {
        case .osStatus(let status, let call): return "Core Audio error \(status) in \(call)"
        case .unsupported(let reason): return "Unsupported: \(reason)"
        }
    }
}

/// The seam between MixBar and Core Audio (ADR-004 testability; ARCHITECTURE.md §12).
/// Production: CoreAudioSystem. Tests + walking skeleton: FakeAudioSystem.
public protocol AudioSystem: Sendable {
    func processObjects() throws -> [DiscoveredProcess]
    func defaultOutputDevice() throws -> OutputDeviceInfo

    // stereoMixdown + mutedWhenTapped + private tap (ADR-002)
    func createTap(processes: [AudioObjectID]) throws -> TapHandle
    func destroyTap(_ tap: TapHandle) throws
    func tapFormat(_ tap: TapHandle) throws -> StreamFormat

    // private aggregate on the default output, drift compensation on,
    // tap auto-start (ADR-001)
    func createAggregate(outputUID: String, taps: [TapHandle]) throws -> AggregateHandle
    func destroyAggregate(_ aggregate: AggregateHandle) throws
    func aggregateFormat(_ aggregate: AggregateHandle) throws -> StreamFormat

    func installRenderLoop(on aggregate: AggregateHandle,
                           context: UnsafeMutablePointer<RenderContext>) throws
    func startRenderLoop(on aggregate: AggregateHandle) throws
    func stopRenderLoop(on aggregate: AggregateHandle) throws
}

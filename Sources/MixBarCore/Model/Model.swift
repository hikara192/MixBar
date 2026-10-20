import Foundation

/// Canonical app identity: the grouping key for processes (ADR-003).
public struct AppIdentity: Hashable, Sendable, Codable {
    public let canonicalBundleID: String
    public init(canonicalBundleID: String) { self.canonicalBundleID = canonicalBundleID }
}

/// Desired per-app state. Unity (gain 1.0, not muted) means "leave untouched" —
/// no tap exists for such apps (ADR-002).
public struct DesiredApp: Sendable, Equatable, Codable {
    public var gain: Float   // 0...1
    public var muted: Bool

    public init(gain: Float = 1, muted: Bool = false) {
        self.gain = gain
        self.muted = muted
    }

    public var isUnity: Bool { !muted && gain >= 0.999 }
    public var milliGain: UInt16 {
        let clamped = max(0, min(1, gain))
        return muted ? 0 : UInt16((clamped * 1000).rounded())
    }
}

public enum AppRowState: Sendable, Equatable {
    case unmanaged        // desired = unity, no tap, bit-perfect path
    case managed          // tap live, gain applies
    case degraded(reason: String)  // tap failed / unsupported; audio untouched
    case gone
}

public struct AppRow: Identifiable, Sendable, Equatable {
    public let identity: AppIdentity
    public let displayName: String
    public let isAudible: Bool
    public let rowState: AppRowState
    public var desired: DesiredApp
    public var id: AppIdentity { identity }

    public init(identity: AppIdentity, displayName: String, isAudible: Bool,
                rowState: AppRowState, desired: DesiredApp) {
        self.identity = identity
        self.displayName = displayName
        self.isAudible = isAudible
        self.rowState = rowState
        self.desired = desired
    }
}

public enum EngineState: Sendable, Equatable {
    case idle              // nothing tapped, no aggregate
    case onboarding        // permission flow shown, no taps created
    case active            // aggregate + render loop running, >= 1 tap
    case rebuilding        // tap set or output device changing
    case failed(reason: String)   // graph torn down; audio plays normally
}

public struct MixerSnapshot: Sendable, Equatable {
    public let engine: EngineState
    public let rows: [AppRow]
    public let outputDeviceName: String?
    public let usesFakeEngine: Bool
    /// Heuristic (ADR-005): taps exist, engine is active, but every slot has
    /// been silent for >= 2 s — most likely System Audio Recording is denied.
    public let permissionSuspected: Bool

    public init(engine: EngineState, rows: [AppRow], outputDeviceName: String?,
                usesFakeEngine: Bool, permissionSuspected: Bool = false) {
        self.engine = engine
        self.rows = rows
        self.outputDeviceName = outputDeviceName
        self.usesFakeEngine = usesFakeEngine
        self.permissionSuspected = permissionSuspected
    }
}

public enum MixerIntent: Sendable {
    case setGain(AppIdentity, Float)
    case setMuted(AppIdentity, Bool)
    case setAllAppsGain(Float)
    /// Forget every saved per-app level and unmute everything. Used by the
    /// "Reset all volumes" action in Settings.
    case resetAll
    case retryPermission
    case shutdown
}

public struct AppSetting: Codable, Equatable, Sendable {
    public let bundleID: String
    public var gain: Float
    public var muted: Bool
    public var remember: Bool

    public init(bundleID: String, gain: Float = 1, muted: Bool = false, remember: Bool = true) {
        self.bundleID = bundleID
        self.gain = gain
        self.muted = muted
        self.remember = remember
    }

    public var desired: DesiredApp { DesiredApp(gain: gain, muted: muted) }
}

struct SettingsSchema: Codable {
    var version: Int = 1
    var apps: [AppSetting] = []
}

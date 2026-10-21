import Foundation
import CoreAudio
import Darwin

/// One user-facing app row: a resolved identity plus its audio processes.
public struct DiscoveredApp: Sendable, Equatable {
    public let identity: AppIdentity
    public let displayName: String
    public var processes: [DiscoveredProcess]
    /// True when at least one process is currently producing output. Silent
    /// apps stay listed (users can pre-set their volume), but they get no tap
    /// until they actually play (Reconciler only taps audible apps).
    public var isAudible: Bool

    public init(identity: AppIdentity, displayName: String, processes: [DiscoveredProcess],
                isAudible: Bool = true) {
        self.identity = identity
        self.displayName = displayName
        self.processes = processes
        self.isAudible = isAudible
    }
}

public protocol ProcessCataloging: Sendable {
    func currentApps() -> [DiscoveredApp]
}

/// Real discovery: Core Audio process objects plus the process table, resolved
/// to the owning `.app` bundle through `proc_pidpath` + `Info.plist` (ADR-003).
///
/// Deliberately avoids `NSWorkspace`/`NSRunningApplication`: even reading
/// `processIdentifier` triggers `_fetchDynamicProperties`, a synchronous
/// LaunchServices XPC round-trip that can block the graph queue for seconds or
/// forever when called off the main thread in a menu-bar app.
public final class ProcessCatalog: ProcessCataloging, @unchecked Sendable {
    private let audio: AudioSystem
    private let lock = NSLock()

    /// Info.plist is read once per bundle path.
    private var infoCache: [String: AppInfo?] = [:]
    /// Discovery is capped at ~2 Hz: reconcile runs on every slider movement,
    /// and scanning the process table each time would be wasteful.
    private var cachedApps: [DiscoveredApp] = []
    private var cachedAt: Date = .distantPast
    private static let cacheLifetime: TimeInterval = 0.5

    public init(audioSystem: AudioSystem) {
        self.audio = audioSystem
    }

    /// Lists the user-facing apps currently running on the Mac, including
    /// silent ones. MixBar itself, helpers and system UI agents are filtered.
    public func currentApps() -> [DiscoveredApp] {
        lock.lock()
        if Date().timeIntervalSince(cachedAt) < Self.cacheLifetime {
            let cached = cachedApps
            lock.unlock()
            return cached
        }
        lock.unlock()

        let apps = discoverApps()

        lock.lock()
        cachedApps = apps
        cachedAt = Date()
        lock.unlock()
        return apps
    }

    private func discoverApps() -> [DiscoveredApp] {
        var groups: [String: DiscoveredApp] = [:]

        // 1. Core Audio clients. This keeps third-party menu-bar players that
        // have an audio client but no regular (Dock) window, even while paused.
        let objects = (try? audio.processObjects()) ?? []
        for p in objects {
            guard p.pid != getpid(),
                  let app = resolveApp(pid: p.pid),
                  !Self.isOwnBundle(app.bundleID),
                  !Exclusions.isExcluded(app.bundleID) else { continue }

            if var group = groups[app.bundleID] {
                group.processes.append(p)
                group.isAudible = group.isAudible || p.isRunningOutput
                groups[app.bundleID] = group
            } else {
                groups[app.bundleID] = DiscoveredApp(
                    identity: AppIdentity(canonicalBundleID: app.bundleID),
                    displayName: app.name,
                    processes: [p],
                    isAudible: p.isRunningOutput)
            }
        }

        // 2. Every other user-facing app in the process table, even if it has
        // no Core Audio client yet. Pure syscalls — never LaunchServices.
        var seenPaths: Set<String> = []
        for pid in Self.allPIDs() where pid != getpid() {
            guard let executable = Self.executablePath(pid),
                  let appPath = Self.owningAppBundlePath(executablePath: executable),
                  seenPaths.insert(appPath).inserted,
                  let info = appInfo(at: appPath),
                  info.isUserFacing,
                  Self.shouldList(appPath: appPath, info: info),
                  !Self.isOwnBundle(info.bundleID),
                  !Exclusions.isExcluded(info.bundleID),
                  groups[info.bundleID] == nil else { continue }
            groups[info.bundleID] = DiscoveredApp(
                identity: AppIdentity(canonicalBundleID: info.bundleID),
                displayName: info.name,
                processes: [],
                isAudible: false)
        }

        return groups.values.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Identity resolution (no LaunchServices)

    private struct ResolvedApp { let bundleID: String; let name: String }

    struct AppInfo: Equatable {
        let bundleID: String
        let name: String
        let isUserFacing: Bool
    }

    private func resolveApp(pid: pid_t) -> ResolvedApp? {
        guard let executable = Self.executablePath(pid),
              let appPath = Self.owningAppBundlePath(executablePath: executable),
              let info = appInfo(at: appPath),
              Self.shouldList(appPath: appPath, info: info) else { return nil }
        return ResolvedApp(bundleID: info.bundleID, name: info.name)
    }

    private func appInfo(at appPath: String) -> AppInfo? {
        lock.lock()
        if let cached = infoCache[appPath] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let info = Self.readAppInfo(at: appPath)
        lock.lock()
        infoCache[appPath] = info
        lock.unlock()
        return info
    }

    // MARK: - Process table (syscalls only)

    static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count))
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let written = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, bytes)
        }
        guard written > 0 else { return [] }
        return Array(pids.prefix(Int(written) / MemoryLayout<pid_t>.size))
    }

    static func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Outermost `.app` containing the executable, so helpers nested inside
    /// `Foo.app/Contents/...` group under Foo, not under a helper bundle.
    static func owningAppBundlePath(executablePath: String) -> String? {
        let components = executablePath.split(separator: "/", omittingEmptySubsequences: true)
        var path = ""
        for component in components {
            path += "/" + component
            if component.hasSuffix(".app") { return path }
        }
        return nil
    }

    static func readAppInfo(at appPath: String) -> AppInfo? {
        let plistPath = appPath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              let raw = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil),
              let dict = raw as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String else { return nil }

        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? bundleID
        let isUIElement = boolValue(dict["LSUIElement"]) ?? false
        let isBackgroundOnly = boolValue(dict["LSBackgroundOnly"]) ?? false
        return AppInfo(bundleID: bundleID, name: name,
                       isUserFacing: !isUIElement && !isBackgroundOnly)
    }

    /// User-installed apps (including third-party menu-bar players such as
    /// Yandex Music) are always eligible. System apps are eligible only from
    /// `/System/Applications` and only when they are user-facing, which keeps
    /// Control Center, Notification Center, Siri and WebKit helpers out.
    static func shouldList(appPath: String, info: AppInfo) -> Bool {
        if appPath.hasPrefix("/System/") {
            // Safari and other stock apps live behind the cryptex mount:
            // /System/Volumes/Preboot/Cryptexes/App/System/Applications/...
            // `contains` covers both that and the normal /System/Applications.
            return appPath.contains("/System/Applications/") && info.isUserFacing
        }
        return true
    }

    static func isOwnBundle(_ bundleID: String) -> Bool {
        let own = Bundle.main.bundleIdentifier ?? "com.mixbar.app"
        return bundleID == own || bundleID == "com.mixbar.app"
    }

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            return string == "1" || string.lowercased() == "true"
        }
        return nil
    }
}

/// Editable exclusion list (ADR-003): pro-audio hosts manage their own audio;
/// fighting them risks routing conflicts. System audio daemons are hidden by
/// identity resolution (no owning app) instead.
public enum Exclusions {
    public static let bundleIDs: Set<String> = [
        "com.apple.logic10",
        "com.apple.garageband10",
        "com.ableton.live",
        "com.avid.protools",
        "com.image-line.flstudio",
    ]

    public static func isExcluded(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}

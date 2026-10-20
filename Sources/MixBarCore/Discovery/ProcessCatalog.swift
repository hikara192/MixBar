import Foundation
import CoreAudio
import AppKit

/// One user-facing app row: a resolved identity plus its audio processes.
public struct DiscoveredApp: Sendable, Equatable {
    public let identity: AppIdentity
    public let displayName: String
    public var processes: [DiscoveredProcess]

    public init(identity: AppIdentity, displayName: String, processes: [DiscoveredProcess]) {
        self.identity = identity
        self.displayName = displayName
        self.processes = processes
    }
}

public protocol ProcessCataloging: Sendable {
    func currentApps() -> [DiscoveredApp]
}

/// Real discovery: Core Audio process objects grouped into app rows via
/// public APIs (ADR-003): NSRunningApplication bundle IDs, parent-chain walk
/// for helper processes, editable exclusion list for pro-audio hosts and
/// system daemons.
public final class ProcessCatalog: ProcessCataloging, @unchecked Sendable {
    private let audio: AudioSystem

    public init(audioSystem: AudioSystem) {
        self.audio = audioSystem
    }

    public func currentApps() -> [DiscoveredApp] {
        guard let objects = try? audio.processObjects() else { return [] }
        var groups: [String: DiscoveredApp] = [:]
        for p in objects where p.isRunningOutput {
            guard let resolved = resolve(pid: p.pid) else { continue }   // hidden system daemon
            guard !Exclusions.isExcluded(resolved.bundle) else { continue }
            if var group = groups[resolved.bundle] {
                group.processes.append(p)
                groups[resolved.bundle] = group
            } else {
                groups[resolved.bundle] = DiscoveredApp(
                    identity: AppIdentity(canonicalBundleID: resolved.bundle),
                    displayName: resolved.name,
                    processes: [p])
            }
        }
        return groups.values.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Identity resolution (public APIs only)

    private struct Resolved { let bundle: String; let name: String }

    private func resolve(pid: pid_t) -> Resolved? {
        if let app = NSRunningApplication(processIdentifier: pid),
           let bid = app.bundleIdentifier,
           !isHelperBundleID(bid) {
            return Resolved(bundle: bid, name: app.localizedName ?? bid)
        }
        // Helper process: walk the parent chain up to 8 hops.
        var current = pid
        for _ in 0..<8 {
            guard let parent = parentPID(of: current), parent > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: parent),
               let bid = app.bundleIdentifier {
                return Resolved(bundle: bid, name: app.localizedName ?? bid)
            }
            current = parent
        }
        return nil
    }

    private func isHelperBundleID(_ bundleID: String) -> Bool {
        let lower = bundleID.lowercased()
        return lower.contains("helper") || lower.contains("renderer")
    }

    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        return pid_t(info.pbi_ppid)
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

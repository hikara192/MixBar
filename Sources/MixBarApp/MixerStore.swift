import Foundation
import AppKit
import Observation
import MixBarCore

/// UI-facing store (ARCHITECTURE.md §4, ADR-004): the UI observes immutable
/// snapshots; it never touches Core Audio or the graph directly.
@MainActor @Observable
final class MixerStore {
    let graph: GraphOwner
    private(set) var snapshot: MixerSnapshot

    /// Peak levels smoothed for the UI. Raw peaks are published at audio rate
    /// (atomic reads); the 30 Hz poll below keeps the fastest attack and lets
    /// the bar fall with a fixed decay, which removes one-frame flicker
    /// without adding another timer.
    private(set) var levels: [AppIdentity: Float] = [:]

    /// App icons are expensive to resolve (LaunchServices lookup + icon
    /// extraction), so resolve once per bundle ID and keep the result.
    /// Not observed: the cache is an implementation detail, and filling it
    /// from a view body must not invalidate that body.
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]
    @ObservationIgnored private var missingIcons: Set<String> = []

    private static let decayPerTick: Float = 0.82
    private static let levelFloor: Float = 0.001

    init(graph: GraphOwner) {
        self.graph = graph
        self.snapshot = graph.snapshot()
        // UI-rate polling (30 Hz): snapshots and meters. Not audio rate;
        // peaks cross the boundary via atomic reads (RenderContext).
        Task { @MainActor [weak self] in
            while let self {
                self.refresh()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func refresh() {
        snapshot = graph.snapshot()
        updateLevels(for: snapshot.rows)
    }

    private func updateLevels(for rows: [AppRow]) {
        var next: [AppIdentity: Float] = [:]
        next.reserveCapacity(rows.count)
        for row in rows {
            let raw = min(1, max(0, graph.meter(for: row.identity)))
            let previous = levels[row.identity] ?? 0
            let decayed = previous * Self.decayPerTick
            // Fast attack, smooth release: a new peak shows immediately, the
            // fall is exponential. Below the floor the bar is simply at rest.
            let level = max(raw, decayed)
            next[row.identity] = level < Self.levelFloor ? 0 : level
        }
        levels = next
    }

    /// Smoothed 0...1 level for the row's meter.
    func meter(for id: AppIdentity) -> Float {
        levels[id] ?? 0
    }

    /// Bundle icon for the row, if LaunchServices can resolve it.
    func icon(for id: AppIdentity) -> NSImage? {
        let key = id.canonicalBundleID
        if let cached = iconCache[key] { return cached }
        guard !missingIcons.contains(key) else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) else {
            // Negative results are cached too: rows refresh at 30 Hz and a
            // lookup miss is just as expensive as a hit.
            missingIcons.insert(key)
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        iconCache[key] = icon
        return icon
    }

    func setGain(_ gain: Float, for id: AppIdentity) {
        graph.submit(.setGain(id, gain))
    }

    func setMuted(_ muted: Bool, for id: AppIdentity) {
        graph.submit(.setMuted(id, muted))
    }

    /// Sets every visible app back to unity and forgets all saved levels.
    func resetAllVolumes() {
        graph.submit(.resetAll)
    }

    /// Global-hotkey action: mute every audible app if at least one is
    /// unmuted, otherwise unmute all of them. Silent rows are ignored so
    /// they cannot flip the toggle direction.
    func toggleMuteAll() {
        let rows = snapshot.rows.filter(\.isAudible)
        guard !rows.isEmpty else { return }
        let shouldMute = rows.contains { !$0.desired.muted }
        for row in rows {
            setMuted(shouldMute, for: row.identity)
        }
    }

    func retryPermission() {
        graph.submit(.retryPermission)
    }

    /// Opens the privacy pane where System Audio Recording lives. Pane IDs
    /// differ between macOS releases, so try the known ones in order.
    func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func quit() {
        // Safe by design: HAL destroys process-owned taps on exit and
        // mutedWhenTapped auto-restores audio (never-silence invariant).
        graph.submit(.shutdown)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            NSApplication.shared.terminate(nil)
        }
    }
}

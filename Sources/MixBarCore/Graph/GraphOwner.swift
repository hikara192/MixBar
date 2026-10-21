import Foundation
import CoreAudio
import CAtomic
import os

/// Single writer for the audio graph (ADR-004). Owns taps, the aggregate,
/// the render context and slot assignment. All Core Audio calls happen on
/// its private serial queue — never on the main thread (ARCHITECTURE.md Q8).
///
/// The only state shared with the real-time path is the slot table, accessed
/// exclusively through the CAtomic helpers (wait-free). The only state
/// shared with the UI is the snapshot (lock-guarded) and the peaks (atomic).
public final class GraphOwner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "mixbar.graph", qos: .userInitiated)
    private let pollTimer: DispatchSourceTimer

    private let audio: AudioSystem
    private let catalog: ProcessCataloging
    private let settings: SettingsStore
    private let usesFakeEngine: Bool
    private let log = Logger(subsystem: "com.mixbar.core", category: "graph")

    // MARK: - Data plane memory

    private let capacity = 16
    private let slots: UnsafeMutablePointer<cat_slot_t>
    private let activeSlots: UnsafeMutablePointer<cat_flag_t>
    private let context: UnsafeMutablePointer<RenderContext>

    // MARK: - Slot identity mapping (slotLock-guarded)

    private let slotLock = NSLock()
    private var identitySlots: [AppIdentity: Int] = [:]

    // MARK: - Snapshot publication (snapshotLock-guarded)

    private let snapshotLock = NSLock()
    private var snapshotValue: MixerSnapshot

    // MARK: - Actual graph state (queue-confined)

    private var taps: [AppIdentity: TapHandle] = [:]
    private var aggregate: AggregateHandle?
    private var degraded: Set<AppIdentity> = []
    private var engineState: EngineState = .idle
    private var outputName: String?
    private var appNapActivity: NSObjectProtocol?
    private var currentOutputID: AudioObjectID?
    private var silentSince: Date?
    private var permissionSuspected = false
    private var permissionBlocked = false
    private var retryNotBefore: Date?

    // MARK: - Init

    public init(audioSystem: AudioSystem, catalog: ProcessCataloging,
                settings: SettingsStore, fakeEngine: Bool) {
        audio = audioSystem
        self.catalog = catalog
        self.settings = settings
        usesFakeEngine = fakeEngine

        slots = UnsafeMutablePointer<cat_slot_t>.allocate(capacity: capacity)
        for i in 0..<capacity {
            slots[i] = cat_slot_t()
            cat_slot_set_target(slots + i, 1000)
            (slots + i).pointee.current_milli = 1000
        }
        activeSlots = UnsafeMutablePointer<cat_flag_t>.allocate(capacity: 1)
        activeSlots.pointee = cat_flag_t()
        cat_flag_set(activeSlots, 0)
        context = UnsafeMutablePointer<RenderContext>.allocate(capacity: 1)
        context.pointee = RenderContext(slots: slots, capacity: capacity,
                                        activeSlots: activeSlots,
                                        rampFrames: 480, frameRate: 48000,
                                        outputChannels: 2)

        snapshotValue = MixerSnapshot(engine: .idle, rows: [], outputDeviceName: nil,
                                      usesFakeEngine: fakeEngine)

        pollTimer = DispatchSource.makeTimerSource(queue: queue)
        pollTimer.schedule(deadline: .now() + 1.0, repeating: 1.0)   // 1 Hz fallback poll (A6)
        pollTimer.setEventHandler { [weak self] in self?.reconcile() }
        pollTimer.activate()

        queue.async { self.reconcile() }
    }

    // MARK: - Public API (thread-safe; called from MainActor and tests)

    public func submit(_ intent: MixerIntent) {
        queue.async {
            self.retryNotBefore = nil   // user action retries immediately
            self.handle(intent)
            self.reconcile()
        }
    }

    public func snapshot() -> MixerSnapshot {
        snapshotLock.lock(); defer { snapshotLock.unlock() }
        return snapshotValue
    }

    public func meter(for identity: AppIdentity) -> Float {
        slotLock.lock(); defer { slotLock.unlock() }
        guard let slot = identitySlots[identity] else { return 0 }
        return cat_slot_read_peak(slots + slot)
    }

    public func shutdown() {
        dispatchPrecondition(condition: .notOnQueue(queue))
        queue.sync {
            teardownAll()
            pollTimer.cancel()
        }
        settings.flushNow()
    }

    deinit {
        // Explicit shutdown() is expected. If the owner is dropped anyway,
        // taps are process-owned: HAL destroys them on exit and
        // mutedWhenTapped auto-restores audio (never-silence invariant).
        pollTimer.cancel()
    }

    // MARK: - Reconcile (queue-confined)

    private func reconcile() {
        // Permission failure is sticky: retrying automatically would mute the
        // affected apps again for seconds each cycle. Only an explicit
        // retryPermission intent clears it.
        if permissionBlocked { return }
        // Backoff after a failed aggregate: retry at most every 5 s, or
        // immediately on the next user intent (submit).
        if let retry = retryNotBefore, Date() < retry { return }

        let apps = catalog.currentApps()
        refreshOutputDevice()
        let desired = settings.desiredState()
        let actual = ActualGraphState(taps: Set(taps.keys), hasAggregate: aggregate != nil)
        // Only apps that are actually outputting get a tap: silent apps stay
        // in the list with their saved volume, and are tapped on next sound.
        let audible = apps.filter(\.isAudible).map(\.identity)
        let ops = Reconciler.plan(desired: desired, audible: audible,
                                  actual: actual, capacity: capacity)
        execute(ops, apps: apps)
        updatePermissionHeuristic()
        publishSnapshot(apps: apps, desired: desired)
    }

    /// Keep the UI's output-device name fresh even when nothing is being mixed.
    /// Previously the name was only learned while building the aggregate, so an
    /// idle graph showed "No output device" on a perfectly fine Mac.
    ///
    /// If the output changed (user switch, AirPods connect/disconnect) and
    /// taps are live, rebuild the aggregate. Taps stay alive; only the rebuild
    /// window is silent (ARCHITECTURE.md §8.4).
    private func refreshOutputDevice() {
        guard let out = try? audio.defaultOutputDevice() else { return }
        outputName = out.name
        guard !taps.isEmpty, aggregate != nil,
              let current = currentOutputID, current != out.id else { return }
        log.notice("default output changed to \(out.name, privacy: .public); rebuilding")
        rebuildAggregate()
    }

    /// ADR-005 heuristic: there is no public permission preflight, so we detect
    /// the common failure mode — taps exist, engine active, all slots silent
    /// for >= 2 s. Runs at 1 Hz; false positives are possible (all managed apps
    /// paused), so this drives a hint only, never an error path.
    ///
    /// The silence is measured **before** the mixer gain: muting an app (or
    /// setting it to 0%) silences our output, but the tap still delivers audio
    /// and must not look like a dead capture. If every managed slot is
    /// intentionally silenced, silence is expected and the heuristic is off.
    private func updatePermissionHeuristic() {
        guard !usesFakeEngine, !taps.isEmpty, engineState == .active else {
            silentSince = nil
            permissionSuspected = false
            return
        }
        var peak: Float = 0
        var anyTargetOpen = false
        slotLock.lock()
        for slot in identitySlots.values where slot < capacity {
            peak = max(peak, cat_slot_read_input_peak(slots + slot))
            if cat_slot_get_target(slots + slot) > 0 { anyTargetOpen = true }
        }
        slotLock.unlock()

        let step = Self.permissionHeuristicStep(inputPeak: peak,
                                               anyTargetOpen: anyTargetOpen,
                                               silentSince: silentSince,
                                               now: Date())
        silentSince = step.silentSince
        permissionSuspected = step.permissionSuspected

        // Safety valve (never-silence): taps muted an app but deliver
        // nothing — most likely TCC denied. Tear the graph down so the
        // app plays normally, and stop retrying until the user asks.
        if step.shouldTeardown {
            log.error("taps silent for 6 s; tearing down (audio-capture permission?)")
            teardownAll()
            permissionBlocked = true
            permissionSuspected = true
            engineState = .failed(reason: "No audio from taps — allow System Audio Recording, then retry")
        }
    }

    /// Pure heuristic state transition (tested without a 1 Hz timer).
    /// `inputPeak` is the pre-gain tap level; `anyTargetOpen` is false when
    /// every managed app is deliberately muted/at 0%.
    struct PermissionHeuristicStep: Equatable {
        var silentSince: Date?
        var permissionSuspected: Bool
        var shouldTeardown: Bool
    }

    static func permissionHeuristicStep(inputPeak: Float, anyTargetOpen: Bool,
                                        silentSince: Date?,
                                        now: Date) -> PermissionHeuristicStep {
        // Intentional silence (all apps muted): never a permission failure.
        guard anyTargetOpen else {
            return PermissionHeuristicStep(silentSince: nil,
                                           permissionSuspected: false,
                                           shouldTeardown: false)
        }
        guard inputPeak < 0.0005 else {
            return PermissionHeuristicStep(silentSince: nil,
                                           permissionSuspected: false,
                                           shouldTeardown: false)
        }
        let since = silentSince ?? now
        let silentFor = now.timeIntervalSince(since)
        return PermissionHeuristicStep(silentSince: since,
                                       permissionSuspected: silentFor >= 2.0,
                                       shouldTeardown: silentFor >= 6.0)
    }

    private func handle(_ intent: MixerIntent) {
        switch intent {
        case .setGain(let id, let gain):
            settings.setGain(id, gain)
        case .setMuted(let id, let muted):
            settings.setMuted(id, muted)
        case .setAllAppsGain(let gain):
            let apps = catalog.currentApps()
            settings.setAllAppsGain(apps.map(\.identity), gain)
        case .resetAll:
            settings.resetAll()
        case .retryPermission:
            permissionBlocked = false
            retryNotBefore = nil
        case .shutdown:
            teardownAll()
        }
    }

    private func execute(_ ops: [GraphOp], apps: [DiscoveredApp]) {
        let byIdentity = Dictionary(apps.map { ($0.identity, $0) },
                                     uniquingKeysWith: { first, _ in first })
        for op in ops {
            switch op {
            case .createTap(let id):
                guard let app = byIdentity[id], !app.processes.isEmpty else { break }
                do {
                    let handle = try audio.createTap(processes: app.processes.map(\.objectID))
                    taps[id] = handle
                    degraded.remove(id)
                } catch {
                    // Per-app isolation (error taxonomy row 2): this app's
                    // audio is untouched, other apps unaffected.
                    log.error("createTap failed for \(id.canonicalBundleID, privacy: .public): \(String(describing: error), privacy: .public)")
                    degraded.insert(id)
                }
            case .destroyTap(let id):
                if let handle = taps.removeValue(forKey: id) {
                    try? audio.destroyTap(handle)
                }
                degraded.remove(id)
            case .rebuildAggregate:
                rebuildAggregate()
            case .teardownAggregate:
                teardownAggregate()
            case .setTarget(let id, let milli):
                slotLock.lock()
                if let slot = identitySlots[id] {
                    cat_slot_set_target(slots + slot, milli)
                }
                slotLock.unlock()
            }
        }
    }

    /// Rebuild = stop render loop, destroy aggregate (taps stay alive),
    /// create a new aggregate on the current default output, install + start.
    /// The window between stop and start unmutes managed apps briefly
    /// (rebuild flash, budget <= 150 ms; ARCHITECTURE.md §8.4).
    private func rebuildAggregate() {
        engineState = .rebuilding
        stopAndDestroyAggregate()
        guard !taps.isEmpty else {
            clearSlots()
            engineState = .idle
            return
        }
        // Stable slot order == aggregate tap order (mapping assumption, S2 pins).
        let identities = taps.keys.sorted { $0.canonicalBundleID < $1.canonicalBundleID }
        assignSlots(identities)
        do {
            let output = try audio.defaultOutputDevice()
            outputName = output.name
            let handles = identities.compactMap { taps[$0] }
            let agg = try audio.createAggregate(outputUID: output.uid, taps: handles)
            try audio.installRenderLoop(on: agg, context: context)
            try audio.startRenderLoop(on: agg)
            let format = try audio.aggregateFormat(agg)
            context.pointee.frameRate = format.sampleRate
            context.pointee.outputChannels = format.channels
            aggregate = agg
            currentOutputID = output.id
            retryNotBefore = nil
            engineState = .active
            beginAppNapActivity()
        } catch {
            // Aggregate failure (taxonomy row 3): tear the graph down.
            // Audio plays normally — control lost, never audio.
            log.error("aggregate failed: \(String(describing: error), privacy: .public)")
            teardownAll()
            retryNotBefore = Date().addingTimeInterval(5)
            engineState = .failed(reason: String(describing: error))
        }
    }

    private func teardownAggregate() {
        stopAndDestroyAggregate()
        clearSlots()
        silentSince = nil
        permissionSuspected = false
        engineState = .idle
    }

    private func stopAndDestroyAggregate() {
        guard let agg = aggregate else { return }
        try? audio.stopRenderLoop(on: agg)
        try? audio.destroyAggregate(agg)
        aggregate = nil
        currentOutputID = nil
        endAppNapActivity()
    }

    private func teardownAll() {
        stopAndDestroyAggregate()
        for (_, handle) in taps { try? audio.destroyTap(handle) }
        taps = [:]
        degraded = []
        clearSlots()
        silentSince = nil
        permissionSuspected = false
        engineState = .idle
    }

    // MARK: - Slots

    private func assignSlots(_ identities: [AppIdentity]) {
        // Defensive bound: the reconciler already caps the tap set, but the
        // slot table must never be indexed past its allocation.
        let bounded = Array(identities.prefix(capacity))
        slotLock.lock()
        identitySlots = Dictionary(uniqueKeysWithValues: bounded.enumerated().map { ($1, $0) })
        slotLock.unlock()
        // The render loop is stopped here, so stale published levels cannot
        // race. Without this a new slot mapping could briefly inherit the
        // previous app's peak — and the permission heuristic could read a
        // stale non-zero input level as "the tap is alive".
        for i in 0..<capacity {
            cat_slot_publish_peak(slots + i, 0)
            cat_slot_publish_input_peak(slots + i, 0)
            (slots + i).pointee.peak = 0
            (slots + i).pointee.input_peak = 0
        }
        cat_flag_set(activeSlots, UInt32(bounded.count))
    }

    private func clearSlots() {
        slotLock.lock()
        identitySlots = [:]
        slotLock.unlock()
        cat_flag_set(activeSlots, 0)
    }

    // MARK: - Snapshot

    private func publishSnapshot(apps: [DiscoveredApp], desired: [AppIdentity: DesiredApp]) {
        // Audible apps first: they are what the user is usually looking for.
        let ordered = apps.sorted { lhs, rhs in
            if lhs.isAudible != rhs.isAudible { return lhs.isAudible }
            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.identity.canonicalBundleID < rhs.identity.canonicalBundleID
        }
        let rows = ordered.map { app -> AppRow in
            let state: AppRowState
            if degraded.contains(app.identity) {
                state = .degraded(reason: "tap unavailable")
            } else if taps[app.identity] != nil {
                state = .managed
            } else {
                state = .unmanaged
            }
            return AppRow(identity: app.identity, displayName: app.displayName,
                          isAudible: app.isAudible, rowState: state,
                          desired: desired[app.identity] ?? DesiredApp())
        }
        log.debug("snapshot rows=\(rows.count, privacy: .public) apps=\(apps.count, privacy: .public) output=\(self.outputName ?? "-", privacy: .public)")
        snapshotLock.lock()
        snapshotValue = MixerSnapshot(engine: engineState, rows: rows,
                                      outputDeviceName: outputName,
                                      usesFakeEngine: usesFakeEngine,
                                      permissionSuspected: permissionSuspected)
        snapshotLock.unlock()
    }

    // MARK: - App Nap (disable while mixing)

    private func beginAppNapActivity() {
        guard appNapActivity == nil else { return }
        appNapActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "MixBar real-time mixing")
    }

    private func endAppNapActivity() {
        if let activity = appNapActivity {
            ProcessInfo.processInfo.endActivity(activity)
            appNapActivity = nil
        }
    }
}

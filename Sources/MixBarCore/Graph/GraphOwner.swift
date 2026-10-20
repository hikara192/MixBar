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
        let apps = catalog.currentApps()
        let desired = settings.desiredState()
        let actual = ActualGraphState(taps: Set(taps.keys), hasAggregate: aggregate != nil)
        let ops = Reconciler.plan(desired: desired, audible: apps.map(\.identity),
                                  actual: actual, capacity: capacity)
        execute(ops, apps: apps)
        publishSnapshot(apps: apps, desired: desired)
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
        case .retryPermission:
            break   // skeleton: the 1 Hz poll re-attempts taps; onboarding UI is slice 3
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
            engineState = .active
            beginAppNapActivity()
        } catch {
            // Aggregate failure (taxonomy row 3): tear the graph down.
            // Audio plays normally — control lost, never audio.
            log.error("aggregate failed: \(String(describing: error), privacy: .public)")
            teardownAll()
            engineState = .failed(reason: String(describing: error))
        }
    }

    private func teardownAggregate() {
        stopAndDestroyAggregate()
        clearSlots()
        engineState = .idle
    }

    private func stopAndDestroyAggregate() {
        guard let agg = aggregate else { return }
        try? audio.stopRenderLoop(on: agg)
        try? audio.destroyAggregate(agg)
        aggregate = nil
        endAppNapActivity()
    }

    private func teardownAll() {
        stopAndDestroyAggregate()
        for (_, handle) in taps { try? audio.destroyTap(handle) }
        taps = [:]
        degraded = []
        clearSlots()
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
        let rows = apps.map { app -> AppRow in
            let state: AppRowState
            if degraded.contains(app.identity) {
                state = .degraded(reason: "tap unavailable")
            } else if taps[app.identity] != nil {
                state = .managed
            } else {
                state = .unmanaged
            }
            return AppRow(identity: app.identity, displayName: app.displayName,
                          isAudible: true, rowState: state,
                          desired: desired[app.identity] ?? DesiredApp())
        }
        snapshotLock.lock()
        snapshotValue = MixerSnapshot(engine: engineState, rows: rows,
                                      outputDeviceName: outputName,
                                      usesFakeEngine: usesFakeEngine)
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

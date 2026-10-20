import Foundation

/// Graph operations the reconciler emits. `rebuildAggregate`/`teardownAggregate`
/// act on the tap set that exists at execution time.
public enum GraphOp: Equatable, Sendable {
    case createTap(AppIdentity)
    case destroyTap(AppIdentity)
    case setTarget(AppIdentity, UInt16)   // milli gain, cheap idempotent atomic write
    case rebuildAggregate
    case teardownAggregate
}

/// Actual (observed) graph state. Structural state only; targets are
/// continuously derived data, not structure.
public struct ActualGraphState: Equatable, Sendable {
    public var taps: Set<AppIdentity>
    public var hasAggregate: Bool

    public init(taps: Set<AppIdentity> = [], hasAggregate: Bool = false) {
        self.taps = taps
        self.hasAggregate = hasAggregate
    }

    /// Pure simulation of applying ops (used by GraphOwner bookkeeping and tests).
    public static func applying(_ ops: [GraphOp], to state: ActualGraphState) -> ActualGraphState {
        var s = state
        for op in ops {
            switch op {
            case .createTap(let id): s.taps.insert(id)
            case .destroyTap(let id): s.taps.remove(id)
            case .rebuildAggregate: s.hasAggregate = !s.taps.isEmpty
            case .teardownAggregate: s.hasAggregate = false
            case .setTarget: break
            }
        }
        return s
    }
}

/// Desired-state reconciler (ADR-004). Pure function: desired state + audible
/// apps -> structural ops + target writes.
///
/// Idempotency: applying the plan and re-planning yields no further
/// structural ops (createTap/destroyTap/rebuildAggregate/teardownAggregate);
/// only cheap setTarget writes re-appear. Tested in ReconcilerTests.
public enum Reconciler {
    /// Deterministic: the tap set is chosen in canonical bundle-ID order, so
    /// the same inputs always produce the same plan (and slot order matches
    /// the aggregate tap order).
    ///
    /// Capacity-bounded: at most `capacity` taps exist. Apps beyond capacity
    /// stay untouched — they play at 100% (never-silence invariant) and are
    /// retried on later reconciles if slots free up.
    public static func plan(desired: [AppIdentity: DesiredApp],
                            audible: [AppIdentity],
                            actual: ActualGraphState,
                            capacity: Int = 16) -> [GraphOp] {
        let audibleSet = Set(audible)

        func needsTap(_ id: AppIdentity) -> Bool {
            guard audibleSet.contains(id) else { return false }
            return !(desired[id]?.isUnity ?? true)
        }

        // Keep existing taps (avoids churn), fill remaining slots in order.
        var finalTaps = actual.taps.filter(needsTap)
        let candidates = audibleSet
            .filter { needsTap($0) && !actual.taps.contains($0) }
            .sorted { $0.canonicalBundleID < $1.canonicalBundleID }
        for id in candidates where finalTaps.count < capacity {
            finalTaps.insert(id)
        }
        let finalIDs = finalTaps.sorted { $0.canonicalBundleID < $1.canonicalBundleID }

        var ops: [GraphOp] = []
        // Taps that must go: app gone, back to unity (ADR-002), or over capacity.
        for id in actual.taps.sorted(by: { $0.canonicalBundleID < $1.canonicalBundleID })
            where !finalTaps.contains(id) {
            ops.append(.destroyTap(id))
        }
        // Taps that must exist.
        for id in finalIDs where !actual.taps.contains(id) {
            ops.append(.createTap(id))
        }

        if !ops.isEmpty {
            ops.append(finalIDs.isEmpty ? .teardownAggregate : .rebuildAggregate)
        }
        // Target writes for every tapped app (atomic, idempotent).
        for id in finalIDs {
            ops.append(.setTarget(id, desired[id]?.milliGain ?? 1000))
        }
        return ops
    }
}

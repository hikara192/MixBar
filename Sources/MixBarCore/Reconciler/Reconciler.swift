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
    public static func plan(desired: [AppIdentity: DesiredApp],
                            audible: [AppIdentity],
                            actual: ActualGraphState) -> [GraphOp] {
        let audibleSet = Set(audible)
        var ops: [GraphOp] = []

        func needsTap(_ id: AppIdentity) -> Bool {
            guard audibleSet.contains(id) else { return false }
            return !(desired[id]?.isUnity ?? true)
        }

        // Taps that must go: app gone, or back to unity (ADR-002).
        for id in actual.taps where !needsTap(id) {
            ops.append(.destroyTap(id))
        }
        // Taps that must exist.
        for id in audibleSet where needsTap(id) && !actual.taps.contains(id) {
            ops.append(.createTap(id))
        }

        let final = ActualGraphState.applying(ops, to: actual)
        if !ops.isEmpty {
            ops.append(final.taps.isEmpty ? .teardownAggregate : .rebuildAggregate)
        }
        // Target writes for every tapped app (atomic, idempotent).
        for id in final.taps {
            ops.append(.setTarget(id, desired[id]?.milliGain ?? 1000))
        }
        return ops
    }
}

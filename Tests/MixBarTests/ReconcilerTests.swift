import XCTest
@testable import MixBarCore

/// Control plane tests: the reconciler is pure and idempotent (ADR-004).
final class ReconcilerTests: XCTestCase {

    private let spotify = AppIdentity(canonicalBundleID: "com.spotify.client")
    private let chrome = AppIdentity(canonicalBundleID: "com.google.Chrome")
    private let zoom = AppIdentity(canonicalBundleID: "us.zoom.xos")

    private func structural(_ ops: [GraphOp]) -> [GraphOp] {
        ops.filter {
            if case .setTarget = $0 { return false }
            return true
        }
    }

    func test_firstAdjustmentCreatesTapAndRebuildsAggregate() {
        let desired = [spotify: DesiredApp(gain: 0.3)]
        let ops = Reconciler.plan(desired: desired,
                                  audible: [spotify, chrome],
                                  actual: ActualGraphState())

        XCTAssertTrue(ops.contains(.createTap(spotify)))
        XCTAssertFalse(ops.contains(.createTap(chrome)))   // unity -> never tapped (ADR-002)
        XCTAssertTrue(ops.contains(.rebuildAggregate))
        XCTAssertTrue(ops.contains(.setTarget(spotify, 300)))
    }

    func test_idempotency_secondPlanEmitsNoStructuralOps() {
        let desired = [spotify: DesiredApp(gain: 0.3)]
        let first = Reconciler.plan(desired: desired,
                                     audible: [spotify, chrome],
                                     actual: ActualGraphState())
        let actual2 = ActualGraphState.applying(first, to: ActualGraphState())
        let second = Reconciler.plan(desired: desired,
                                     audible: [spotify, chrome],
                                     actual: actual2)
        XCTAssertTrue(structural(second).isEmpty, "second plan must be structural no-op, got: \(second)")
    }

    func test_returnToUnityTearsDownGraph() {
        let desired: [AppIdentity: DesiredApp] = [:]   // spotify back to unity
        let actual = ActualGraphState(taps: [spotify], hasAggregate: true)
        let ops = Reconciler.plan(desired: desired, audible: [spotify], actual: actual)

        XCTAssertEqual(structural(ops), [.destroyTap(spotify), .teardownAggregate])
    }

    func test_goneAppLosesTapOthersKeepMixing() {
        let desired = [chrome: DesiredApp(gain: 0.4)]
        let actual = ActualGraphState(taps: [spotify, chrome], hasAggregate: true)
        // spotify stopped playing (not audible anymore), chrome stays at 40%.
        let ops = Reconciler.plan(desired: desired, audible: [chrome], actual: actual)

        XCTAssertEqual(structural(ops), [.destroyTap(spotify), .rebuildAggregate])
        XCTAssertTrue(ops.contains(.setTarget(chrome, 400)))
    }

    func test_mutedAppKeepsTapWithZeroTarget() {
        let desired = [zoom: DesiredApp(gain: 1.0, muted: true)]
        let ops = Reconciler.plan(desired: desired, audible: [zoom], actual: ActualGraphState())

        XCTAssertTrue(ops.contains(.createTap(zoom)))          // muted != unity
        XCTAssertTrue(ops.contains(.setTarget(zoom, 0)))
    }

    func test_allUnityLeavesGraphEmpty() {
        let ops = Reconciler.plan(desired: [:], audible: [spotify, chrome], actual: ActualGraphState())
        XCTAssertTrue(ops.isEmpty)
    }
}

import XCTest
@testable import MixBarCore

/// Regression tests for the ADR-005 permission heuristic. The reported bug:
/// muting an app silenced the mixer output, which looked exactly like a dead
/// tap — the panel showed "No audio detected" and then paused MixBar.
final class PermissionHeuristicTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func test_mutedSlotSilenceIsNeverTreatedAsPermissionFailure() {
        // User muted everything: output is silent, input peak is zero because
        // no app is playing — still not a capture failure.
        let step = GraphOwner.permissionHeuristicStep(
            inputPeak: 0,
            anyTargetOpen: false,
            silentSince: t0,
            now: t0.addingTimeInterval(60))

        XCTAssertNil(step.silentSince)
        XCTAssertFalse(step.permissionSuspected)
        XCTAssertFalse(step.shouldTeardown)
    }

    func test_liveInputPreventsFalsePositiveEvenAtZeroOutput() {
        // Slot target is 0 (muted) but the tap still delivers audio before the
        // gain stage: this is exactly the reported case.
        let step = GraphOwner.permissionHeuristicStep(
            inputPeak: 0.4,
            anyTargetOpen: true,
            silentSince: t0,
            now: t0.addingTimeInterval(60))

        XCTAssertNil(step.silentSince)
        XCTAssertFalse(step.permissionSuspected)
        XCTAssertFalse(step.shouldTeardown)
    }

    func test_silenceStartsHintAfterTwoSeconds() {
        let first = GraphOwner.permissionHeuristicStep(
            inputPeak: 0, anyTargetOpen: true, silentSince: nil, now: t0)
        XCTAssertEqual(first.silentSince, t0)
        XCTAssertFalse(first.permissionSuspected)
        XCTAssertFalse(first.shouldTeardown)

        let hint = GraphOwner.permissionHeuristicStep(
            inputPeak: 0, anyTargetOpen: true,
            silentSince: first.silentSince, now: t0.addingTimeInterval(2.5))
        XCTAssertTrue(hint.permissionSuspected)
        XCTAssertFalse(hint.shouldTeardown)
    }

    func test_sustainedSilenceTriggersSafetyValveAfterSixSeconds() {
        let step = GraphOwner.permissionHeuristicStep(
            inputPeak: 0, anyTargetOpen: true,
            silentSince: t0, now: t0.addingTimeInterval(6.1))
        XCTAssertTrue(step.permissionSuspected)
        XCTAssertTrue(step.shouldTeardown)
    }

    func test_signalResetsTheSilenceWindow() {
        let step = GraphOwner.permissionHeuristicStep(
            inputPeak: 0.2, anyTargetOpen: true,
            silentSince: t0, now: t0.addingTimeInterval(5))
        XCTAssertNil(step.silentSince)
        XCTAssertFalse(step.permissionSuspected)
        XCTAssertFalse(step.shouldTeardown)
    }
}

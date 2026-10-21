import XCTest
@testable import MixBarCore

/// End-to-end skeleton test: the REAL GraphOwner + Reconciler + RenderCore
/// driven by FakeAudioSystem — no Core Audio, but the whole control/data
/// plane including peaks publishing is exercised for real (ARCHITECTURE.md §12).
final class GraphOwnerEndToEndTests: XCTestCase {

    private let spotify = AppIdentity(canonicalBundleID: "com.spotify.client")

    func test_fakeEngineEndToEnd_gainOnMetersOnTeardown() async throws {
        let suite = "mixbar-e2e-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(defaults: defaults)
        settings.setGain(spotify, 0.5)   // pre-persisted: applies on first reconcile

        let graph = GraphOwner(audioSystem: FakeAudioSystem(),
                               catalog: FakeProcessCatalog(),
                               settings: settings,
                               fakeEngine: true)
        defer { graph.shutdown() }

        // 1. First reconcile creates the tap, builds the aggregate, goes active.
        let becameActive = try await pollUntil(timeout: 3.0) {
            let s = graph.snapshot()
            return s.engine == .active
                && s.rows.contains { $0.identity == self.spotify && $0.rowState == .managed }
        }
        XCTAssertTrue(becameActive, "engine should reach .active with spotify managed")

        // 2. The fake render thread drives the REAL RenderCore -> peaks flow.
        let metered = try await pollUntil(timeout: 3.0) {
            graph.meter(for: self.spotify) > 0.01
        }
        XCTAssertTrue(metered, "peaks should publish through the slot table")

        // 3. Other audible apps stay unmanaged (bit-perfect, zero overhead).
        let chrome = AppIdentity(canonicalBundleID: "com.google.Chrome")
        XCTAssertTrue(graph.snapshot().rows.contains {
            $0.identity == chrome && $0.rowState == .unmanaged
        })

        // 4. Back to unity -> tap destroyed, aggregate torn down, engine idle.
        graph.submit(.setGain(spotify, 1.0))
        let wentIdle = try await pollUntil(timeout: 3.0) {
            graph.snapshot().engine == .idle
                && graph.snapshot().rows.contains { $0.identity == self.spotify && $0.rowState == .unmanaged }
        }
        XCTAssertTrue(wentIdle, "returning to unity should tear the graph down")
    }

    func test_muteKeepsTapWithZeroGain() async throws {
        let suite = "mixbar-e2e-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let graph = GraphOwner(audioSystem: FakeAudioSystem(),
                               catalog: FakeProcessCatalog(),
                               settings: SettingsStore(defaults: defaults),
                               fakeEngine: true)
        defer { graph.shutdown() }

        graph.submit(.setMuted(spotify, true))
        let muted = try await pollUntil(timeout: 3.0) {
            let s = graph.snapshot()
            return s.engine == .active
                && s.rows.contains { $0.identity == self.spotify && $0.rowState == .managed }
        }
        XCTAssertTrue(muted)

        // Muted target = 0: the meter decays to zero while the tap stays.
        let silenced = try await pollUntil(timeout: 3.0) {
            graph.meter(for: self.spotify) < 0.01
        }
        XCTAssertTrue(silenced, "muted app's meter should fall to zero")
        XCTAssertEqual(graph.snapshot().engine, .active)
    }

    func test_outputDeviceIsVisibleWhileIdle() async throws {
        let suite = "mixbar-e2e-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let graph = GraphOwner(audioSystem: FakeAudioSystem(),
                               catalog: FakeProcessCatalog(),
                               settings: SettingsStore(defaults: defaults),
                               fakeEngine: true)
        defer { graph.shutdown() }

        // Regression: the name used to be learned only while building the
        // aggregate, so an idle graph displayed "No output device".
        let visible = try await pollUntil(timeout: 2.0) {
            let snapshot = graph.snapshot()
            return snapshot.engine == .idle
                && snapshot.outputDeviceName == "Fake Output"
        }
        XCTAssertTrue(visible, "idle graph should still report the output device")
    }

    func test_silentAppsStayListedWithoutTap() async throws {
        let suite = "mixbar-e2e-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let graph = GraphOwner(audioSystem: FakeAudioSystem(),
                               catalog: FakeProcessCatalog(),
                               settings: SettingsStore(defaults: defaults),
                               fakeEngine: true)
        defer { graph.shutdown() }

        let music = AppIdentity(canonicalBundleID: "com.apple.Music")

        // Paused player is listed, marked silent, and has no tap.
        let listed = try await pollUntil(timeout: 3.0) {
            graph.snapshot().rows.contains {
                $0.identity == music && !$0.isAudible && $0.rowState == .unmanaged
            }
        }
        XCTAssertTrue(listed, "silent apps should stay in the panel")

        // Setting a volume for a silent app persists the intent but does not
        // create a tap or an aggregate until it actually plays.
        graph.submit(.setGain(music, 0.3))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(graph.snapshot().engine, .idle)
        XCTAssertTrue(graph.snapshot().rows.contains {
            $0.identity == music && $0.rowState == .unmanaged && abs($0.desired.gain - 0.3) < 0.001
        })
    }

    private func pollUntil(timeout: TimeInterval, _ condition: @escaping () -> Bool) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }
}

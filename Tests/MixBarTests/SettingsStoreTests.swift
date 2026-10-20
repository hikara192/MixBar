import XCTest
@testable import MixBarCore

final class SettingsStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private let spotify = AppIdentity(canonicalBundleID: "com.spotify.client")
    private let chrome = AppIdentity(canonicalBundleID: "com.google.Chrome")

    override func setUp() {
        super.setUp()
        suiteName = "mixbar-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_roundTripThroughUserDefaults() {
        let store = SettingsStore(defaults: defaults)
        store.setGain(spotify, 0.3)
        store.setMuted(chrome, true)
        store.flushNow()

        let reloaded = SettingsStore(defaults: defaults)
        let desired = reloaded.desiredState()
        XCTAssertEqual(desired[spotify], DesiredApp(gain: 0.3, muted: false))
        XCTAssertEqual(desired[chrome]?.muted, true)
    }

    func test_unknownIdentityDefaultsToUnity() {
        let store = SettingsStore(defaults: defaults)
        XCTAssertNil(store.setting(for: spotify))
        XCTAssertEqual(store.desiredState()[spotify] ?? DesiredApp(), DesiredApp())
    }

    func test_gainClampedToUnitRange() {
        let store = SettingsStore(defaults: defaults)
        store.setGain(spotify, 5.0)
        XCTAssertEqual(store.setting(for: spotify)?.gain, 1.0)
        store.setGain(spotify, -1.0)
        XCTAssertEqual(store.setting(for: spotify)?.gain, 0.0)
    }

    func test_flushNowPersistsImmediately() {
        let store = SettingsStore(defaults: defaults)
        store.setGain(spotify, 0.25)
        store.flushNow()
        XCTAssertNotNil(defaults.data(forKey: "mixbar.settings.v1"))
    }
}

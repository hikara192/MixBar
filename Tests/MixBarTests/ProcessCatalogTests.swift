import XCTest
@testable import MixBarCore

/// Identity filters for the panel: MixBar must never list itself, helper
/// processes must group under their owning app, and system agents must not
/// masquerade as user apps.
final class ProcessCatalogTests: XCTestCase {

    func test_mixBarExcludesItself() {
        XCTAssertTrue(ProcessCatalog.isOwnBundle("com.mixbar.app"))
        XCTAssertFalse(ProcessCatalog.isOwnBundle("com.spotify.client"))
        XCTAssertFalse(ProcessCatalog.isOwnBundle("ru.keepcoder.Telegram"))
    }

    func test_owningAppBundleIsOutermostApp() {
        XCTAssertEqual(
            ProcessCatalog.owningAppBundlePath(
                executablePath: "/Applications/Foo.app/Contents/MacOS/Foo"),
            "/Applications/Foo.app")

        // Nested helper apps group under the real app, not the helper bundle.
        XCTAssertEqual(
            ProcessCatalog.owningAppBundlePath(
                executablePath: "/Applications/Яндекс Музыка.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            "/Applications/Яндекс Музыка.app")

        // XPC services and daemons are not apps.
        XCTAssertNil(ProcessCatalog.owningAppBundlePath(
            executablePath: "/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.GPU.xpc/Contents/MacOS/com.apple.WebKit.GPU"))
        XCTAssertNil(ProcessCatalog.owningAppBundlePath(
            executablePath: "/usr/sbin/systemsoundserverd"))
    }

    func test_systemAgentsAreHiddenButSystemUserAppsAreKept() {
        let agent = ProcessCatalog.AppInfo(
            bundleID: "com.apple.controlcenter", name: "Control Center",
            isUserFacing: false)
        XCTAssertFalse(ProcessCatalog.shouldList(
            appPath: "/System/Library/CoreServices/ControlCenter.app", info: agent))

        let music = ProcessCatalog.AppInfo(
            bundleID: "com.apple.Music", name: "Music", isUserFacing: true)
        XCTAssertTrue(ProcessCatalog.shouldList(
            appPath: "/System/Applications/Music.app", info: music))

        // Stock apps like Safari actually run from the cryptex mount.
        let safari = ProcessCatalog.AppInfo(
            bundleID: "com.apple.Safari", name: "Safari", isUserFacing: true)
        XCTAssertTrue(ProcessCatalog.shouldList(
            appPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app",
            info: safari))

        let yandex = ProcessCatalog.AppInfo(
            bundleID: "ru.yandex.desktop.music", name: "Яндекс Музыка",
            isUserFacing: false)
        XCTAssertTrue(ProcessCatalog.shouldList(
            appPath: "/Applications/Яндекс Музыка.app", info: yandex))
    }

    func test_readsRealBundleInfoWithoutLaunchServices() throws {
        // The test bundle lives inside Xcode's app; this exercises the plist
        // parser on a real Info.plist rather than a synthetic dictionary.
        let path = try XCTUnwrap(
            ProcessCatalog.owningAppBundlePath(
                executablePath: ProcessCatalog.executablePath(getpid()) ?? ""))
        let info = try XCTUnwrap(ProcessCatalog.readAppInfo(at: path))
        XCTAssertFalse(info.bundleID.isEmpty)
        XCTAssertFalse(info.name.isEmpty)
    }
}

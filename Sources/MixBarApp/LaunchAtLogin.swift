import AppKit
import Foundation
import Observation
import ServiceManagement

/// Login-item control for a menu bar app (macOS 13+ `SMAppService`).
///
/// Registration is only meaningful for a stable installed location: a bundle
/// launched from a build directory would register that throw-away path, so the
/// toggle stays disabled outside /Applications.
@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var status: SMAppService.Status
    private(set) var lastError: String?

    init() {
        status = SMAppService.mainApp.status
    }

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }
    var isSupportedLocation: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// Login Items lives in System Settings → General; the pane identifier is
    /// stable on Ventura and later.
    func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preferences.users",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

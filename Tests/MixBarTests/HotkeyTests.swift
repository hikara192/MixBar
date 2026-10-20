import XCTest
import Carbon.HIToolbox
@testable import MixBarApp

@MainActor
final class HotkeyTests: XCTestCase {

    // MARK: Defaults

    func test_defaultBindings() {
        let configuration = HotkeyConfiguration.defaults

        let toggle = configuration[.toggleMuteAll]
        XCTAssertEqual(toggle.hotkey?.displayString, "⌥⌘M")
        XCTAssertEqual(toggle.hotkey?.keyCode, UInt32(kVK_ANSI_M))
        XCTAssertTrue(toggle.isEnabled)

        let reset = configuration[.resetAll]
        XCTAssertEqual(reset.hotkey?.displayString, "⌥⌘R")
        XCTAssertEqual(reset.hotkey?.keyCode, UInt32(kVK_ANSI_R))
        XCTAssertTrue(reset.isEnabled)
    }

    func test_actionIdentifiersAreStable() {
        XCTAssertEqual(HotkeyAction.toggleMuteAll.carbonID, 1)
        XCTAssertEqual(HotkeyAction.resetAll.carbonID, 2)
        XCTAssertEqual(HotkeyAction.toggleMuteAll.rawValue, "toggleMuteAll")
        XCTAssertEqual(HotkeyAction.resetAll.rawValue, "resetAll")
    }

    // MARK: Formatting

    func test_displayStringUsesConventionalModifierOrder() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_R),
                            modifiers: [.command, .shift, .control, .option])
        XCTAssertEqual(hotkey.displayString, "⌃⌥⇧⌘R")
    }

    func test_displayStringWithoutModifiers() {
        let hotkey = Hotkey(keyCode: UInt32(kVK_ANSI_1), modifiers: [])
        XCTAssertEqual(hotkey.displayString, "1")
    }

    func test_carbonModifiersMatchCarbonConstants() {
        let modifiers: HotkeyModifiers = [.command, .option, .control, .shift]
        XCTAssertEqual(modifiers.carbonFlags,
                       UInt32(cmdKey | optionKey | controlKey | shiftKey))
    }

    // MARK: Codable

    func test_configurationCodableRoundTrip() throws {
        var configuration = HotkeyConfiguration.defaults
        configuration[.resetAll] = HotkeyBinding(
            hotkey: Hotkey(keyCode: UInt32(kVK_F5),
                           modifiers: [.control, .shift]),
            isEnabled: false
        )

        let data = try configuration.encoded()
        let decoded = try XCTUnwrap(HotkeyConfiguration.decoded(from: data))

        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded[.resetAll].hotkey?.displayString, "⌃⇧F5")
        XCTAssertFalse(decoded[.resetAll].isEnabled)
        XCTAssertEqual(decoded[.toggleMuteAll], configuration[.toggleMuteAll])
    }

    func test_storePersistsAcrossInstances() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        XCTAssertEqual(store.binding(for: .toggleMuteAll).hotkey?.displayString, "⌥⌘M")

        store.assign(Hotkey(keyCode: UInt32(kVK_ANSI_K),
                            modifiers: [.control, .option]),
                     to: .toggleMuteAll)
        XCTAssertTrue(defaults.data(forKey: HotkeyStore.defaultsKey) != nil)

        let reloaded = HotkeyStore(defaults: defaults)
        XCTAssertEqual(reloaded.binding(for: .toggleMuteAll).hotkey?.displayString,
                       "⌃⌥K")
        XCTAssertEqual(reloaded.binding(for: .resetAll).hotkey?.displayString, "⌥⌘R")
    }

    func test_corruptDataFallsBackToDefaults() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set(Data("not json".utf8), forKey: HotkeyStore.defaultsKey)

        let store = HotkeyStore(defaults: defaults)
        XCTAssertEqual(store.binding(for: .toggleMuteAll).hotkey?.displayString, "⌥⌘M")
        XCTAssertEqual(store.binding(for: .resetAll).hotkey?.displayString, "⌥⌘R")
    }

    // MARK: Clearing

    func test_clearRemovesHotkeyAndPersists() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        store.clear(.toggleMuteAll)

        XCTAssertNil(store.binding(for: .toggleMuteAll).hotkey)
        XCTAssertEqual(store.status(for: .toggleMuteAll), .notSet)

        let reloaded = HotkeyStore(defaults: defaults)
        XCTAssertNil(reloaded.binding(for: .toggleMuteAll).hotkey)
        XCTAssertEqual(reloaded.binding(for: .resetAll).hotkey?.displayString, "⌥⌘R")
    }

    func test_assignNilClears() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        XCTAssertEqual(store.assign(nil, to: .resetAll), .applied)
        XCTAssertNil(store.binding(for: .resetAll).hotkey)
    }

    // MARK: Validation

    func test_duplicateIsRejected() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        let result = store.assign(Hotkey(keyCode: UInt32(kVK_ANSI_M),
                                         modifiers: [.option, .command]),
                                  to: .resetAll)

        XCTAssertEqual(result, .conflict(.toggleMuteAll))
        XCTAssertEqual(store.warning, .conflict(.toggleMuteAll))
        // The rejected shortcut must not be applied.
        XCTAssertEqual(store.binding(for: .resetAll).hotkey?.displayString, "⌥⌘R")
    }

    func test_duplicateOfDisabledBindingIsStillRejected() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        store.setEnabled(false, for: .toggleMuteAll)

        let result = store.assign(Hotkey(keyCode: UInt32(kVK_ANSI_M),
                                         modifiers: [.option, .command]),
                                  to: .resetAll)
        XCTAssertEqual(result, .conflict(.toggleMuteAll))
    }

    func test_shortcutWithoutRequiredModifierIsRejected() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        let shiftOnly = Hotkey(keyCode: UInt32(kVK_ANSI_K), modifiers: [.shift])

        XCTAssertEqual(store.assign(shiftOnly, to: .toggleMuteAll), .needsModifier)
        XCTAssertEqual(store.warning, .needsModifier)
        XCTAssertEqual(store.binding(for: .toggleMuteAll).hotkey?.displayString, "⌥⌘M")
    }

    func test_shiftAloneIsNotEnoughButShiftPlusCommandIs() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        let valid = Hotkey(keyCode: UInt32(kVK_ANSI_J),
                           modifiers: [.shift, .command])
        XCTAssertEqual(store.assign(valid, to: .toggleMuteAll), .applied)
        XCTAssertNil(store.warning)
    }

    // MARK: Enable / reset

    func test_disablePersistsAndReportsDisabledStatus() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        store.setEnabled(false, for: .resetAll)

        XCTAssertEqual(store.status(for: .resetAll), .disabled)
        XCTAssertEqual(store.binding(for: .resetAll).hotkey?.displayString, "⌥⌘R")

        let reloaded = HotkeyStore(defaults: defaults)
        XCTAssertFalse(reloaded.binding(for: .resetAll).isEnabled)
    }

    func test_resetToDefaultsRestoresBothActions() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        store.clear(.toggleMuteAll)
        store.setEnabled(false, for: .resetAll)

        store.resetToDefaults()
        XCTAssertEqual(store.configuration, .defaults)
        XCTAssertEqual(store.binding(for: .toggleMuteAll).hotkey?.displayString, "⌥⌘M")
        XCTAssertTrue(store.binding(for: .resetAll).isEnabled)
    }

    // MARK: Recording suspension

    func test_recordingSuspendsRegistrationAndEndRestoresIt() throws {
        let suite = "mixbar-hotkey-tests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HotkeyStore(defaults: defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        store.beginRecording(.toggleMuteAll)
        XCTAssertEqual(store.recordingAction, .toggleMuteAll)
        XCTAssertNil(store.warning)

        store.endRecording()
        XCTAssertNil(store.recordingAction)
        XCTAssertEqual(changes, 2)
    }
}

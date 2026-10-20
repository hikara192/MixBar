import Foundation
import Observation

/// Result of trying to assign a shortcut. The UI turns the non-applied cases
/// into localized warnings and keeps the recorder open for another try.
enum HotkeyAssignmentResult: Equatable, Sendable {
    case applied
    case needsModifier
    case conflict(HotkeyAction)
}

enum HotkeyValidationError: Equatable, Sendable {
    case needsModifier
    case conflict(HotkeyAction)
}

enum HotkeyRegistrationStatus: Equatable, Sendable {
    case active
    case disabled
    case notSet
    case unavailable
}

/// Observable, persisted shortcut configuration (UserDefaults + JSON).
///
/// The store owns validation and persistence; `HotkeyManager` owns Carbon.
/// Mutations call `onChange`, which the manager installs at launch, so every
/// edit is re-registered immediately without touching the UI code.
@MainActor
@Observable
final class HotkeyStore {
    static let defaultsKey = "mixbar.hotkeys.v1"

    private(set) var configuration: HotkeyConfiguration
    private(set) var statuses: [HotkeyAction: HotkeyRegistrationStatus] = [:]
    private(set) var warning: HotkeyValidationError?

    /// Non-nil while the settings recorder is waiting for a key. The manager
    /// suspends Carbon registration meanwhile so the shortcut being edited
    /// cannot fire its action.
    private(set) var recordingAction: HotkeyAction?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let stored = HotkeyConfiguration.decoded(from: data) {
            self.configuration = stored
        } else {
            self.configuration = .defaults
        }
    }

    // MARK: Reads

    func binding(for action: HotkeyAction) -> HotkeyBinding {
        configuration[action]
    }

    func status(for action: HotkeyAction) -> HotkeyRegistrationStatus {
        if let status = statuses[action] { return status }
        let binding = configuration[action]
        if binding.hotkey == nil { return .notSet }
        return binding.isEnabled ? .active : .disabled
    }

    // MARK: Mutations

    @discardableResult
    func assign(_ hotkey: Hotkey?, to action: HotkeyAction) -> HotkeyAssignmentResult {
        guard let hotkey else {
            clear(action)
            return .applied
        }
        guard !hotkey.modifiers.intersection(.required).isEmpty else {
            warning = .needsModifier
            return .needsModifier
        }

        var next = configuration
        next[action] = HotkeyBinding(hotkey: hotkey,
                                     isEnabled: next[action].isEnabled)
        if let owner = next.duplicateOwner(of: action) {
            warning = .conflict(owner)
            return .conflict(owner)
        }

        configuration = next
        warning = nil
        persist()
        notifyChange()
        return .applied
    }

    func clear(_ action: HotkeyAction) {
        var next = configuration
        next[action] = HotkeyBinding(hotkey: nil,
                                     isEnabled: next[action].isEnabled)
        configuration = next
        warning = nil
        persist()
        notifyChange()
    }

    func setEnabled(_ enabled: Bool, for action: HotkeyAction) {
        var next = configuration
        next[action].isEnabled = enabled
        configuration = next
        warning = nil
        persist()
        notifyChange()
    }

    func resetToDefaults() {
        configuration = .defaults
        warning = nil
        persist()
        notifyChange()
    }

    // MARK: Recording

    func beginRecording(_ action: HotkeyAction) {
        guard recordingAction != action else { return }
        recordingAction = action
        warning = nil
        notifyChange()
    }

    func endRecording() {
        guard recordingAction != nil else { return }
        recordingAction = nil
        notifyChange()
    }

    /// Called by the manager after Carbon registration; not a user edit, so it
    /// must not trigger another re-registration.
    func apply(statuses: [HotkeyAction: HotkeyRegistrationStatus]) {
        self.statuses = statuses
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? configuration.encoded() else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private func notifyChange() {
        onChange?()
    }
}

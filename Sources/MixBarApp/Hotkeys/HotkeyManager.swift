import AppKit
import Carbon.HIToolbox
import Foundation

/// Owns the Carbon registration for every enabled shortcut.
///
/// Carbon's `RegisterEventHotKey` works for a menu-bar (`LSUIElement`) app
/// without Accessibility or Input Monitoring permission: the system routes the
/// key press to us through the application event target. The C callback cannot
/// capture context, so the manager pointer travels in `userData`.
@MainActor
final class HotkeyManager {
    /// Four-character code "MXBR" used as `EventHotKeyID.signature`.
    static let signature: OSType = 0x4D58_4252

    private let store: HotkeyStore
    private let mixer: MixerStore

    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private(set) var isStarted = false

    init(store: HotkeyStore, mixer: MixerStore) {
        self.store = store
        self.mixer = mixer
    }

    isolated deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
    }

    /// Installs the Carbon handler once, then registers the current bindings.
    /// Safe to call more than once; only the first call has an effect.
    func start() {
        guard !isStarted else { return }
        isStarted = true

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(),
                                         mixbarHotkeyHandler,
                                         1,
                                         &eventType,
                                         userData,
                                         &eventHandler)
        if status != noErr {
            NSLog("MixBar hotkeys: InstallEventHandler failed (OSStatus %d)", status)
            eventHandler = nil
        }

        store.onChange = { [weak self] in
            self?.synchronize()
        }

        synchronize()
    }

    func stop() {
        store.onChange = nil
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isStarted = false
    }

    // MARK: Registration

    /// Re-registers every binding from scratch. Called at launch and after each
    /// edit in Settings, so changes apply without relaunching.
    private func synchronize() {
        unregisterAll()

        // The recorder is waiting for a key: keep the old statuses, but do not
        // let a stale shortcut fire while the user is typing a new one.
        guard store.recordingAction == nil else { return }

        var statuses: [HotkeyAction: HotkeyRegistrationStatus] = [:]
        for action in HotkeyAction.allCases {
            let binding = store.binding(for: action)
            guard let hotkey = binding.hotkey else {
                statuses[action] = .notSet
                continue
            }
            guard binding.isEnabled else {
                statuses[action] = .disabled
                continue
            }

            let status = register(hotkey, for: action)
            if status == noErr {
                statuses[action] = .active
                NSLog("MixBar hotkeys: %@ registered as %@ (%u)",
                      action.rawValue, hotkey.displayString, action.carbonID)
            } else if status == OSStatus(eventHotKeyExistsErr) {
                statuses[action] = .unavailable
                NSLog("MixBar hotkeys: %@ is already taken (%@)",
                      action.rawValue, hotkey.displayString)
            } else {
                statuses[action] = .unavailable
                NSLog("MixBar hotkeys: RegisterEventHotKey failed for %@ (OSStatus %d)",
                      action.rawValue, status)
            }
        }
        store.apply(statuses: statuses)
    }

    private func register(_ hotkey: Hotkey, for action: HotkeyAction) -> OSStatus {
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: Self.signature, id: action.carbonID)
        let status = RegisterEventHotKey(hotkey.keyCode,
                                         hotkey.carbonModifiers,
                                         identifier,
                                         GetApplicationEventTarget(),
                                         0,
                                         &reference)
        if status == noErr, let reference {
            registrations[action] = reference
        }
        return status
    }

    private func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
    }

    // MARK: Dispatch

    fileprivate func perform(carbonID: UInt32) {
        guard let action = HotkeyAction.allCases.first(where: { $0.carbonID == carbonID }) else {
            return
        }
        switch action {
        case .toggleMuteAll:
            mixer.toggleMuteAll()
        case .resetAll:
            mixer.resetAllVolumes()
        }
    }
}

/// Carbon callback. The application event target delivers hotkey events on the
/// main thread, so `assumeIsolated` is valid and avoids an async hop.
private func mixbarHotkeyHandler(_ callRef: EventHandlerCallRef?,
                                 _ event: EventRef?,
                                 _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &identifier)
    guard status == noErr else { return status }

    // The pointer crosses into the main-actor closure, so carry it in a
    // Sendable box; the manager itself stays main-actor isolated.
    let pointer = HotkeyManagerPointer(raw: userData)
    MainActor.assumeIsolated {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(pointer.raw).takeUnretainedValue()
        manager.perform(carbonID: identifier.id)
    }
    return noErr
}

private struct HotkeyManagerPointer: @unchecked Sendable {
    let raw: UnsafeMutableRawPointer
}

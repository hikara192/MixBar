import AppKit
import Carbon.HIToolbox
import Foundation
import MixBarLocalization

// MARK: - Modifiers

/// The four modifiers a global shortcut can use. Stored as a raw mask so the
/// value survives JSON round-trips and maps 1:1 to Carbon's modifier flags.
struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: UInt32

    init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    static let command = HotkeyModifiers(rawValue: 1 << 0)
    static let option = HotkeyModifiers(rawValue: 1 << 1)
    static let control = HotkeyModifiers(rawValue: 1 << 2)
    static let shift = HotkeyModifiers(rawValue: 1 << 3)

    /// At least one of ⌘, ⌥ or ⌃ is required; Shift alone is not a shortcut.
    static let required: HotkeyModifiers = [.command, .option, .control]

    /// Carbon expects its own constants (`cmdKey`, `optionKey`, …), not the
    /// `1 << n` mask above.
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.command) { flags |= UInt32(cmdKey) }
        if contains(.option) { flags |= UInt32(optionKey) }
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    /// Conventional macOS order: ⌃⌥⇧⌘.
    var displayString: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    init(eventFlags: NSEvent.ModifierFlags) {
        var modifiers: HotkeyModifiers = []
        if eventFlags.contains(.command) { modifiers.insert(.command) }
        if eventFlags.contains(.option) { modifiers.insert(.option) }
        if eventFlags.contains(.control) { modifiers.insert(.control) }
        if eventFlags.contains(.shift) { modifiers.insert(.shift) }
        self = modifiers
    }
}

extension HotkeyModifiers: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt32.self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Key names

/// Physical ANSI key codes → short, layout-independent labels. Symbols are
/// used instead of words so the same label works in every language.
enum HotkeyKeyNames {
    static func name(for keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"

        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"

        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"

        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "␣"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_DownArrow: return "↓"
        case kVK_UpArrow: return "↑"
        case kVK_Home: return "↖"
        case kVK_End: return "↘"
        case kVK_PageUp: return "⇞"
        case kVK_PageDown: return "⇟"

        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"

        default:
            // Language-neutral fallback for keys we do not have a label for.
            return String(format: "0x%02X", keyCode)
        }
    }

    /// Modifier keys arrive as `flagsChanged`, but filter them anyway so a
    /// stray keyDown cannot create a shortcut with no real key.
    static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_Function, kVK_CapsLock:
            return true
        default:
            return false
        }
    }
}

// MARK: - Hotkey

/// One physical key plus modifiers. Carbon addresses keys by virtual key code
/// (`kVK_ANSI_M`), so the stored value is independent of the layout's glyphs.
struct Hotkey: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: HotkeyModifiers

    init(keyCode: UInt32, modifiers: HotkeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown,
              !HotkeyKeyNames.isModifierKey(event.keyCode) else { return nil }
        self.init(keyCode: UInt32(event.keyCode),
                  modifiers: HotkeyModifiers(eventFlags: event.modifierFlags))
    }

    var displayString: String {
        modifiers.displayString + HotkeyKeyNames.name(for: keyCode)
    }

    var carbonModifiers: UInt32 { modifiers.carbonFlags }
}

// MARK: - Actions

/// Stable actions. Raw values and Carbon IDs are persisted, so never renumber
/// them: `carbonID` becomes `EventHotKeyID.id` and IDs 1/2 are fixed.
enum HotkeyAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case toggleMuteAll
    case resetAll

    var id: String { rawValue }

    var carbonID: UInt32 {
        switch self {
        case .toggleMuteAll: return 1
        case .resetAll: return 2
        }
    }

    var titleKey: L10nKey {
        switch self {
        case .toggleMuteAll: return .hotkeyToggleMuteAll
        case .resetAll: return .hotkeyResetAll
        }
    }

    var defaultHotkey: Hotkey {
        switch self {
        case .toggleMuteAll:
            return Hotkey(keyCode: UInt32(kVK_ANSI_M), modifiers: [.option, .command])
        case .resetAll:
            return Hotkey(keyCode: UInt32(kVK_ANSI_R), modifiers: [.option, .command])
        }
    }

    var defaultBinding: HotkeyBinding {
        HotkeyBinding(hotkey: defaultHotkey, isEnabled: true)
    }
}

// MARK: - Persisted configuration

struct HotkeyBinding: Codable, Equatable, Sendable {
    var hotkey: Hotkey?
    var isEnabled: Bool

    init(hotkey: Hotkey?, isEnabled: Bool = true) {
        self.hotkey = hotkey
        self.isEnabled = isEnabled
    }
}

/// JSON model behind `mixbar.hotkeys.v1`. Bindings are keyed by the action's
/// raw value; a missing entry falls back to the action's default, so adding a
/// new action later does not invalidate an existing file.
struct HotkeyConfiguration: Codable, Equatable, Sendable {
    private var bindings: [String: HotkeyBinding]

    init(bindings: [String: HotkeyBinding] = [:]) {
        self.bindings = bindings
    }

    static var defaults: HotkeyConfiguration {
        var configuration = HotkeyConfiguration()
        for action in HotkeyAction.allCases {
            configuration.bindings[action.rawValue] = action.defaultBinding
        }
        return configuration
    }

    subscript(action: HotkeyAction) -> HotkeyBinding {
        get { bindings[action.rawValue] ?? action.defaultBinding }
        set { bindings[action.rawValue] = newValue }
    }

    /// The other action that already owns this shortcut, if any. Disabled
    /// bindings count too: re-enabling them later must not create a duplicate.
    func duplicateOwner(of action: HotkeyAction) -> HotkeyAction? {
        guard let hotkey = self[action].hotkey else { return nil }
        return HotkeyAction.allCases.first { other in
            other != action && self[other].hotkey == hotkey
        }
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> HotkeyConfiguration? {
        try? JSONDecoder().decode(HotkeyConfiguration.self, from: data)
    }
}

import Foundation
import Observation

/// User-selectable interface language. `.system` follows the first preferred
/// macOS language and falls back to English for anything we do not translate.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case english
    case russian

    public var id: String { rawValue }

    public func resolved(preferredLanguages: [String] = Locale.preferredLanguages) -> ResolvedLanguage {
        switch self {
        case .english: return .english
        case .russian: return .russian
        case .system:
            let code = preferredLanguages.first?
                .split(separator: "-").first
                .map(String.init)?
                .lowercased()
            return code == "ru" ? .russian : .english
        }
    }
}

public enum ResolvedLanguage: String, Sendable, CaseIterable {
    case english
    case russian
}

/// Every user-visible string. Adding a case forces both tables to be updated
/// (enforced by `LocalizationTests`), so a half-translated release cannot ship.
public enum L10nKey: String, CaseIterable, Sendable {
    // Menu bar panel
    case noOutputDevice
    case outputDeviceLabel
    case outputDeviceA11y
    case statusIdle
    case statusPermission
    case statusMixing
    case statusRebuilding
    case statusPaused
    case statusHelpIdle
    case statusHelpPermission
    case statusHelpMixing
    case statusHelpRebuilding
    case statusHelpPaused
    case engineStatusA11y
    case pausedBannerTitle
    case actionSettings
    case actionRetry
    case noAudioTitle
    case noAudioMessage
    case degradedHelp
    case degradedA11y
    case volumeA11y
    case unmuteApp
    case muteApp
    case mutedValue
    case unmutedValue
    case emptyTitle
    case emptyMessage
    case fakeEngineBadge
    case fakeEngineHelp
    case fakeEngineA11y
    case quit
    case quitHelp
    case openSettings

    // Settings window
    case settingsTitle
    case tabGeneral
    case tabAudio
    case tabHotkeys
    case tabAbout
    case sectionLanguage
    case languageLabel
    case languageSystem
    case languageHint
    case sectionStartup
    case launchAtLogin
    case launchAtLoginHint
    case launchAtLoginUnsupported
    case launchAtLoginRequiresApproval
    case openLoginItems
    case launchAtLoginError
    case sectionAudioCapture
    case audioStatusActive
    case audioStatusIdle
    case audioStatusPermission
    case audioStatusPaused
    case audioStatusRebuilding
    case audioStatusActiveMessage
    case audioStatusIdleMessage
    case audioStatusPermissionMessage
    case audioStatusPausedMessage
    case audioStatusRebuildingMessage
    case openSystemSettings
    case retryAction
    case sectionOutput
    case outputDeviceName
    case sectionReset
    case resetAllVolumes
    case resetAllVolumesHint
    case resetConfirmTitle
    case resetConfirmMessage
    case resetAction
    case cancelAction
    case tapLimitNote
    case demoEngineNote
    case aboutTagline
    case aboutEngine
    case aboutEngineCore
    case aboutEngineFake
    case aboutVersion
    case aboutPromise
    case hotkeysPlaceholderTitle
    case hotkeysPlaceholderMessage
}

/// Pure string lookup, independent of SwiftUI, so the catalog can be tested.
public enum LocalizationCatalog {
    public static func string(_ key: L10nKey, language: ResolvedLanguage) -> String {
        let table = language == .russian ? russian : english
        return table[key] ?? english[key] ?? key.rawValue
    }

    /// Keys missing from the given language; tests assert this is empty.
    public static func missingKeys(in language: ResolvedLanguage) -> [L10nKey] {
        let table = language == .russian ? russian : english
        return L10nKey.allCases.filter { table[$0] == nil }
    }

    static let english: [L10nKey: String] = [
        .noOutputDevice: "No output device",
        .outputDeviceLabel: "Output device: %@",
        .outputDeviceA11y: "Output device: %@",
        .statusIdle: "Idle",
        .statusPermission: "Permission",
        .statusMixing: "Mixing",
        .statusRebuilding: "Rebuilding",
        .statusPaused: "Paused",
        .statusHelpIdle: "Nothing is being mixed; untouched apps play at 100%",
        .statusHelpPermission: "Waiting for System Audio Recording permission",
        .statusHelpMixing: "Per-app volume is being applied",
        .statusHelpRebuilding: "Audio graph is being rebuilt",
        .statusHelpPaused: "MixBar is paused; audio plays normally",
        .engineStatusA11y: "Engine status: %@",
        .pausedBannerTitle: "MixBar paused — audio is normal",
        .actionSettings: "Settings",
        .actionRetry: "Retry",
        .noAudioTitle: "No audio detected",
        .noAudioMessage: "If an app is silent, allow System Audio Recording for MixBar in System Settings.",
        .degradedHelp: "MixBar cannot control this app (%@); it plays at 100%",
        .degradedA11y: "Limited control: %@",
        .volumeA11y: "Volume for %@",
        .unmuteApp: "Unmute %@",
        .muteApp: "Mute %@",
        .mutedValue: "Muted",
        .unmutedValue: "Unmuted",
        .emptyTitle: "Nothing is playing audio",
        .emptyMessage: "Apps appear here while they produce sound.",
        .fakeEngineBadge: "FAKE ENGINE",
        .fakeEngineHelp: "Synthetic audio drives the real engine. Use MIXBAR_ENGINE=core for real apps.",
        .fakeEngineA11y: "Fake audio engine",
        .quit: "Quit",
        .quitHelp: "Quit MixBar",
        .openSettings: "Open settings",

        .settingsTitle: "Settings",
        .tabGeneral: "General",
        .tabAudio: "Audio",
        .tabHotkeys: "Shortcuts",
        .tabAbout: "About",
        .sectionLanguage: "Language",
        .languageLabel: "Interface language",
        .languageSystem: "System",
        .languageHint: "Changes apply immediately.",
        .sectionStartup: "Startup",
        .launchAtLogin: "Launch MixBar at login",
        .launchAtLoginHint: "MixBar will appear in the menu bar after you log in.",
        .launchAtLoginUnsupported: "Move MixBar to Applications to enable this.",
        .launchAtLoginRequiresApproval: "macOS requires approval in Login Items.",
        .openLoginItems: "Open Login Items",
        .launchAtLoginError: "Could not change the login item: %@",
        .sectionAudioCapture: "Audio capture",
        .audioStatusActive: "Active",
        .audioStatusIdle: "Idle",
        .audioStatusPermission: "Permission needed",
        .audioStatusPaused: "Paused",
        .audioStatusRebuilding: "Rebuilding",
        .audioStatusActiveMessage: "MixBar is controlling the apps that are playing now.",
        .audioStatusIdleMessage: "Apps appear here when they start producing sound.",
        .audioStatusPermissionMessage: "Allow System Audio Recording for MixBar, otherwise apps play at 100%.",
        .audioStatusPausedMessage: "MixBar stopped control so apps keep playing. Check the permission, then retry.",
        .audioStatusRebuildingMessage: "The audio graph is being rebuilt after an output change.",
        .openSystemSettings: "Open System Settings",
        .retryAction: "Retry",
        .sectionOutput: "Output",
        .outputDeviceName: "Output device",
        .sectionReset: "Reset",
        .resetAllVolumes: "Reset all volumes to 100%",
        .resetAllVolumesHint: "Clears saved volume settings and releases every app.",
        .resetConfirmTitle: "Reset all volumes?",
        .resetConfirmMessage: "All apps return to 100% and saved values are deleted.",
        .resetAction: "Reset",
        .cancelAction: "Cancel",
        .tapLimitNote: "MixBar can control up to 16 apps at once.",
        .demoEngineNote: "Demo engine: synthetic audio, no permission needed.",
        .aboutTagline: "Per-app volume mixer for macOS.",
        .aboutEngine: "Audio engine",
        .aboutEngineCore: "Core Audio process taps",
        .aboutEngineFake: "Demo (synthetic audio)",
        .aboutVersion: "Version %@",
        .aboutPromise: "No virtual audio driver. No kernel extensions.",
        .hotkeysPlaceholderTitle: "Global shortcuts",
        .hotkeysPlaceholderMessage: "Shortcut configuration will appear here soon.",
    ]

    static let russian: [L10nKey: String] = [
        .noOutputDevice: "Нет устройства вывода",
        .outputDeviceLabel: "Устройство вывода: %@",
        .outputDeviceA11y: "Устройство вывода: %@",
        .statusIdle: "Ожидание",
        .statusPermission: "Разрешение",
        .statusMixing: "Микширование",
        .statusRebuilding: "Пересборка",
        .statusPaused: "Пауза",
        .statusHelpIdle: "Ничего не микшируется; приложения без изменений играют на 100%",
        .statusHelpPermission: "Ожидание разрешения на запись системного звука",
        .statusHelpMixing: "Применяется громкость приложений",
        .statusHelpRebuilding: "Аудиограф пересобирается",
        .statusHelpPaused: "MixBar на паузе; звук воспроизводится как обычно",
        .engineStatusA11y: "Состояние движка: %@",
        .pausedBannerTitle: "MixBar на паузе — звук в норме",
        .actionSettings: "Настройки",
        .actionRetry: "Повторить",
        .noAudioTitle: "Звук не обнаружен",
        .noAudioMessage: "Если приложение молчит, разрешите MixBar запись системного звука в Настройках системы.",
        .degradedHelp: "MixBar не может управлять этим приложением (%@); оно играет на 100%",
        .degradedA11y: "Ограниченное управление: %@",
        .volumeA11y: "Громкость для %@",
        .unmuteApp: "Включить звук: %@",
        .muteApp: "Выключить звук: %@",
        .mutedValue: "Без звука",
        .unmutedValue: "Со звуком",
        .emptyTitle: "Ничего не воспроизводится",
        .emptyMessage: "Приложения появятся здесь, пока воспроизводят звук.",
        .fakeEngineBadge: "ДЕМО-ДВИЖОК",
        .fakeEngineHelp: "Синтетический звук управляет реальным движком. Для реальных приложений: MIXBAR_ENGINE=core.",
        .fakeEngineA11y: "Демонстрационный аудиодвижок",
        .quit: "Выйти",
        .quitHelp: "Выйти из MixBar",
        .openSettings: "Открыть настройки",

        .settingsTitle: "Настройки",
        .tabGeneral: "Основные",
        .tabAudio: "Звук",
        .tabHotkeys: "Сочетания",
        .tabAbout: "О программе",
        .sectionLanguage: "Язык",
        .languageLabel: "Язык интерфейса",
        .languageSystem: "Системный",
        .languageHint: "Изменения применяются сразу.",
        .sectionStartup: "Запуск",
        .launchAtLogin: "Запускать MixBar при входе",
        .launchAtLoginHint: "MixBar появится в строке меню после входа в систему.",
        .launchAtLoginUnsupported: "Чтобы включить автозапуск, переместите MixBar в папку «Программы».",
        .launchAtLoginRequiresApproval: "macOS требует подтверждения в разделе «Объекты входа».",
        .openLoginItems: "Открыть «Объекты входа»",
        .launchAtLoginError: "Не удалось изменить автозапуск: %@",
        .sectionAudioCapture: "Захват звука",
        .audioStatusActive: "Активно",
        .audioStatusIdle: "Ожидание",
        .audioStatusPermission: "Нужно разрешение",
        .audioStatusPaused: "Пауза",
        .audioStatusRebuilding: "Пересборка",
        .audioStatusActiveMessage: "MixBar управляет приложениями, которые звучат сейчас.",
        .audioStatusIdleMessage: "Приложения появятся здесь, когда начнут воспроизводить звук.",
        .audioStatusPermissionMessage: "Разрешите MixBar запись системного звука, иначе приложения будут играть на 100%.",
        .audioStatusPausedMessage: "MixBar отключил управление, чтобы приложения не остались без звука. Проверьте разрешение и повторите.",
        .audioStatusRebuildingMessage: "Аудиограф пересобирается после смены устройства вывода.",
        .openSystemSettings: "Открыть Настройки системы",
        .retryAction: "Повторить",
        .sectionOutput: "Вывод",
        .outputDeviceName: "Устройство вывода",
        .sectionReset: "Сброс",
        .resetAllVolumes: "Сбросить громкость всех приложений до 100%",
        .resetAllVolumesHint: "Удаляет сохранённые значения громкости и освобождает все приложения.",
        .resetConfirmTitle: "Сбросить все громкости?",
        .resetConfirmMessage: "Все приложения вернутся к 100%, сохранённые значения будут удалены.",
        .resetAction: "Сбросить",
        .cancelAction: "Отмена",
        .tapLimitNote: "MixBar управляет максимум 16 приложениями одновременно.",
        .demoEngineNote: "Демонстрационный движок: синтетический звук, разрешение не требуется.",
        .aboutTagline: "Микшер громкости приложений для macOS.",
        .aboutEngine: "Аудиодвижок",
        .aboutEngineCore: "Захват звука приложений Core Audio",
        .aboutEngineFake: "Демонстрационный (синтетический звук)",
        .aboutVersion: "Версия %@",
        .aboutPromise: "Без виртуального аудиодрайвера. Без расширений ядра.",
        .hotkeysPlaceholderTitle: "Глобальные горячие клавиши",
        .hotkeysPlaceholderMessage: "Настройка сочетаний появится здесь в ближайшее время.",
    ]
}

/// Observable, persisted language selection. Views read `t(...)` in their body,
/// so switching the language re-renders them immediately — no relaunch.
@MainActor
@Observable
public final class LocalizationStore {
    public static let defaultsKey = "mixbar.language"

    @ObservationIgnored private let defaults: UserDefaults

    public var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Self.defaultsKey)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.language = defaults.string(forKey: Self.defaultsKey)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    public var resolvedLanguage: ResolvedLanguage {
        language.resolved()
    }

    public func t(_ key: L10nKey) -> String {
        LocalizationCatalog.string(key, language: resolvedLanguage)
    }

    public func t(_ key: L10nKey, _ arguments: CVarArg...) -> String {
        String(format: LocalizationCatalog.string(key, language: resolvedLanguage),
               arguments: arguments)
    }
}

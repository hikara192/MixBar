import AppKit
import SwiftUI
import MixBarCore
import MixBarLocalization

/// Standard Settings window (⌘,): language, launch at login, audio status,
/// reset, shortcuts and about. All strings go through `LocalizationStore`,
/// so switching the language updates the window without a relaunch.
struct SettingsView: View {
    let store: MixerStore
    @Bindable var l10n: LocalizationStore
    @Bindable var launchAtLogin: LaunchAtLoginController
    @Bindable var hotkeys: HotkeyStore

    @State private var tab: SettingsTab = .general
    @State private var showResetConfirmation = false

    private enum SettingsTab: Hashable {
        case general, audio, hotkeys, about
    }

    var body: some View {
        TabView(selection: $tab) {
            generalTab
                .tabItem { Label(l10n.t(.tabGeneral), systemImage: "gearshape") }
                .tag(SettingsTab.general)

            audioTab
                .tabItem { Label(l10n.t(.tabAudio), systemImage: "waveform") }
                .tag(SettingsTab.audio)

            HotkeysSettingsView(hotkeys: hotkeys, l10n: l10n)
                .tabItem { Label(l10n.t(.tabHotkeys), systemImage: "keyboard") }
                .tag(SettingsTab.hotkeys)

            aboutTab
                .tabItem { Label(l10n.t(.tabAbout), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .navigationTitle(l10n.t(.settingsTitle))
        .frame(width: 560, height: 470)
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
        .confirmationDialog(l10n.t(.resetConfirmTitle),
                            isPresented: $showResetConfirmation,
                            titleVisibility: .visible) {
            Button(l10n.t(.resetAction), role: .destructive) {
                store.resetAllVolumes()
            }
            Button(l10n.t(.cancelAction), role: .cancel) {}
        } message: {
            Text(l10n.t(.resetConfirmMessage))
        }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                Picker(l10n.t(.languageLabel), selection: $l10n.language) {
                    Text(l10n.t(.languageSystem)).tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Русский").tag(AppLanguage.russian)
                }
                .pickerStyle(.menu)

                Text(l10n.t(.languageHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(l10n.t(.sectionLanguage))
            }

            Section {
                Toggle(l10n.t(.launchAtLogin), isOn: launchAtLoginBinding)
                    .disabled(!launchAtLogin.isSupportedLocation)

                if !launchAtLogin.isSupportedLocation {
                    Text(l10n.t(.launchAtLoginUnsupported))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if launchAtLogin.requiresApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Text(l10n.t(.launchAtLoginRequiresApproval))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button(l10n.t(.openLoginItems)) {
                            launchAtLogin.openLoginItemsSettings()
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                } else {
                    Text(l10n.t(.launchAtLoginHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = launchAtLogin.lastError {
                    Text(l10n.t(.launchAtLoginError, error))
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text(l10n.t(.sectionStartup))
            }
        }
        .formStyle(.grouped)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    // MARK: - Audio

    private var audioTab: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(audioStatus.color)
                        .frame(width: 8, height: 8)
                        .padding(.top, 5)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(audioStatus.title)
                            .font(.system(size: 12, weight: .semibold))
                        Text(audioStatus.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if case .failed(let reason) = store.snapshot.engine {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                HStack(spacing: 8) {
                    Button(l10n.t(.openSystemSettings)) {
                        store.openPrivacySettings()
                    }
                    Button(l10n.t(.retryAction)) {
                        store.retryPermission()
                    }
                }

                if store.snapshot.usesFakeEngine {
                    Text(l10n.t(.demoEngineNote))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(l10n.t(.sectionAudioCapture))
            }

            Section {
                LabeledContent(l10n.t(.outputDeviceName)) {
                    Text(store.snapshot.outputDeviceName ?? l10n.t(.noOutputDevice))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(l10n.t(.sectionOutput))
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirmation = true
                } label: {
                    Text(l10n.t(.resetAllVolumes))
                }

                Text(l10n.t(.resetAllVolumesHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(l10n.t(.tapLimitNote))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } header: {
                Text(l10n.t(.sectionReset))
            }
        }
        .formStyle(.grouped)
    }

    private var audioStatus: (title: String, message: String, color: Color) {
        if store.snapshot.permissionSuspected || store.snapshot.engine == .onboarding {
            return (l10n.t(.audioStatusPermission),
                    l10n.t(.audioStatusPermissionMessage), .orange)
        }
        switch store.snapshot.engine {
        case .active:
            return (l10n.t(.audioStatusActive),
                    l10n.t(.audioStatusActiveMessage), .green)
        case .rebuilding:
            return (l10n.t(.audioStatusRebuilding),
                    l10n.t(.audioStatusRebuildingMessage), .orange)
        case .failed:
            return (l10n.t(.audioStatusPaused),
                    l10n.t(.audioStatusPausedMessage), .red)
        case .idle, .onboarding:
            return (l10n.t(.audioStatusIdle),
                    l10n.t(.audioStatusIdleMessage), .secondary)
        }
    }

    // MARK: - About

    private var aboutTab: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("MixBar")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(l10n.t(.aboutVersion, Self.version))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(l10n.t(.aboutTagline))
                .font(.callout)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 240)
                .padding(.vertical, 2)

            VStack(spacing: 4) {
                Text(l10n.t(.aboutEngine))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.snapshot.usesFakeEngine
                     ? l10n.t(.aboutEngineFake)
                     : l10n.t(.aboutEngineCore))
                    .font(.system(size: 12, weight: .medium))
            }

            Text(l10n.t(.aboutPromise))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            ?? "0.1.0"
    }
}

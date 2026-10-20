import AppKit
import Carbon.HIToolbox
import SwiftUI
import MixBarLocalization

/// Settings → Shortcuts. Each action has a recorder field, a clear button and
/// an enable switch; edits are validated by `HotkeyStore` and re-registered by
/// `HotkeyManager` immediately.
struct HotkeysSettingsView: View {
    @Bindable var hotkeys: HotkeyStore
    @Bindable var l10n: LocalizationStore

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    actionRow(action)
                }

                if let warning = hotkeys.warning {
                    Label(warningText(warning), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                }
            } header: {
                Text(l10n.t(.sectionHotkeys))
            } footer: {
                Text(l10n.t(.hotkeysHint))
            }

            Section {
                Button(l10n.t(.hotkeysRestoreDefaults)) {
                    hotkeys.endRecording()
                    hotkeys.resetToDefaults()
                }

                Text(l10n.t(.hotkeysRecorderHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onDisappear {
            hotkeys.endRecording()
        }
    }

    // MARK: - Row

    private func actionRow(_ action: HotkeyAction) -> some View {
        let binding = hotkeys.binding(for: action)
        let status = hotkeys.status(for: action)
        let isRecording = hotkeys.recordingAction == action

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(l10n.t(action.titleKey))
                    .font(.system(size: 12, weight: .medium))

                Text(statusText(status))
                    .font(.caption)
                    .foregroundStyle(statusColor(status))
                    .help(status == .unavailable ? l10n.t(.hotkeyUnavailableHint) : "")
            }

            Spacer(minLength: 8)

            recorderField(action: action, binding: binding, isRecording: isRecording)

            Button {
                hotkeys.endRecording()
                hotkeys.clear(action)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(binding.hotkey == nil)
            .help(l10n.t(.hotkeyClear))
            .accessibilityLabel(l10n.t(.hotkeyClear))

            Toggle("", isOn: enabledBinding(action))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(binding.hotkey == nil)
                .help(l10n.t(.hotkeyEnable))
                .accessibilityLabel(l10n.t(.hotkeyEnable))
        }
        .padding(.vertical, 3)
    }

    private func recorderField(action: HotkeyAction,
                               binding: HotkeyBinding,
                               isRecording: Bool) -> some View {
        let text = isRecording
            ? l10n.t(.hotkeyRecording)
            : (binding.hotkey?.displayString ?? l10n.t(.hotkeyNotSet))

        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: isRecording ? 1.5 : 1)
                }

            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(binding.hotkey == nil && !isRecording ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
        }
        .frame(width: 132, height: 26)
        .overlay {
            HotkeyRecorderView(
                isRecording: isRecording,
                help: l10n.t(.hotkeysHint),
                accessibilityLabel: l10n.t(.hotkeyRecorderA11y, l10n.t(action.titleKey)),
                onBegin: { hotkeys.beginRecording(action) },
                onKeyDown: { handleKeyDown($0, for: action) },
                onCancel: { hotkeys.endRecording() }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t(.hotkeyRecorderA11y, l10n.t(action.titleKey)))
        .accessibilityValue(text)
        .accessibilityAddTraits(.isButton)
    }

    private func handleKeyDown(_ event: NSEvent, for action: HotkeyAction) -> Bool {
        guard hotkeys.recordingAction == action else { return false }

        switch Int(event.keyCode) {
        case kVK_Escape:
            hotkeys.endRecording()
            return true

        case kVK_Delete, kVK_ForwardDelete:
            hotkeys.clear(action)
            hotkeys.endRecording()
            return true

        default:
            guard let hotkey = Hotkey(event: event) else { return true }
            if hotkeys.assign(hotkey, to: action) == .applied {
                hotkeys.endRecording()
            }
            return true
        }
    }

    // MARK: - Helpers

    private func enabledBinding(_ action: HotkeyAction) -> Binding<Bool> {
        Binding(
            get: { hotkeys.binding(for: action).isEnabled },
            set: { hotkeys.setEnabled($0, for: action) }
        )
    }

    private func statusText(_ status: HotkeyRegistrationStatus) -> String {
        switch status {
        case .active: return l10n.t(.hotkeyStatusActive)
        case .disabled: return l10n.t(.hotkeyStatusDisabled)
        case .notSet: return l10n.t(.hotkeyNotSet)
        case .unavailable: return l10n.t(.hotkeyStatusUnavailable)
        }
    }

    private func statusColor(_ status: HotkeyRegistrationStatus) -> Color {
        switch status {
        case .active: return .green
        case .disabled, .notSet: return .secondary
        case .unavailable: return .orange
        }
    }

    private func warningText(_ warning: HotkeyValidationError) -> String {
        switch warning {
        case .needsModifier:
            return l10n.t(.hotkeyNeedsModifier)
        case .conflict(let other):
            return l10n.t(.hotkeyConflict, l10n.t(other.titleKey))
        }
    }
}

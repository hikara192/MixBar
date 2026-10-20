import SwiftUI
import AppKit
import MixBarCore
import MixBarLocalization

// MARK: - Header

struct HeaderView: View {
    let snapshot: MixerSnapshot
    let l10n: LocalizationStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("MixBar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(snapshot.outputDeviceName ?? l10n.t(.noOutputDevice))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel(l10n.t(.outputDeviceA11y,
                                               snapshot.outputDeviceName ?? l10n.t(.noOutputDevice)))
            }

            Spacer(minLength: 6)

            StatusBadge(engine: snapshot.engine, l10n: l10n)
        }
    }
}

struct StatusBadge: View {
    let engine: EngineState
    let l10n: LocalizationStore

    var body: some View {
        let style = style(for: engine)
        HStack(spacing: 4) {
            Circle()
                .fill(style.color)
                .frame(width: 5, height: 5)
            Text(style.title)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(style.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.color.opacity(0.12)))
        .help(style.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(l10n.t(.engineStatusA11y, style.title))
    }

    private struct Style {
        let title: String
        let color: Color
        let help: String
    }

    private func style(for engine: EngineState) -> Style {
        switch engine {
        case .idle:
            Style(title: l10n.t(.statusIdle), color: .secondary,
                  help: l10n.t(.statusHelpIdle))
        case .onboarding:
            Style(title: l10n.t(.statusPermission), color: .orange,
                  help: l10n.t(.statusHelpPermission))
        case .active:
            Style(title: l10n.t(.statusMixing), color: .green,
                  help: l10n.t(.statusHelpMixing))
        case .rebuilding:
            Style(title: l10n.t(.statusRebuilding), color: .orange,
                  help: l10n.t(.statusHelpRebuilding))
        case .failed:
            Style(title: l10n.t(.statusPaused), color: .red,
                  help: l10n.t(.statusHelpPaused))
        }
    }
}

// MARK: - Row

struct RowView: View {
    let store: MixerStore
    let row: AppRow
    let l10n: LocalizationStore

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            AppIconView(image: store.icon(for: row.identity))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text(row.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(row.desired.muted ? Color.secondary : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if case .degraded(let reason) = row.rowState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .help(l10n.t(.degradedHelp, reason))
                            .accessibilityLabel(l10n.t(.degradedA11y, reason))
                    }

                    Spacer(minLength: 4)

                    Text(percentText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(minWidth: 30, alignment: .trailing)
                        .accessibilityHidden(true)
                }

                HStack(spacing: 8) {
                    MeterView(level: store.meter(for: row.identity))
                        .frame(maxWidth: .infinity)

                    Slider(value: gainBinding, in: 0...1)
                        .controlSize(.mini)
                        .tint(.accentColor)
                        .frame(width: 84)
                        .disabled(row.desired.muted)
                        .opacity(row.desired.muted ? 0.45 : 1)
                        .accessibilityLabel(l10n.t(.volumeA11y, row.displayName))
                        .accessibilityValue(percentText)

                    muteButton
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var gainBinding: Binding<Float> {
        Binding(
            get: { row.desired.gain },
            set: { store.setGain($0, for: row.identity) }
        )
    }

    private var percentText: String {
        let gain = min(1, max(0, row.desired.gain))
        return "\(Int((gain * 100).rounded()))%"
    }

    private var muteButton: some View {
        Button {
            store.setMuted(!row.desired.muted, for: row.identity)
        } label: {
            Image(systemName: row.desired.muted ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(row.desired.muted ? Color.accentColor : Color.secondary)
                .background(
                    Circle().fill(row.desired.muted ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(row.desired.muted
              ? l10n.t(.unmuteApp, row.displayName)
              : l10n.t(.muteApp, row.displayName))
        .accessibilityLabel(row.desired.muted
                            ? l10n.t(.unmuteApp, row.displayName)
                            : l10n.t(.muteApp, row.displayName))
        .accessibilityValue(row.desired.muted ? l10n.t(.mutedValue) : l10n.t(.unmutedValue))
    }
}

struct AppIconView: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    Circle().fill(Color.primary.opacity(0.08))
                    Image(systemName: "waveform")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Meter

struct MeterView: View {
    let level: Float

    private var clamped: CGFloat { CGFloat(min(1, max(0, level))) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Self.gradient
                    .frame(width: geo.size.width, height: 4)
                    .clipShape(Capsule())
                    .mask(alignment: .leading) {
                        Capsule().frame(width: geo.size.width * clamped, height: 4)
                    }
            }
            .frame(width: geo.size.width, height: 4)
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }

    /// Mint → green, warning yellow only at the top of the scale so the
    /// colour reads as "loud" rather than as a decoration.
    private static let gradient = LinearGradient(
        stops: [
            .init(color: .mint, location: 0.0),
            .init(color: .green, location: 0.55),
            .init(color: .green, location: 0.8),
            .init(color: .yellow, location: 1.0),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Banners and empty state

struct NoticeBanner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    private let actions: () -> Actions

    init(symbol: String, tint: Color, title: String, message: String,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions
    }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint.opacity(0.14)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(tint.opacity(0.16), lineWidth: 1)
        )
    }
}

struct EmptyStateView: View {
    let l10n: LocalizationStore

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(l10n.t(.emptyTitle))
                    .font(.system(size: 12, weight: .medium))
                Text(l10n.t(.emptyMessage))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Footer

struct FooterView: View {
    let store: MixerStore
    let l10n: LocalizationStore

    var body: some View {
        HStack(spacing: 8) {
            if store.snapshot.usesFakeEngine {
                HStack(spacing: 4) {
                    Image(systemName: "testtube.2")
                        .font(.system(size: 8, weight: .bold))
                    Text(l10n.t(.fakeEngineBadge))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.4)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
                .help(l10n.t(.fakeEngineHelp))
                .accessibilityLabel(l10n.t(.fakeEngineA11y))
            }

            Spacer(minLength: 8)

            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(l10n.t(.openSettings))
            .accessibilityLabel(l10n.t(.openSettings))

            Button {
                store.quit()
            } label: {
                Text(l10n.t(.quit))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(l10n.t(.quitHelp))
            .accessibilityLabel(l10n.t(.quitHelp))
        }
    }
}

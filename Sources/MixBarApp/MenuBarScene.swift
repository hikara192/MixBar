import SwiftUI
import MixBarCore

/// Menu bar panel: one row per audible app, footer with engine state.
/// Localization (String Catalog, ru/en) lands with slice 2; strings are
/// inline English for the walking skeleton.
struct MenuBarScene: View {
    let store: MixerStore

    var body: some View {
        VStack(spacing: 0) {
            if case .failed(let reason) = store.snapshot.engine {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("MixBar paused — audio is normal").font(.caption).bold()
                        Text(reason).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Settings") { store.openPrivacySettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                    Button("Retry") { store.retryPermission() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.red.opacity(0.12)))
                .padding(.bottom, 6)
            } else if store.snapshot.permissionSuspected {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("No audio detected")
                            .font(.caption).bold()
                        Text("If an app is silent, allow System Audio Recording for MixBar in System Settings.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Button("Settings") { store.openPrivacySettings() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.yellow.opacity(0.12)))
                .padding(.bottom, 6)
            }
            if store.snapshot.rows.isEmpty {
                VStack(spacing: 4) {
                    Text("Nothing is playing audio")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("Apps appear here while they produce sound.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 24)
            } else {
                ForEach(store.snapshot.rows) { row in
                    RowView(store: store, row: row)
                }
            }
            Divider().padding(.vertical, 8)
            FooterView(store: store)
        }
        .padding(10)
        .frame(width: 320)
    }
}

struct RowView: View {
    let store: MixerStore
    let row: AppRow

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(row.displayName)
                        .font(.callout)
                        .lineLimit(1)
                    if case .degraded = row.rowState {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("MixBar cannot control this app; it plays at 100%")
                    }
                    if row.desired.muted {
                        Text("muted")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                MeterView(level: store.meter(for: row.identity))
            }
            Slider(value: Binding(
                get: { row.desired.gain },
                set: { store.setGain($0, for: row.identity) }
            ), in: 0...1)
            .disabled(row.desired.muted)
            Button {
                store.setMuted(!row.desired.muted, for: row.identity)
            } label: {
                Image(systemName: row.desired.muted
                      ? "speaker.slash.fill"
                      : "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .help("Mute / unmute this app")
        }
        .padding(.vertical, 5)
    }
}

struct MeterView: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(.green)
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, level))))
            }
        }
        .frame(height: 4)
    }
}

struct FooterView: View {
    let store: MixerStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(engineText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let name = store.snapshot.outputDeviceName {
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if store.snapshot.usesFakeEngine {
                Text("FAKE ENGINE")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.orange.opacity(0.15)))
                    .help("Walking skeleton: synthetic audio drives the real engine. Set MIXBAR_ENGINE=core after spikes.")
            }
            Button("Quit") { store.quit() }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var engineText: String {
        switch store.snapshot.engine {
        case .idle: "Idle — nothing to mix"
        case .onboarding: "Onboarding"
        case .active: "Mixing"
        case .rebuilding: "Rebuilding audio graph…"
        case .failed: "MixBar paused — audio is normal"
        }
    }
}

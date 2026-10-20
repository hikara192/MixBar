import SwiftUI
import MixBarCore

/// Menu bar panel: header with device + engine state, one row per audible app,
/// banners for permission/engine problems, footer with engine badge and Quit.
struct MenuBarScene: View {
    let store: MixerStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(snapshot: store.snapshot)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            VStack(spacing: 8) {
                banners

                if store.snapshot.rows.isEmpty {
                    EmptyStateView()
                } else {
                    rowList
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            FooterView(store: store)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 340)
    }

    @ViewBuilder
    private var banners: some View {
        if case .failed(let reason) = store.snapshot.engine {
            NoticeBanner(
                symbol: "exclamationmark.triangle.fill",
                tint: .red,
                title: "MixBar paused — audio is normal",
                message: reason
            ) {
                HStack(spacing: 6) {
                    Button("Settings") { store.openPrivacySettings() }
                    Button("Retry") { store.retryPermission() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if store.snapshot.permissionSuspected {
            NoticeBanner(
                symbol: "waveform.slash",
                tint: .orange,
                title: "No audio detected",
                message: "If an app is silent, allow System Audio Recording for MixBar in System Settings."
            ) {
                Button("Settings") { store.openPrivacySettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var rowList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(store.snapshot.rows) { row in
                    RowView(store: store, row: row)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: 320)
    }
}

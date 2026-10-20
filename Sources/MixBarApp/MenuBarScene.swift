import SwiftUI
import MixBarCore
import MixBarLocalization

/// Menu bar panel: header with device + engine state, one row per audible app,
/// banners for permission/engine problems, footer with engine badge, settings
/// and Quit.
struct MenuBarScene: View {
    let store: MixerStore
    let l10n: LocalizationStore

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(snapshot: store.snapshot, l10n: l10n)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            VStack(spacing: 8) {
                banners

                if store.snapshot.rows.isEmpty {
                    EmptyStateView(l10n: l10n)
                } else {
                    rowList
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            Divider()

            FooterView(store: store, l10n: l10n)
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
                title: l10n.t(.pausedBannerTitle),
                message: reason
            ) {
                HStack(spacing: 6) {
                    Button(l10n.t(.actionSettings)) { store.openPrivacySettings() }
                    Button(l10n.t(.actionRetry)) { store.retryPermission() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if store.snapshot.permissionSuspected {
            NoticeBanner(
                symbol: "waveform.slash",
                tint: .orange,
                title: l10n.t(.noAudioTitle),
                message: l10n.t(.noAudioMessage)
            ) {
                Button(l10n.t(.actionSettings)) { store.openPrivacySettings() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }

    private var rowList: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 1) {
                ForEach(store.snapshot.rows) { row in
                    RowView(store: store, row: row, l10n: l10n)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .frame(maxHeight: 320)
    }
}

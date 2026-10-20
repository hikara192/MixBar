import SwiftUI
import MixBarCore

/// Walking skeleton entry point (ARCHITECTURE.md §15).
///
/// Engine selection via the MIXBAR_ENGINE environment variable:
/// - "fake" (default): FakeAudioSystem drives the REAL control plane and
///   REAL RenderCore with synthetic tap buffers — no Core Audio involved.
/// - "core": CoreAudioSystem with real process taps. Enable only after
///   spikes S1–S4 pass; it triggers the System Audio Recording prompt.
@main
struct MixBarApp: App {
    private let store: MixerStore = {
        let raw = ProcessInfo.processInfo.environment["MIXBAR_ENGINE"] ?? "fake"
        let fake = raw != "core"
        let audio: AudioSystem = fake ? FakeAudioSystem() : CoreAudioSystem()
        let catalog: ProcessCataloging = fake
            ? FakeProcessCatalog()
            : ProcessCatalog(audioSystem: audio)
        let graph = GraphOwner(audioSystem: audio, catalog: catalog,
                               settings: SettingsStore(), fakeEngine: fake)
        return MixerStore(graph: graph)
    }()

    var body: some Scene {
        MenuBarExtra("MixBar", systemImage: "slider.horizontal.3") {
            MenuBarScene(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

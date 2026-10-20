import SwiftUI
import MixBarCore

/// Walking skeleton entry point (ARCHITECTURE.md §15).
///
/// Engine selection via the MIXBAR_ENGINE environment variable:
/// - "core" (default): CoreAudioSystem with real process taps. Spike S1
///   validated taps/aggregate/IOProc and the interleaved buffer layout.
/// - "fake": FakeAudioSystem drives the REAL control plane and REAL
///   RenderCore with synthetic buffers — no Core Audio, no permission prompt.
@main
struct MixBarApp: App {
    private let store: MixerStore = {
        let raw = ProcessInfo.processInfo.environment["MIXBAR_ENGINE"] ?? "core"
        let fake = raw == "fake"
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

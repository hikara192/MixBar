import Foundation
import AppKit
import Observation
import MixBarCore

/// UI-facing store (ARCHITECTURE.md §4, ADR-004): the UI observes immutable
/// snapshots; it never touches Core Audio or the graph directly.
@MainActor @Observable
final class MixerStore {
    let graph: GraphOwner
    private(set) var snapshot: MixerSnapshot

    init(graph: GraphOwner) {
        self.graph = graph
        self.snapshot = graph.snapshot()
        // UI-rate polling (30 Hz): snapshots and meters. Not audio rate;
        // peaks cross the boundary via atomic reads (RenderContext).
        Task { @MainActor [weak self] in
            while let self {
                self.snapshot = self.graph.snapshot()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    func setGain(_ gain: Float, for id: AppIdentity) {
        graph.submit(.setGain(id, gain))
    }

    func setMuted(_ muted: Bool, for id: AppIdentity) {
        graph.submit(.setMuted(id, muted))
    }

    func meter(for id: AppIdentity) -> Float {
        graph.meter(for: id)
    }

    func quit() {
        // Safe by design: HAL destroys process-owned taps on exit and
        // mutedWhenTapped auto-restores audio (never-silence invariant).
        graph.submit(.shutdown)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            NSApplication.shared.terminate(nil)
        }
    }
}

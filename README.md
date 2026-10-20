# MixBar

Per-app volume and mute in the macOS menu bar. Built on private Core Audio
process taps and one private aggregate device: no virtual audio driver, no
kext, no admin rights.

Full design, ADRs and fitness functions: **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Status: walking skeleton

The control plane and the data plane are real and covered by tests. The Core
Audio backend compiles against the SDK but has not been runtime-validated yet
(that is what the spikes are for).

| Layer | State |
|---|---|
| `RenderCore` + slot table (RT mixing, ramps, clamp, peaks) | **real**, tested |
| `GraphOwner` + `Reconciler` (single writer, idempotent reconcile) | **real**, tested |
| `SettingsStore`, discovery model, menu bar UI | **real**, tested |
| `FakeAudioSystem` — drives the real `RenderCore` with synthetic tap buffers | **real**, default engine |
| `CoreAudioSystem` — process taps, private aggregate, IOProc | compiles, **unvalidated** |

Default engine is `fake`: the menu bar app is fully functional, the meters are
driven by the real render path, but no audio is touched.

## Build and run

```bash
swift build
swift run MixBarApp            # fake engine; Dock icon (no bundle in dev)

Scripts/build-app.sh           # -> build/MixBar.app (LSUIElement, menu bar only)
open build/MixBar.app
```

Engine selection: `MIXBAR_ENGINE=fake|core` (default `fake`).
`core` switches to the real Core Audio backend — enable it only after the
spikes below pass, and expect the System Audio Recording permission prompt on
the first slider adjustment.

## Tests

```bash
swift test                     # 20 tests: render math, reconciler, settings, end-to-end
Scripts/check-deps.sh          # fitness functions: dependency + RT-purity checks
```

`GraphOwnerEndToEndTests` runs the whole chain — reconciler, taps, slot
assignment, real `RenderCore`, peak publishing, teardown back to unity — with
the fake audio system only substituting the Core Audio calls.

## Repository map

```
Sources/CAtomic/               C11 atomics shim shared with the RT path
Sources/MixBarCore/
  Model/                       AppIdentity, AppRow, EngineState, MixerIntent
  Render/                      RenderCore, RenderContext — no Foundation, no UI
  AudioSystem/                 AudioSystem protocol, CoreAudioSystem, FakeAudioSystem
  Graph/                       GraphOwner — the only writer of the audio graph
  Discovery/                   process catalog, helper grouping, exclusions
  Reconciler/                  pure desired-state planner
  Persistence/                 SettingsStore (UserDefaults, bundle-ID keyed)
Sources/MixBarApp/             SwiftUI menu bar UI
Tests/MixBarTests/
AppResources/Info.plist        LSUIElement, NSAudioCaptureUsageDescription
Scripts/                       build-app.sh, check-deps.sh
Spikes/                        S1–S4, Week 0 (throwaway)
```

## Invariants

1. **Untouched apps are never tapped** — bit-perfect, zero overhead (ADR-002).
2. **Failures degrade to "no per-app control", never to silence.**
   `mutedWhenTapped` auto-restores audio when taps are destroyed or the process
   dies; every error path tears the graph down.
3. **One writer** for the audio graph; the reconciler is idempotent.
4. **The RT path allocates nothing, locks nothing, logs nothing** — state
   crosses the boundary through C11 atomics only.

## Next step: Week-0 spikes

See [Spikes/README.md](Spikes/README.md). S1 (tap + aggregate + IOProc
end-to-end, crash restore, flash window, latency) gates the switch to
`MIXBAR_ENGINE=core`.

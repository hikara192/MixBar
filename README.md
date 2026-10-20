# MixBar

Per-app volume and mute in the macOS menu bar. Built on private Core Audio
process taps and one private aggregate device: no virtual audio driver, no
kext, no admin rights.

Full design, ADRs and fitness functions: **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## Status: real per-app control works

Real Core Audio is the default engine. Spike S1 validated the whole path on
live audio: process tap, private aggregate, IOProc, buffer layout
(interleaved stereo), and gain reaching the output exactly
(out/in = 1.000 → 0.500 → 0.000 → 1.000).

| Layer | State |
|---|---|
| `RenderCore` + slot table (RT mixing, ramps, clamp, peaks) | **real**, tested |
| `GraphOwner` + `Reconciler` (single writer, idempotent reconcile) | **real**, tested |
| `SettingsStore`, discovery, menu bar UI | **real**, tested |
| `CoreAudioSystem` — process taps, private aggregate, IOProc | **real**, S1-validated |
| `FakeAudioSystem` — synthetic buffers through the real render core | **real**, demo/CI engine |

## Using it

1. Play audio in an app (Music, Spotify, a browser tab, …).
2. Open MixBar from the menu bar: apps appear while they produce sound.
3. Move a slider. On the first tap macOS asks for **System Audio Recording**
   permission — allow it. From then on the slider actually changes that app's
   volume and the meter shows its real level.
4. Slider back to 100% releases the app: the tap is destroyed and playback is
   bit-perfect again.

Safety valve: if taps are created but deliver no audio for 6 s (the usual
signature of denied permission), MixBar removes them, leaves audio untouched,
and shows a "MixBar paused" banner with Settings / Retry.

Engine override: `MIXBAR_ENGINE=fake open build/MixBar.app` runs the UI on
synthetic audio with no permission prompt.

## Build and run

```bash
swift build
swift run MixBarApp            # fake engine; Dock icon (no bundle in dev)

Scripts/build-app.sh           # -> build/MixBar.app (LSUIElement, menu bar only)
Scripts/make-icon.sh           # regenerate AppResources/AppIcon.icns
open build/MixBar.app
```

Engine selection: `MIXBAR_ENGINE=core|fake` (default `core`).
`fake` runs the same UI and the same render core on synthetic buffers.

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

## Spikes

S1 is done: taps, aggregate, IOProc, buffer layout and gain are validated.
Still open (see [Spikes/README.md](Spikes/README.md)): S2 tap add/remove
mid-playback and buffer↔slot mapping under multiple taps, S3 permission
matrix and re-prompt behavior, S4 AirPods HFP format changes.

# Spikes (Week 0) — throwaway, run before any UI work (ARCHITECTURE.md §15)

Each spike is a small CLI in this folder, half a day timebox, hard pass/fail.
They validate the assumptions the walking skeleton was built on.

## S1 — tap + aggregate + IOProc end-to-end (highest priority)
- Tap one audible app (e.g. Spotify), gain 0.5, verify mute-when-read and
  auto-restore on exit.
- `kill -9` mid-mute: audio must return.
- Measure the rebuild flash window (budget <= 150 ms) and added latency
  (budget <= 15 ms) with a loopback.
- Reuse `CoreAudioSystem` from MixBarCore with MIXBAR_ENGINE=core.

## S2 — tap add/remove mid-playback
- Add/remove a tap while others play: mapping order vs slot order.
- Verify whether the aggregate's tap list is mutable post-creation (A1).
- Try two private aggregates sharing one output (fallback topology B, A2).

## S3 — TCC permission behavior
- Trigger, deny, confirm taps return silence without error (A3).
- Re-prompt after removing the entry in System Settings.
- Decide the onboarding copy and the "diagnose silence" flow.

## S4 — AirPods HFP
- Switch to HFP (mic active): output drops to 24 kHz mono.
- Observe tap vs aggregate format, choose the degrade path (A4, A5).

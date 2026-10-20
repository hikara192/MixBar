# MixBar

A small per-app volume mixer for the macOS menu bar.

Spotify too loud while a call is too quiet? MixBar gives every app its own
slider and mute button. It uses Core Audio process taps, so there is no virtual
audio driver, no kernel extension, and nothing that needs admin rights.

**Status:** early, but it actually works. Built and tested on Apple Silicon.

## Install

There is no notarized download yet, so you build it yourself. It takes about a
minute.

**You need:** macOS 14.2 or newer and Xcode Command Line Tools. If `swift`
is missing, run `xcode-select --install` first.

```bash
git clone https://github.com/hikara192/MixBar.git
cd MixBar
./Scripts/build-app.sh release
cp -R build/MixBar.app /Applications/
open /Applications/MixBar.app
```

Prefer a ZIP? [Download the source](https://github.com/hikara192/MixBar/archive/refs/heads/main.zip),
unzip it, then run the same commands inside the folder.

The build is ad-hoc signed. That is fine for personal use, but macOS treats
every rebuild as a new app, so you may have to allow audio capture again after
rebuilding. A properly signed and notarized release is still on the list.

### First run

1. Play something in any app.
2. Click the sliders icon in the menu bar.
3. Move a slider. macOS will ask for **System Audio Recording** — allow it.
4. That's it. The slider changes that app's volume, and the meter shows its
   real level.

If the slider moves but nothing changes, open System Settings → Privacy &
Security → **Screen & System Audio Recording**, make sure MixBar is enabled,
then hit **Retry** in the MixBar panel.

## Using it

Only apps that are currently making sound appear in the panel. Pause the music
and it disappears; start it again and it comes back.

- **Slider** — per-app volume from 0 to 100%.
- **Speaker button** — mute or unmute that app.
- **100%** — MixBar removes its tap completely. The app goes back to playing
  bit-perfect, with zero overhead.
- **Gear** — settings.

MixBar lives only in the menu bar. There is no Dock icon and no main window.

## Settings and shortcuts

Open settings with the gear in the panel, or press ⌘, while MixBar is active.

- **General** — interface language (System / English / Русский, switches
  immediately) and launch at login.
- **Audio** — current capture status, output device, a link to System Settings,
  Retry, and a reset that puts every app back to 100%.
- **Shortcuts** — global hotkeys, with a recorder and per-action switches.
- **About** — version and engine info.

Defaults:

- **⌥⌘M** — mute or unmute all apps.
- **⌥⌘R** — reset all volumes to 100%.

They work while MixBar is in the background and don't need Accessibility or
Input Monitoring permission.

## Good to know

- Up to 16 apps can be controlled at once.
- Apps that are not playing audio are not listed, by design.
- There is no boost above 100%, no equalizer, and no per-app output routing
  yet.
- A few pro-audio hosts (Logic, Ableton, Pro Tools, …) are excluded on purpose
  so MixBar doesn't fight them for the audio device.
- If your menu bar is full, macOS may hide the icon. Hold ⌘ and drag it
  somewhere visible.

## How it works

For every app you touch, MixBar creates a Core Audio process tap, feeds all
taps into one private aggregate device, and mixes them in a single real-time
callback. Apps at 100% are never tapped, so they keep their original path.

The full design, decisions and trade-offs are in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Development

```bash
swift build
swift test                 # 45 tests: render, reconciler, settings, localization, hotkeys
Scripts/check-deps.sh      # dependency and real-time purity checks

Scripts/build-app.sh       # builds build/MixBar.app
Scripts/make-icon.sh       # regenerates the app icon
```

Run the UI without Core Audio (synthetic audio, no permission prompt):

```bash
MIXBAR_ENGINE=fake open build/MixBar.app
```

## Privacy

MixBar never records audio and never sends it anywhere. Taps are mixed in
memory and played straight to your output device.

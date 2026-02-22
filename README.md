# Sentrio

A lightweight macOS menu bar app that automatically switches between audio devices based on your priority settings, with per-device volume memory.

[![Release](https://github.com/YunaBraska/Sentrio/actions/workflows/release.yml/badge.svg)](https://github.com/YunaBraska/Sentrio/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://developer.apple.com/macos/)

---

## What it does

- **Auto-switches** your default output and input device when devices connect/disconnect (and when you reorder priorities)
- **Priority order** — you decide which device wins (e.g. AirPods over built-in speakers, USB mic over headset mic)
- **Manual switching** — pick a device yourself when Auto is off
- **Per-device volume memory** — restores Output, Input, and Alert volumes when a device becomes active
- **Battery display** (when macOS reports it) — icons in the menu bar; full left/right/case details in Preferences
- **Smart default icons** for common device types (AirPods/HomePod/iPhone/monitors/headsets), plus per-device overrides
- **Custom device labels** — rename devices separately for Output vs Input
- **Device hygiene** — disable devices (kept) or permanently forget disconnected ones
- **Low‑battery warning** — menu bar icon turns into a red battery when the active output/input device drops below 15%
- **Backup & restore** — export/import settings as JSON (priorities, disabled devices, names/icons, volume memory)
- **Privacy-aware input meter** — optional live input level meter only while Preferences is open (macOS shows the mic indicator then)
- **Stats & easter eggs** — auto-switch counter, “milliseconds saved”, and a few silly messages

---

## Screenshots

![Menu bar panel](docs/screenshots/bar_menu.png)
![Preferences](docs/screenshots/preferences.png)

## Install

Sentrio runs on **macOS 13+** and lives in your **menu bar** (no Dock icon).

### Download (recommended)
1. Open [Releases](https://github.com/YunaBraska/Sentrio/releases)
2. Download the latest zip (named like `Sentrio-2026.02.0521048.zip`)
3. Unzip it and drag `Sentrio.app` into **Applications**
4. First launch: **right-click → Open** (Sentrio is not notarized yet)

If macOS still blocks it: **System Settings → Privacy & Security → Open Anyway**.

### Homebrew (easy updates)
If you already use Homebrew:

<details>
<summary>Show Homebrew commands</summary>

Homebrew installs Sentrio from GitHub Releases. If this fails, use the Download option above.

```bash
brew tap yunabraska/tap
brew install --cask sentrio
```

Update later:
```bash
brew upgrade --cask sentrio
```

Uninstall:
```bash
brew uninstall --cask sentrio
```

</details>

### Build from source (advanced)
See [Building from source](#building-from-source-advanced).

---

## Quick Start

1. Click the icon in your menu bar to open the control panel
2. Connect your audio devices — Sentrio discovers them automatically
3. Open **Preferences…** and drag devices into priority order (top = highest priority)
4. Make sure the **Auto** toggle is on (it is by default)
5. Done — device switching is now automatic

---

## Menu Bar Panel

Click the icon in your menu bar to open the panel.

| Element | What it does |
|---|---|
| **Auto** toggle | Master on/off for automatic device switching |
| **Output / Input / Alert** sliders | Adjust volumes right here |
| **Output devices** | Connected output devices, sorted by your priority |
| **Input devices** | Connected input devices, sorted by your priority |
| **Preferences…** | Open the full settings window |
| **Sound Settings…** | Open macOS System Sound Settings |
| **Quit** | Exit Sentrio |

### Device rows
- The **icon** shows the device type; the **#N badge** shows priority rank
- Battery indicators (when available) appear as small battery icons
- Click a device to switch to it — **only when Auto is off**
- Right‑click a device to **set a custom icon** or **disable** it
- For AirPods, there’s also a quick **Bluetooth Settings…** shortcut

> When **Auto-switch is ON**, clicking a device does nothing — the rules engine is in charge. Turn Auto off to select a device manually.

---

## Preferences

Open via **Preferences…** in the menu bar, or by launching the app again from Launchpad.

### Output tab / Input tab

| Control | What it does |
|---|---|
| **Drag a row** | Reorder priority (top = first choice) |
| **Click the device icon** | Choose a custom icon for that device |
| **− button** | Disable the device — excluded from auto-switching but stays in your known list |
| **Trash button** *(disconnected devices only)* | Permanently forget the device — reappears automatically if it reconnects |
| **Enable button** *(disabled section)* | Move the device back into the active priority list |

### General tab

| Setting | What it does |
|---|---|
| **Enable auto-switching** | Master on/off (same as the Auto toggle in the menu bar) |
| **Output / Input / Alert** sliders | Volume controls (handy when the menu bar icon is hidden) |
| **Hide menu bar icon** | Hides the icon; open Preferences by launching the app again from Launchpad |
| **Launch at login** | Start Sentrio automatically when you log in |
| **Show live input level meter (Preferences)** | Shows a live mic meter for the *active* input device while Preferences is open (macOS will show the mic indicator) |
| **Export / Import Settings** | Backup/restore priorities, disabled devices, custom names/icons, and volume memory |
| **Open Sound Settings…** | Jump straight to macOS System Sound Settings |
| **Clear Volume Memory** | Forget all saved volume levels for all devices |

---

## How priority works

Sentrio checks your priority list from top to bottom and activates whichever device is currently connected:

```
Output priority:
  1. AirPods Pro          ← connected → this one wins
  2. USB Audio Interface
  3. Built-in Speakers    ← always connected, ultimate fallback

Input priority:
  1. USB Microphone       ← connected → this one wins
  2. AirPods Pro
  3. Built-in Microphone  ← ultimate fallback
```

When AirPods disconnect, Sentrio instantly picks the next device on the list.

---

## Tips & Common Questions

**Why did music stop when I switched audio output?**
This is macOS behaviour, not a Sentrio bug. When the output device changes, some apps briefly pause to re-route audio to the new device. Spotify and Apple Music typically resume automatically within a second or two.

**My input level meter is frozen / always at zero**
The level meter only shows live input for the currently active (default) input device — all other devices show zero. If the active device's meter is stuck, restart Sentrio.

> **Note:** Monitoring input level for non-active devices is not supported: macOS only allows one microphone tap at a time. Similarly, output level metering (VU-style) is not available without the Screen Recording entitlement.

**I see "CADefaultDeviceAggregate" entries in my list**
Sentrio filters these automatically. They are macOS-internal virtual devices created by CoreAudio — you never selected them. If any appear, restart Sentrio.

**How do I open Preferences when the menu bar icon is hidden?**
Launch Sentrio again from Launchpad — instead of starting a second copy, it opens the Preferences window.

**AirPods appear as two devices**
This is normal. macOS creates:
- An **A2DP** entry (output only, high quality audio)
- An **HFP** entry (input + output, lower quality, used when the mic is active)

Add both to your list and place A2DP higher in output priority for best audio quality.

**Can I use aggregate devices (from Audio MIDI Setup)?**
Sentrio filters all aggregate device types to prevent phantom entries from macOS. Use macOS System Sound Settings to select aggregate devices manually.

---

## Building from source (advanced)

Requires **macOS 13+** and **Swift 5.9+**. Xcode is optional.

<details>
<summary>Terminal</summary>

```bash
git clone https://github.com/YunaBraska/Sentrio.git
cd Sentrio

# Run from source (debug)
swift build && .build/debug/Sentrio

# Build an app bundle (creates ./build/Sentrio.app)
chmod +x build.sh
./build.sh

# Install (optional)
cp -r ./build/Sentrio.app /Applications/

# Tests
swift test
```

</details>

<details>
<summary>Xcode</summary>

1. Run `open Package.swift`
2. Press **Run** (or **Product → Run**)

</details>

---

## Contributing

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE).

# Sentrio

A lightweight macOS menu bar app that keeps your audio routing and BusyLight behavior predictable.

[![Release](https://github.com/YunaBraska/Sentrio/actions/workflows/release.yml/badge.svg)](https://github.com/YunaBraska/Sentrio/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)](https://developer.apple.com/macos/)

**Home** | [Getting Started](docs/getting-started/README.md) | [Output + Input](docs/output-input/README.md) | [Settings + Backup](docs/settings-backup/README.md) | [Icons + Names](docs/icons-and-names/README.md) | [BusyLight](docs/busylight/README.md) | [BusyLight HTTP API](docs/busylight-http-api/README.md) | [BusyLight macOS Integrations](docs/busylight-macos-integrations/README.md) | [Troubleshooting](docs/troubleshooting/README.md)

---

## What Sentrio does

- Auto-switches output and input devices based on your priority order
- Uses explicit manual connect for Continuity/iPhone routes (shown as `Continuity` transport); failed manual connects fall back to next eligible priority
- Restores per-device Output, Input, and Alert volumes
- Supports custom device names and icons
- Shows battery info when macOS exposes it
- Adds BusyLight automation (rules/manual), HTTP control, and macOS integrations
- Runs a short BusyLight hello sequence on device detection, then applies rules/manual action
- Turns BusyLight off on app quit
- Shows per-rule BusyLight activity metrics (active total + rolling avg/day, avg/month, avg/year)
- Includes import/export for settings backup

## Install

### Download (recommended)
1. Open [Releases](https://github.com/YunaBraska/Sentrio/releases)
2. Download the latest zip (`Sentrio-<version>.zip`)
3. Drag `Sentrio.app` into **Applications**
4. First launch: right-click `Sentrio.app` -> **Open**

### Homebrew
```bash
brew tap yunabraska/tap
brew install --cask sentrio
```

## Build from source

```bash
swift build
swift test
./build.sh
open build/Sentrio.app
```

## Screenshots

![Menu bar panel](docs/screenshots/generated/bar_menu.png)
![Preferences - Output](docs/screenshots/generated/preferences_output.png)
![Preferences - Input](docs/screenshots/generated/preferences_input.png)
![Preferences - Busy Light](docs/screenshots/generated/preferences_busy_light.png)
![Preferences - General](docs/screenshots/generated/preferences_general.png)

## Regenerate Screenshots

```bash
bash scripts/generate-doc-screenshots.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - see [LICENSE](LICENSE).

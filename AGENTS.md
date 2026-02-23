# AGENTS.md

Working map for contributors and coding agents.

## Quick Start

```bash
swift build
swift test
bash scripts/check.sh
bash scripts/format.sh
```

## Repo Navigation

- `Package.swift`  
  SwiftPM manifest (`Sentrio` executable + `SentrioCore` library).

- `Sources/Sentrio/main.swift`  
  App entrypoint (`SentrioApp.main()` only).

- `Sources/SentrioCore/SentrioApp.swift`  
  Menu bar scene, app delegate, reopen handling.

- `Sources/SentrioCore/AppState.swift`  
  App composition root: `AppSettings`, `AudioManager`, `RulesEngine`, `BusyLightEngine`.

- `Sources/SentrioCore/AudioManager.swift`  
  CoreAudio device discovery, defaults, volume, battery snapshots.

- `Sources/SentrioCore/RulesEngine.swift`  
  Auto-switch logic for default audio devices.

- `Sources/SentrioCore/BusyLightEngine.swift`  
  BusyLight rule evaluation + output scheduling (solid/blink/pulse).

- `Sources/SentrioCore/BusyLightUSBClient.swift`  
  HID USB discovery + 64-byte report writes.

- `Sources/SentrioCore/BusyLightSignalsMonitor.swift`  
  Mic/camera/screen signals feeding BusyLight rules.

- `Sources/SentrioCore/PreferencesView.swift` and `Sources/SentrioCore/BusyLightPreferencesView.swift`  
  Settings UI.

- `Tests/SentrioTests/`  
  XCTest suite for `SentrioCore`.

## Runtime Data Flow

1. `main.swift` boots `SentrioApp`.
2. `SentrioApp` owns a single `AppState`.
3. `AppState` initializes `AudioManager`, `RulesEngine`, and `BusyLightEngine`.
4. `BusyLightSignalsMonitor` publishes signal state.
5. `BusyLightEngine` maps signal state + configured rules to a `BusyLightAction`.
6. `BusyLightUSBClient` sends HID reports to all matched BusyLight devices.

## BusyLight Troubleshooting

- Check device detection first in Preferences > BusyLight > Devices.
- Check live signal indicators in Preferences > BusyLight > Signals.
- Validate rule order and enabled state in Preferences > BusyLight > Rules.
- For lights that turn off by themselves in `solid` mode, use periodic keepalive writes (engine-level), not one-shot color sends.
- If blink/pulse looks wrong, verify `periodMilliseconds` and rule transitions.

## BusyLight Product Decisions (Current)

- Preferences/API parity is required: anything changeable via REST must be visible/editable in Preferences, and vice versa.
- Control semantics are fixed:
  - rules enabled = `auto`
  - rules disabled = `manual`
- REST action paths that set light state must switch control to `manual`; `/v1/busylight/auto` returns to rules.
- Logs are in-memory only, capped to the most recent 20 trigger events, and must include trigger origin (`REST`, rule name, startup, etc.).
- Keepalive writes are operational noise and must not be logged as trigger events.
- BusyLight tab visibility follows hardware presence: hide when no device, show on reconnect.
- BusyLight API port input is integer-only UX in Preferences; normalize to valid range in settings.
- Signal label uses **Alert sounds** (not guaranteed per-app media truth).

## Style + Testing

- Keep app wiring in `Sentrio`; keep logic in `SentrioCore`.
- Swift style: 4 spaces, `UpperCamelCase` types, `lowerCamelCase` members.
- Prefer deterministic tests and `UserDefaults(suiteName:)` for settings tests.
- Do not commit generated output from `.build/` or `build/`.
- Any new user-facing text requires localization updates across all supported `.lproj` files.

## Release Notes

- Commit format: `type: short summary` (`fix:`, `feat:`, `test:`, `docs:`).
- Release tags use UTC timestamp format `YYYY.MM.DDDHHMM`.

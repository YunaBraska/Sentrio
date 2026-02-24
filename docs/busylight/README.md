# BusyLight

[Home](../../README.md) | [Getting Started](../getting-started/README.md) | [Output + Input](../output-input/README.md) | [Settings + Backup](../settings-backup/README.md) | [Icons + Names](../icons-and-names/README.md) | **BusyLight** | [BusyLight HTTP API](../busylight-http-api/README.md) | [BusyLight macOS Integrations](../busylight-macos-integrations/README.md) | [Troubleshooting](../troubleshooting/README.md)

BusyLight controls a USB status light from app signals and rules.

## Setup

1. Connect a supported BusyLight USB device.
2. Open **Preferences -> BusyLight**.
3. Enable BusyLight.
4. Enable rules for automatic mode.
5. On first detection after app start, Sentrio runs a short hello sequence before normal rules/manual action apply.

## Control modes

- **Rules enabled**: automatic mode (`auto`)
- **Rules disabled**: manual mode (`manual`)

## Signals

Current signals include:
- Microphone
- Camera
- Screen recording
- Media activity

Signals are best-effort and depend on available macOS APIs.

## Rules

Each rule has:
- Name
- Conditions (AND/OR)
- Action (off, solid, blink, pulse, color, speed)
- Footer metrics:
  - Active total
  - Avg/day (rolling last 24h)
  - Avg/month (rolling last 30d, normalized per day)
  - Avg/year (rolling last 365d, normalized per day)
  - Display units are compact: `ms`, `s`, `min`, `h`, `d`, `mo`, `y`

First matching enabled rule wins.

## Logs

- In-memory only (last 20)
- Shows trigger source (REST, rule name, startup, integrations)
- Keepalive writes are not logged

## Lifecycle behavior

- On app quit, Sentrio sends an explicit `off` command to connected BusyLight devices.

## Related docs

- HTTP control: [BusyLight HTTP API](../busylight-http-api/README.md)
- URL/Shortcuts/AppleScript control: [BusyLight macOS Integrations](../busylight-macos-integrations/README.md)

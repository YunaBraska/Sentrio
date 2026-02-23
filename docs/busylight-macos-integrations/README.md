# BusyLight macOS Integrations

[Home](../../README.md) | [Getting Started](../getting-started/README.md) | [Output + Input](../output-input/README.md) | [Settings + Backup](../settings-backup/README.md) | [Icons + Names](../icons-and-names/README.md) | [BusyLight](../busylight/README.md) | [BusyLight HTTP API](../busylight-http-api/README.md) | **BusyLight macOS Integrations** | [Troubleshooting](../troubleshooting/README.md)

This page covers URL scheme, Shortcuts, Siri, and AppleScript usage.

## App Shortcuts (Siri / Shortcuts)

Available actions:
- Set Busy Light Automatic
- Set Busy Light Manual (color + mode + period)
- Set Busy Light Manual RGB (red + green + blue + mode + period)

How to use:
1. Open **Shortcuts** app.
2. Search for **Sentrio**.
3. Add a BusyLight action.
4. Run manually, with Siri, or inside a larger workflow.

## URL scheme

Scheme:

```text
sentrio://...
```

Examples:

```bash
open "sentrio://busylight/auto"
open "sentrio://busylight/red"
open "sentrio://busylight/red/pulse/234"
open "sentrio://busylight/hex/33cc99/pulse/234"
open "sentrio://busylight/rgb/12/34/56/blink/777"
open "sentrio://busylight/rules/off"
```

## AppleScript

Use URL commands from AppleScript:

```bash
osascript -e 'open location "sentrio://busylight/red"'
osascript -e 'open location "sentrio://busylight/hex/ff7f00"'
osascript -e 'open location "sentrio://busylight/auto"'
```

## Automation behavior

- URL/Shortcuts/manual actions switch BusyLight to **manual**.
- `.../auto` returns to rules/auto mode.
- This mirrors REST behavior.

## Failure testing

Try invalid commands and confirm no light change:

```bash
open "sentrio://busylight/red/fade"
open "sentrio://busylight/rules/maybe"
open "sentrio://nope/red"
```

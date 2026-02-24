# Troubleshooting

[Home](../../README.md) | [Getting Started](../getting-started/README.md) | [Output + Input](../output-input/README.md) | [Settings + Backup](../settings-backup/README.md) | [Icons + Names](../icons-and-names/README.md) | [BusyLight](../busylight/README.md) | [BusyLight HTTP API](../busylight-http-api/README.md) | [BusyLight macOS Integrations](../busylight-macos-integrations/README.md) | **Troubleshooting**

Quick fixes for common issues.

## Audio did not switch

- Confirm **Auto** is enabled.
- Check device priority order.
- Ensure device is not disabled.
- For Continuity/iPhone routes, use **Connect now** explicitly. These routes do not auto-connect in the background.

## Device appears but does not win

- Move it higher in priority.
- Re-check if another higher device is currently connected.
- If a manual Continuity connect attempt fails, Sentrio falls back to the next eligible priority automatically.

## BusyLight did not change

- Confirm USB device is listed in BusyLight tab.
- Check whether you are in auto or manual mode.
- Inspect BusyLight recent activity logs.

## URL/API command did nothing

- Verify path syntax.
- Check API port for HTTP calls.
- For URL commands, use `sentrio://busylight/...`.

## Preferences issue persists

- Export settings.
- Restart app.
- Re-import settings if needed.

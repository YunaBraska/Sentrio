# BusyLight HTTP API

[Home](../../README.md) | [Getting Started](../getting-started/README.md) | [Output + Input](../output-input/README.md) | [Settings + Backup](../settings-backup/README.md) | [Icons + Names](../icons-and-names/README.md) | [BusyLight](../busylight/README.md) | **BusyLight HTTP API** | [BusyLight macOS Integrations](../busylight-macos-integrations/README.md) | [Troubleshooting](../troubleshooting/README.md)

Control BusyLight from local scripts or automation tools.

## Enable API

- Open **Preferences -> BusyLight -> Remote API**
- Enable local REST API
- Pick your port

Base URL:

```text
http://127.0.0.1:<port>/v1/busylight
```

## Common endpoints

| Endpoint | Effect |
|---|---|
| `/auto` | Switch to rules/auto mode |
| `/red` | Manual solid red |
| `/red/pulse` | Manual pulse red |
| `/red/pulse/234` | Manual pulse red, 234 ms |
| `/hex/ff7f00` | Manual solid custom hex color |
| `/hex/33cc99/pulse/234` | Manual pulse custom hex color |
| `/rgb/255/127/0` | Manual solid custom RGB color |
| `/rgb/12/34/56/blink/777` | Manual blink custom RGB color |
| `/rules/on` | Enable rules (auto) |
| `/rules/off` | Disable rules (manual) |
| `/state` | Current state snapshot |
| `/logs` | Recent trigger events |

## Important behavior

- Action endpoints switch BusyLight to **manual**.
- `/auto` returns control to rules.
- API and Preferences always reflect the same state.

## Curl examples

```bash
curl -X POST http://127.0.0.1:47833/v1/busylight/auto
curl -X POST http://127.0.0.1:47833/v1/busylight/red
curl -X POST http://127.0.0.1:47833/v1/busylight/red/pulse/234
curl -X POST http://127.0.0.1:47833/v1/busylight/hex/33cc99/pulse/234
curl -X POST http://127.0.0.1:47833/v1/busylight/rgb/12/34/56/blink/777
```

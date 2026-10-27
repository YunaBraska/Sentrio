# App Store Review Notes

Use these notes as the starting point for the App Review Information field in App Store Connect. Replace the version and contact details there before submission.

## Reviewer Journey

1. Launch Sentrio. The app appears in the menu bar.
2. Open the menu bar panel to review current output and input devices, change their priority, or select a device directly.
3. Choose **Settings** to open the full settings window. The Output and Input tabs expose the same device priorities and per-device volume behavior as the menu bar panel.
4. Choose **macOS Sound** when system-owned sound settings are needed. The sandboxed App Store build does not modify another process's preferences.
5. The BusyLight tab appears only while compatible hardware is connected. Without hardware, the audio features remain fully available.

## Permissions and Data

- No account, login, subscription, analytics, advertising, or remote backend is used.
- Device priorities, custom names, icons, and volume memory remain on the Mac in local preferences.
- Microphone permission is requested only if the user enables the optional live input-level meter. Audio is analyzed in memory and is not recorded or transmitted.
- Camera access is used only to observe whether camera activity is present for optional BusyLight rules. Sentrio does not capture, store, or transmit video.
- Import and export operate only on a settings file explicitly selected by the user.
- The optional BusyLight HTTP API is disabled by default and listens on loopback only when enabled.

## Hardware-dependent Behavior

BusyLight automation requires supported USB hardware. The app intentionally hides that settings tab when no compatible device is present. Review of audio routing, settings, import/export, localization, and accessibility does not require external hardware.

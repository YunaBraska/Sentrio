# ADR-0002: Separate Mac App Store Distribution

- Status: Accepted
- Date: 2026-10-27

## Context

Sentrio has an established direct-distribution build with Sparkle updates. Mac App Store distribution requires App Sandbox, Store-managed updates, a privacy manifest, and App Store signing. The app's switching, BusyLight, settings, URL, and App Intent behavior must remain one product rather than diverging by channel.

The direct build also uses `system_profiler` as one optional source of Bluetooth metadata. A sandboxed app cannot launch that system executable.

## Decision

1. Keep one source tree and one set of user-facing behavior.
2. Select distribution with `SENTRIO_DISTRIBUTION=direct|app-store`. Direct remains the default.
3. Compile the App Store variant without Sparkle. Updates are owned by the Mac App Store.
4. Sign the App Store variant with `scripts/Sentrio-AppStore.entitlements`, including sandbox access required for microphone and camera activity monitoring, supported USB and Bluetooth devices, the optional local REST server, and user-selected settings files.
5. Include `PrivacyInfo.xcprivacy` in both distribution variants and declare the approved `UserDefaults` required-reason use.
6. Do not launch `system_profiler` in the App Store build. Preserve battery reporting through the existing in-process IOPowerSources, CoreAudio, and IOKit sources. This affects optional Bluetooth metadata only, not routing or switching.
7. Keep Developer ID notarization, Sparkle, ZIP, DMG, and appcast generation exclusive to direct distribution. Keep App Store package signing exclusive to the App Store path.
8. Keep system alert-volume control in direct builds only. App Sandbox cannot modify another process's preferences, so the App Store build links to macOS Sound instead of presenting a control that cannot work.

## Consequences

- Audio routing, priority, volume memory, BusyLight rules, local REST behavior, settings import/export, URL actions, and App Intents continue to share their implementations.
- Distribution-specific code is limited to packaging, updater inclusion, sandbox-safe Bluetooth enrichment, and signing.
- Final App Store submission still requires Apple distribution credentials, an App Store Connect record, metadata, screenshots, and review in Apple's systems.

# Sentrio — Development Plan

A macOS 13+ menu bar app that watches audio devices and enforces input/output
priority rules with per-device volume memory.

---

## Progress Checklist

### Phase 1 — Project Setup  ✅ COMPLETE
- [x] Create folder `/Users/yuna/projects/Sentrio/`
- [x] Write `PLAN.md` (this file)
- [x] Write `Package.swift`

### Phase 2 — Core Models & Audio Engine  ✅ COMPLETE
- [x] `Sources/Sentrio/AudioDevice.swift`       — Device model (id, uid, name, hasInput, hasOutput)
- [x] `Sources/Sentrio/AppSettings.swift`       — UserDefaults-backed settings (priority lists, volume memory, knownDevices)
- [x] `Sources/Sentrio/AppState.swift`          — Top-level observable state container
- [x] `Sources/Sentrio/AudioManager.swift`      — CoreAudio wrapper (enumerate, monitor, get/set defaults + volume)

### Phase 3 — Rules Engine  ✅ COMPLETE
- [x] `Sources/Sentrio/RulesEngine.swift`       — Priority logic: on device change, apply highest-priority connected device per role

### Phase 4 — UI  ✅ COMPLETE
- [x] `Sources/Sentrio/SentrioApp.swift`    — @main entry point, MenuBarExtra
- [x] `Sources/Sentrio/MenuBarView.swift`       — Popover with current devices, volume sliders, auto-mode toggle
- [x] `Sources/Sentrio/PreferencesView.swift`   — Drag-to-reorder priority lists, launch-at-login

### Phase 5 — Build & Distribution  ✅ COMPLETE
- [x] `build.sh`                                    — Creates a signed or unsigned .app bundle

### Phase 5b — Feature additions  ✅ COMPLETE
- [x] Bug fix: RulesEngine now re-applies rules when priority list changes (Combine subscription)
- [x] Bug fix: Auto-mode default is true (confirmed)
- [x] Menu bar device list sorted by priority order
- [x] Transport type icon on every device (USB, Bluetooth, AirPlay, Thunderbolt, HDMI, Built-in…)
- [x] Live input level meter (AVAudioEngine tap + RMS, shown in the Input section header)
- [x] "Device is active" indicator (green dot) for non-default active devices
- [x] Custom menu bar icon picker (12 curated SF Symbols)
- [x] Hide menu bar icon option (shows Dock icon; click to re-open Preferences)
- [x] Library split: SentrioCore (library) + Sentrio (thin executable)
- [x] 37 unit tests: AppSettingsTests (20), AudioDeviceTests (8), RulesEngineTests (9)

### Phase 6 — Bug fixes & polish  ✅ COMPLETE
- [x] No Dock icon ever — always `.accessory` activation policy; Launchpad click opens Preferences
- [x] Bluetooth SF Symbol "bluetooth" (restricted/empty) replaced with "wave.3.right"
- [x] Icon options cleaned up: removed mic.fill + bluetooth, added earbuds + speaker.wave.3
- [x] Delete button (trash) on disconnected/disabled devices — `AppSettings.deleteDevice(uid:)`
- [x] Frozen level meter fix — reset inputLevel=0 and restart AVAudioEngine tap in the defaultInput CoreAudio listener
- [x] Removed `audio.isDeviceActive()` from views (called CoreAudio synchronously on every render)
- [x] CADefaultDeviceAggregate filtering: now filters ALL aggregate transport types unconditionally
- [x] Menu bar compact: removed per-device volume slider, reduced padding on all rows
- [x] Manual device click disabled (no-op + tooltip) when Auto-switch is on
- [x] 54 unit tests, 0 failures; zero release-build warnings
- [x] README.md written for end users

### Phase 7 — Future / Nice-to-have  ⬜ NOT STARTED
- [ ] Custom app icon (design a waveform + shield logo)
- [ ] Import/export of priority rules as JSON
- [ ] Code-signing & notarisation for Gatekeeper-clean distribution
- [ ] Real-time output level meter (requires CoreAudio IOProc tap)

---

## Architecture Overview

```
SentrioApp (@main)
  └── AppState (ObservableObject, @StateObject)
        ├── AppSettings     — persists to UserDefaults
        ├── AudioManager    — wraps CoreAudio, publishes device lists + defaults
        └── RulesEngine     — listens to AudioManager, reads AppSettings, applies priority
```

### Data Flow

1. `AudioManager` registers CoreAudio property listeners for:
   - `kAudioHardwarePropertyDevices` (connect/disconnect)
   - `kAudioHardwarePropertyDefaultInputDevice` (external changes)
   - `kAudioHardwarePropertyDefaultOutputDevice`

2. On device change → posts `.audioDevicesChanged` notification.

3. `RulesEngine` receives notification → runs `applyRules()`:
   - For output: walk `settings.outputPriority` UIDs, pick first that is connected
   - For input:  walk `settings.inputPriority`  UIDs, pick first that is connected
   - Before switching: save current device volume → `settings.volumeMemory`
   - After  switching: restore saved volume for new device (0.5 s delay)

4. User can also **manually** click a device in the menu → sets default immediately
   and restores its saved volume.

### Key Settings (UserDefaults)

| Key              | Type                       | Meaning                                    |
|------------------|----------------------------|--------------------------------------------|
| outputPriority   | [String]                   | Ordered array of device UIDs               |
| inputPriority    | [String]                   | Ordered array of device UIDs               |
| volumeMemory     | [String:[String:Float]]    | uid → {"output": 0.8, "input": 0.5}        |
| knownDevices     | [String:String]            | uid → name (for disconnected devices)      |
| isAutoMode       | Bool                       | Whether rules engine is active             |

### CoreAudio Notes

- Device UIDs (`kAudioDevicePropertyDeviceUID`) persist across reboots — safe for storage.
- Device IDs (`AudioDeviceID`) are session-local — do NOT persist.
- Volume via `kAudioDevicePropertyVolumeScalar` on element 0 (master), fall back to channel 1.
- AirPods appear as two CoreAudio devices: HFP (input+output, lower quality) and
  A2DP (output only, high quality). Priority list lets user pick which UID to prefer.
- `AudioObjectAddPropertyListenerBlock` used throughout (Swift-friendly, no Unmanaged needed).

---

## Build Status

```
swift build          → Build complete (debug)
swift build -c release → Build complete (release, zero warnings)
```

## Build & Run

### Development (quickest)
```bash
cd /Users/yuna/projects/Sentrio

# Open in Xcode (recommended — full debugger, live previews)
open Package.swift

# Or build + run from terminal
swift build && .build/debug/Sentrio
```

### Distribution (.app bundle)
```bash
cd /Users/yuna/projects/Sentrio
chmod +x build.sh
./build.sh
# Produces: ./build/Sentrio.app
open ./build/Sentrio.app
cp -r ./build/Sentrio.app /Applications/
```

**Note:** On first run macOS may show a Gatekeeper warning because the app is
unsigned. Right-click → Open → Open to allow it. For clean distribution, code-sign
and notarise via Xcode Organiser (Phase 6).

### Xcode Archive (cleanest for sharing)
1. `open Package.swift` in Xcode
2. Product → Archive
3. Distribute App → Copy App
4. Share the resulting `Sentrio.app`

---

## Resuming After Token Limit

If context is lost, pick up by:
1. Check boxes above to see what's done.
2. Read each completed file to re-establish context.
3. Continue with the next unchecked item.
4. The architecture section above has everything needed to continue.

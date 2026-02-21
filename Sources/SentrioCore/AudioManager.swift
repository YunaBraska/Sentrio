import CoreAudio
import AVFoundation
import Foundation
import IOKit
import IOKit.ps

extension Notification.Name {
    static let audioDevicesChanged = Notification.Name("Sentrio.audioDevicesChanged")
}

final class AudioManager: ObservableObject {

    // MARK: – Published

    @Published var inputDevices:  [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var defaultInput:  AudioDevice?
    @Published var defaultOutput: AudioDevice?

    /// Live RMS input level [0…1] for the current default input device
    @Published var inputLevel: Float = 0

    /// Master output volume [0…1] of the current default output device
    @Published var outputVolume: Float = 0.5
    /// Mic gain [0…1] of the current default input device
    @Published var inputVolume: Float = 0.5
    /// System alert/beep volume [0…1]
    @Published var alertVolume: Float = 0.75

    // MARK: – Private

    private var listeners: [Any] = []
    private var audioEngine: AVAudioEngine?

    // MARK: – Init

    init() {
        refreshDevices()
        addListeners()
        startInputLevelMonitor()
        startVolumePolling()
        alertVolume = Self.readAlertVolume()
    }

    // MARK: – Device refresh

    func refreshDevices() {
        let all        = fetchAllDevices()                        // includes battery from power sources
        let defaultIn  = resolveDefaultID(input: true)
        let defaultOut = resolveDefaultID(input: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.inputDevices  = all.filter(\.hasInput)
            self.outputDevices = all.filter(\.hasOutput)
            // Reuse the already-created device objects so battery data is preserved
            self.defaultInput  = all.first { $0.id == defaultIn  }
            self.defaultOutput = all.first { $0.id == defaultOut }
            self.refreshVolumes()
        }
    }

    func refreshVolumes() {
        if let out = defaultOutput { outputVolume = volume(for: out, isOutput: true) ?? outputVolume }
        if let inp = defaultInput  { inputVolume  = volume(for: inp, isOutput: false) ?? inputVolume }
        alertVolume = Self.readAlertVolume()
    }

    // MARK: – Set default device

    func setDefault(_ device: AudioDevice, isInput: Bool) {
        let selector = isInput
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var devID = device.id
        AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &devID)
        DispatchQueue.main.async { [weak self] in
            if isInput { self?.defaultInput  = device }
            else       { self?.defaultOutput = device }
            self?.refreshVolumes()
        }
        // Level monitor restart is handled by the defaultInputDevice listener below
    }

    // MARK: – Volume

    func volume(for device: AudioDevice, isOutput: Bool) -> Float? {
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope, mElement: element)
            guard AudioObjectHasProperty(device.id, &addr) else { continue }
            var vol: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &vol) == noErr else { continue }
            return vol
        }
        return nil
    }

    func setVolume(_ volume: Float, for device: AudioDevice, isOutput: Bool) {
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope, mElement: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device.id, &addr) {
            var vol = volume
            AudioObjectSetPropertyData(device.id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            if isOutput { DispatchQueue.main.async { self.outputVolume = volume } }
            else        { DispatchQueue.main.async { self.inputVolume  = volume } }
            return
        }
        for ch: UInt32 in [1, 2] {
            addr.mElement = ch
            if AudioObjectHasProperty(device.id, &addr) {
                var vol = volume
                AudioObjectSetPropertyData(device.id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            }
        }
        if isOutput { DispatchQueue.main.async { self.outputVolume = volume } }
        else        { DispatchQueue.main.async { self.inputVolume  = volume } }
    }

    // MARK: – Alert volume

    static func readAlertVolume() -> Float {
        UserDefaults(suiteName: "com.apple.systemsound")?
            .float(forKey: "com.apple.sound.beep.volume") ?? 0.75
    }

    func setAlertVolume(_ volume: Float) {
        alertVolume = volume
        let ud = UserDefaults(suiteName: "com.apple.systemsound")
        ud?.set(volume, forKey: "com.apple.sound.beep.volume")
        ud?.synchronize()
    }

    // MARK: – Device activity

    func isDeviceActive(_ device: AudioDevice) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: – Volume polling (real-time sync with keyboard / system changes)

    /// Polls volumes every 1.5 s and updates published properties only when values actually changed.
    ///
    /// A true CoreAudio property listener on the device volume would be more efficient but requires
    /// per-device listener setup and teardown on every device switch — the polling approach is simpler
    /// and 1.5 s latency is imperceptible for a volume slider.
    ///
    /// Output level metering (VU meter) is NOT available for other apps' audio without the
    /// Screen Recording entitlement. The mini-bar for output shows playback activity only.
    ///
    /// Input level for non-active devices is NOT available: AVAudioEngine supports one input tap
    /// at a time (the current default input device). Monitoring multiple input devices simultaneously
    /// would require per-device CoreAudio IOProc setup and could conflict with other recording apps.
    private func startVolumePolling() {
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.pollVolumes()
        }
        // Refresh device list (including battery levels) every 60 s.
        // Batteries on Bluetooth devices can change while connected without
        // triggering a device-list change event, so a periodic refresh is needed.
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshDevices()
        }
    }

    private func pollVolumes() {
        let newOut   = defaultOutput.flatMap { volume(for: $0, isOutput: true)  } ?? outputVolume
        let newIn    = defaultInput.flatMap  { volume(for: $0, isOutput: false) } ?? inputVolume
        let newAlert = Self.readAlertVolume()
        if abs(newOut   - outputVolume) > 0.005 { outputVolume = newOut   }
        if abs(newIn    - inputVolume)  > 0.005 { inputVolume  = newIn    }
        if abs(newAlert - alertVolume)  > 0.005 { alertVolume  = newAlert }
    }

    // MARK: – Input level (AVAudioEngine)

    private func startInputLevelMonitor() {
        stopInputLevelMonitor()
        let engine = AVAudioEngine()
        let input  = engine.inputNode
        // Guard: no input channels means no active input device — nothing to tap.
        guard input.outputFormat(forBus: 0).channelCount > 0 else { return }
        // Pass nil so AVAudioEngine picks its own compatible format.
        // Passing the hardware format explicitly crashes when the device reports a
        // deinterleaved layout after a switch (AVAudioEngine rejects it as a mismatch).
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let ch = Int(buffer.format.channelCount)
            let fr = Int(buffer.frameLength)
            var sum: Float = 0
            for c in 0..<ch { let p = data[c]; for f in 0..<fr { sum += p[f] * p[f] } }
            let rms   = sqrt(sum / Float(ch * max(fr, 1)))
            let level = min(rms * 6, 1.0)
            DispatchQueue.main.async { self?.inputLevel = level }
        }
        do { try engine.start(); audioEngine = engine } catch {}
    }

    private func stopInputLevelMonitor() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputLevel = 0
    }

    // MARK: – CoreAudio enumeration

    private func fetchAllDevices() -> [AudioDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr
        else { return [] }
        let powerSources = fetchPowerSourceBatteries()
        return ids.compactMap { makeDevice(from: $0, powerSources: powerSources) }
    }

    private func makeDevice(from id: AudioDeviceID, powerSources: [String: Float] = [:]) -> AudioDevice? {
        guard
            let uid  = stringProperty(id, kAudioDevicePropertyDeviceUID),
            let name = stringProperty(id, kAudioDevicePropertyDeviceNameCFString)
        else { return nil }

        let transport = fetchTransportType(id)

        // Filter all aggregate devices — this removes macOS-internal auto-aggregates
        // (CADefaultDeviceAggregate-*, created and destroyed on every device change)
        // as well as user-created aggregate devices from Audio MIDI Setup.
        if transport == .aggregate { return nil }

        let hasIn  = hasStreams(id, scope: kAudioObjectPropertyScopeInput)
        let hasOut = hasStreams(id, scope: kAudioObjectPropertyScopeOutput)
        guard hasIn || hasOut else { return nil }

        let (iconBase, isApple) = fetchIconInfo(id)
        // Battery resolution order:
        //   1. CoreAudio 'batt' — works for some USB headsets and virtual devices
        //   2. IOPowerSources name-match — the same API used by macOS Control Center;
        //      covers AirPods, Beats, BT keyboards/mice; works even for renamed devices
        //   3. IOKit HID service scan — fallback for third-party BT HID headsets
        let battery = fetchBatteryLevel(id)
            ?? batteryFromPowerSources(name, powerSources)
            ?? (transport == .bluetooth ? fetchBluetoothBatteryViaIOKit(uid: uid) : nil)
        return AudioDevice(id: id, uid: uid, name: name,
                           hasInput: hasIn, hasOutput: hasOut,
                           transportType: transport,
                           iconBaseName:  iconBase,
                           isAppleMade:   isApple,
                           batteryLevel:  battery)
    }

    /// kAudioDevicePropertyIcon → (lowercased filename stem, isAppleMade).
    ///
    /// "isAppleMade" is derived from the icon URL path: Apple device icons live inside
    /// Apple-branded framework bundles (CoreBluetooth, CoreAudio, etc.), so checking
    /// the path for "apple" is reliable and requires no extra CoreAudio property reads.
    ///
    /// Note: kAudioDevicePropertyDeviceManufacturer was attempted but is unsafe — on macOS 26
    /// it writes raw C-string bytes directly into the buffer rather than a CFString pointer,
    /// causing a "bad pointer dereference" crash when the bytes are misinterpreted as an address.
    private func fetchIconInfo(_ id: AudioDeviceID) -> (baseName: String?, isAppleMade: Bool) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIcon,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var urlRef: Unmanaged<CFURL>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        let status = withUnsafeMutablePointer(to: &urlRef) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
                AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw)
            }
        }
        guard status == noErr, let url = urlRef?.takeRetainedValue() as URL? else {
            return (nil, false)
        }
        let baseName  = url.deletingPathExtension().lastPathComponent.lowercased()
        let isApple   = url.path.lowercased().contains("apple")
        return (baseName, isApple)
    }

    /// kAudioDevicePropertyBatteryLevel ('batt') — [0…1], nil if not reported.
    /// Tries Global, Output, and Input scopes; uses AudioObjectHasProperty before each read.
    private func fetchBatteryLevel(_ id: AudioDeviceID) -> Float? {
        let kBatteryLevel: AudioObjectPropertySelector = 0x62617474  // 'batt'
        let scopes: [AudioObjectPropertyScope] = [
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyScopeInput,
        ]
        for scope in scopes {
            var addr = AudioObjectPropertyAddress(
                mSelector: kBatteryLevel, mScope: scope,
                mElement:  kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var level: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &level) == noErr,
                  level >= 0, level <= 1 else { continue }
            return level
        }
        return nil
    }

    // MARK: – IOPowerSources battery (dynamic name-based matching)

    /// Reads all external power sources via the public IOPowerSources API — the same source
    /// that macOS Control Center uses to show AirPods battery.
    ///
    /// Returns a map of lowercased device name → battery fraction [0…1].
    /// Devices with multiple cells (AirPods left / right / case) are merged by keeping
    /// the minimum so we show the most-critical value.
    private func fetchPowerSourceBatteries() -> [String: Float] {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return [:] }

        var result: [String: Float] = [:]
        for source in list {
            guard
                let desc    = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                let present = desc["Is Present"]       as? Bool, present,
                let name    = desc["Name"]              as? String, !name.isEmpty,
                let current = desc["Current Capacity"] as? Int,
                let maxCap  = desc["Max Capacity"]     as? Int, maxCap > 0
            else { continue }
            let level = Float(current).clamped(to: 0...Float(maxCap)) / Float(maxCap)
            let key   = name.lowercased()
            result[key] = min(result[key] ?? level, level)  // keep the lowest cell
        }
        return result
    }

    /// Matches a CoreAudio device name against the IOPowerSources map.
    /// Tries exact match first, then substring containment in either direction —
    /// handles renamed AirPods (e.g. "[Yuna] ClayWave" ↔ original BT name).
    private func batteryFromPowerSources(_ deviceName: String, _ ps: [String: Float]) -> Float? {
        guard !ps.isEmpty else { return nil }
        let lower = deviceName.lowercased()
        if let exact = ps[lower] { return exact }
        return ps.first { k, _ in lower.contains(k) || k.contains(lower) }?.value
    }

    // MARK: – IOKit HID battery (last-resort fallback for third-party BT HID headsets)

    /// For Bluetooth devices whose name doesn't match any IOPowerSource entry,
    /// scan the IOKit HID service tree for a matching device using the MAC address
    /// embedded in the UID and read BatteryPercent from its registry entry.
    ///
    /// UID format for BT devices: "2C-32-6A-E9-E9-65:output"
    private func fetchBluetoothBatteryViaIOKit(uid: String) -> Float? {
        let parts = uid.components(separatedBy: ":")
        guard parts.count >= 2 else { return nil }
        let macWithDashes = parts[0]
        guard macWithDashes.count == 17,
              macWithDashes.filter({ $0 == "-" }).count == 5 else { return nil }

        let macDash  = macWithDashes.lowercased()
        let macColon = macDash.replacingOccurrences(of: "-", with: ":")

        for serviceClass in ["IOBluetoothHIDDriver", "AppleBluetoothHIDDriver"] {
            if let level = ioKitHIDBattery(service: serviceClass,
                                           macDash: macDash, macColon: macColon) {
                return level
            }
        }
        return nil
    }

    private func ioKitHIDBattery(service: String, macDash: String, macColon: String) -> Float? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(service), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            var propRef: Unmanaged<CFMutableDictionary>? = nil
            guard IORegistryEntryCreateCFProperties(
                    entry, &propRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = propRef?.takeRetainedValue() as? [String: Any] else { continue }

            let strings = dict.values.compactMap { $0 as? String }.map { $0.lowercased() }
            guard strings.contains(where: { $0.contains(macDash) || $0.contains(macColon) })
            else { continue }

            if let pct = dict["BatteryPercent"]    as? Int { return Float(pct).clamped(to: 0...100) / 100 }
            if let pct = dict["BatteryPercentRaw"] as? Int { return Float(pct).clamped(to: 0...100) / 100 }
            if let lvl = dict["BatteryLevel"]      as? Int { return Float(lvl).clamped(to: 0...100) / 100 }
        }
        return nil
    }

    private func fetchTransportType(_ id: AudioDeviceID) -> AudioDevice.TransportType {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope:    kAudioObjectPropertyScopeGlobal,
            mElement:  kAudioObjectPropertyElementMain)
        var raw: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &raw) == noErr else { return .unknown }
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn:                               return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB:                                   return .usb
        case kAudioDeviceTransportTypeAirPlay:                               return .airPlay
        case kAudioDeviceTransportTypeThunderbolt:                           return .thunderbolt
        case kAudioDeviceTransportTypeHDMI:                                  return .hdmi
        case kAudioDeviceTransportTypeDisplayPort:                           return .displayPort
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .aggregate
        case kAudioDeviceTransportTypeVirtual:                               return .virtual
        case kAudioDeviceTransportTypePCI:                                   return .pci
        default:                                                             return .unknown
        }
    }

    /// Returns the CoreAudio ID of the current system default device, or kAudioObjectUnknown.
    private func resolveDefaultID(input: Bool) -> AudioDeviceID {
        let selector = input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var devID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID) == noErr
        else { return kAudioObjectUnknown }
        return devID
    }

    /// Used by listeners when only the default device changes (not the full list).
    /// Prefers the existing device object from the published arrays (battery already set),
    /// falling back to a fresh makeDevice call when the device isn't in the list yet.
    private func fetchDefaultDevice(input: Bool) -> AudioDevice? {
        let devID = resolveDefaultID(input: input)
        guard devID != kAudioObjectUnknown else { return nil }
        let existing = (input ? inputDevices : outputDevices).first { $0.id == devID }
        if let existing { return existing }
        // Device connected and became default before the device-list listener fired
        let powerSources = fetchPowerSourceBatteries()
        return makeDevice(from: devID, powerSources: powerSources)
    }

    // MARK: – Helpers

    private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfRef: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &cfRef) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: Int(size)) { raw in
                AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw)
            }
        }
        guard status == noErr, let ref = cfRef else { return nil }
        return ref.takeRetainedValue() as String
    }

    private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    // MARK: – Listeners

    private func addListeners() {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        addListener(on: sys, selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.refreshDevices()
            NotificationCenter.default.post(name: .audioDevicesChanged, object: self)
        }
        addListener(on: sys, selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            guard let self else { return }
            self.defaultOutput = self.fetchDefaultDevice(input: false)
            self.refreshVolumes()
        }
        addListener(on: sys, selector: kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            guard let self else { return }
            self.inputLevel = 0                                     // reset immediately
            self.defaultInput = self.fetchDefaultDevice(input: true)
            self.refreshVolumes()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startInputLevelMonitor()                       // reattach tap to new device
            }
        }
    }

    private func addListener(
        on objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        handler: @escaping () -> Void
    ) {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in DispatchQueue.main.async { handler() } }
        AudioObjectAddPropertyListenerBlock(objectID, &addr, .main, block)
        listeners.append(block)
    }
}

// MARK: – Numeric helpers

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

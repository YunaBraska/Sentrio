import AVFoundation
import CoreAudio
import Foundation
import IOKit
import IOKit.ps

extension Notification.Name {
    static let audioDevicesChanged = Notification.Name("Sentrio.audioDevicesChanged")
}

final class AudioManager: ObservableObject {
    // MARK: – Published

    @Published var inputDevices: [AudioDevice] = []
    @Published var outputDevices: [AudioDevice] = []
    @Published var defaultInput: AudioDevice?
    @Published var defaultOutput: AudioDevice?

    /// Live RMS input level [0…1] for the current default input device
    @Published var inputLevel: Float = 0

    /// Master output volume [0…1] of the current default output device
    @Published var outputVolume: Float = 0.5
    /// Mute state of the current default output device (best effort; false when unavailable)
    @Published var isOutputMuted = false
    /// Mic gain [0…1] of the current default input device
    @Published var inputVolume: Float = 0.5
    /// System alert/beep volume [0…1]
    @Published var alertVolume: Float = 0.75

    // MARK: – Private

    private var listeners: [Any] = []
    private var volumeListeners: [ListenerToken] = []
    private var volumeListenerOutputID: AudioDeviceID = kAudioObjectUnknown
    private var volumeListenerInputID: AudioDeviceID = kAudioObjectUnknown
    private var audioEngine: AVAudioEngine?
    private var isInputLevelMonitoringEnabled = false
    private var inputLevelMonitoringDemandTokens: Set<String> = []
    private let coreAudioWorkQueue = DispatchQueue(
        label: "Sentrio.AudioManager.CoreAudioWork",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private var bluetoothBatterySnapshot = BluetoothBatterySnapshot()
    private var bluetoothBatterySnapshotLastRefreshedAt: Date?
    private var bluetoothBatterySnapshotRefreshInFlight = false
    private var unavailableUntilByUID: [String: Date] = [:]
    private let unavailableUntilByUIDLock = NSLock()
    private let unavailableCooldownSeconds: TimeInterval = 30

    // MARK: – Init

    init() {
        refreshDevices()
        addListeners()
        startPeriodicRefresh()
        alertVolume = Self.readAlertVolume()
        refreshBluetoothBatterySnapshotIfNeeded(force: true)
    }

    // MARK: – Input level (microphone monitor)

    func setInputLevelMonitoringEnabled(_ enabled: Bool) {
        guard enabled != isInputLevelMonitoringEnabled else { return }
        isInputLevelMonitoringEnabled = enabled
        if enabled {
            if let uid = defaultInput?.uid, isTemporarilyUnavailable(uid) {
                inputLevel = 0
                return
            }
            startInputLevelMonitor()
        } else {
            stopInputLevelMonitor()
        }
    }

    func setInputLevelMonitoringDemand(_ demanded: Bool, token: String) {
        if demanded { inputLevelMonitoringDemandTokens.insert(token) }
        else { inputLevelMonitoringDemandTokens.remove(token) }
        setInputLevelMonitoringEnabled(!inputLevelMonitoringDemandTokens.isEmpty)
    }

    // MARK: – Device refresh

    func refreshDevices() {
        let all = fetchAllDevices() // includes battery from power sources
        let defaultIn = resolveDefaultID(input: true)
        let defaultOut = resolveDefaultID(input: false)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            inputDevices = all.filter(\.hasInput)
            outputDevices = all.filter(\.hasOutput)
            // Reuse the already-created device objects so battery data is preserved
            defaultInput = all.first { $0.id == defaultIn }
            defaultOutput = all.first { $0.id == defaultOut }
            refreshVolumes()
            rebuildVolumeListenersIfNeeded()
        }
    }

    func refreshVolumes() {
        let out = defaultOutput
        let inp = defaultInput
        let currentOutVolume = outputVolume
        let currentOutMuted = isOutputMuted
        let currentInVolume = inputVolume

        coreAudioWorkQueue.async { [weak self] in
            guard let self else { return }
            let outVol = out.flatMap { self.volume(for: $0, isOutput: true) }
            let outMuted = out.flatMap { self.mute(for: $0, isOutput: true) }
            let inVol = inp.flatMap { self.volume(for: $0, isOutput: false) }
            let alertVol = Self.readAlertVolume()

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let out, defaultOutput?.id == out.id {
                    outputVolume = outVol ?? currentOutVolume
                    isOutputMuted = outMuted ?? currentOutMuted
                }
                if let inp, defaultInput?.id == inp.id {
                    inputVolume = inVol ?? currentInVolume
                }
                alertVolume = alertVol
            }
        }
    }

    // MARK: – Set default device

    func setDefault(
        _ device: AudioDevice,
        isInput: Bool,
        completion: ((Bool) -> Void)? = nil
    ) {
        coreAudioWorkQueue.async { [weak self] in
            guard let self else { return }

            let selector = isInput
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice
            var addr = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var devID = device.id
            let status = AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &addr, 0, nil,
                UInt32(MemoryLayout<AudioDeviceID>.size), &devID
            )

            // Do not optimistically mutate defaultInput/defaultOutput on the main thread.
            // Some devices (notably Continuity iPhone) can fail or time out; forcing UI state
            // early makes the app look "stuck" with a non-active default device.
            let resolvedID = resolveDefaultID(input: isInput)
            let didSucceed = Self.didDefaultSwitchSucceed(
                status: status,
                resolvedDefaultID: resolvedID,
                targetID: device.id
            )
            if !didSucceed {
                markDeviceTemporarilyUnavailable(device.uid)
                NSLog(
                    "Sentrio: failed to set default %@ device to %@ (status=%d, resolvedID=%u)",
                    isInput ? "input" : "output",
                    device.uid,
                    Int32(status),
                    resolvedID
                )
            } else {
                clearTemporarilyUnavailable(device.uid)
            }

            DispatchQueue.main.async {
                completion?(didSucceed)
            }
            refreshDevices()
        }
        // Level monitor restart is handled by the defaultInputDevice listener.
    }

    // MARK: – Volume

    func volume(for device: AudioDevice, isOutput: Bool) -> Float? {
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: scope, mElement: element
            )
            guard AudioObjectHasProperty(device.id, &addr) else { continue }
            var vol: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &vol) == noErr else { continue }
            return vol
        }
        return nil
    }

    func mute(for device: AudioDevice, isOutput: Bool) -> Bool? {
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        for element: UInt32 in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: scope, mElement: element
            )
            guard AudioObjectHasProperty(device.id, &addr) else { continue }
            var muted: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &muted) == noErr else { continue }
            return muted != 0
        }
        return nil
    }

    func setVolume(_ volume: Float, for device: AudioDevice, isOutput: Bool) {
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope, mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(device.id, &addr) {
            var vol = volume
            AudioObjectSetPropertyData(device.id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            if isOutput {
                DispatchQueue.main.async {
                    self.outputVolume = volume
                    self.isOutputMuted = volume <= 0.001
                }
            } else { DispatchQueue.main.async { self.inputVolume = volume } }
            return
        }
        for ch: UInt32 in [1, 2] {
            addr.mElement = ch
            if AudioObjectHasProperty(device.id, &addr) {
                var vol = volume
                AudioObjectSetPropertyData(device.id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &vol)
            }
        }
        if isOutput {
            DispatchQueue.main.async {
                self.outputVolume = volume
                self.isOutputMuted = volume <= 0.001
            }
        } else { DispatchQueue.main.async { self.inputVolume = volume } }
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
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device.id, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    func isTemporarilyUnavailable(_ uid: String, now: Date = Date()) -> Bool {
        unavailableUntilByUIDLock.lock()
        defer { unavailableUntilByUIDLock.unlock() }
        unavailableUntilByUID = unavailableUntilByUID.filter { $0.value > now }
        return Self.isDeviceUnavailable(until: unavailableUntilByUID[uid], now: now)
    }

    func requiresManualConnection(_ device: AudioDevice) -> Bool {
        Self.requiresManualConnection(
            uid: device.uid,
            name: device.name,
            transportType: device.transportType,
            modelUID: device.modelUID
        )
    }

    // MARK: – Periodic refresh (battery)

    private func startPeriodicRefresh() {
        // Batteries on Bluetooth devices can change while connected without
        // triggering a device-list change event, so a periodic refresh is needed.
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            self?.refreshBluetoothBatterySnapshotIfNeeded(force: true)
        }
    }

    // MARK: – Input level (AVAudioEngine)

    private func startInputLevelMonitor() {
        stopInputLevelMonitor()

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    guard granted, self.isInputLevelMonitoringEnabled else { return }
                    self.startInputLevelMonitor()
                }
            }
            return
        case .denied, .restricted:
            inputLevel = 0
            return
        @unknown default:
            inputLevel = 0
            return
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        // Pass nil so AVAudioEngine picks its own compatible format.
        // Passing the hardware format explicitly crashes when the device reports a
        // deinterleaved layout after a switch (AVAudioEngine rejects it as a mismatch).
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            let ch = Int(buffer.format.channelCount)
            guard ch > 0 else { return }
            let fr = Int(buffer.frameLength)
            var sum: Float = 0
            for c in 0 ..< ch {
                let p = data[c]; for f in 0 ..< fr {
                    sum += p[f] * p[f]
                }
            }
            let rms = sqrt(sum / Float(ch * max(fr, 1)))
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
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        ) == noErr
        else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        ) == noErr
        else { return [] }
        let powerSources = fetchPowerSourceBatteries()
        let btSnapshot = bluetoothBatterySnapshot
        return ids.compactMap { makeDevice(from: $0, powerSources: powerSources, bluetoothBatterySnapshot: btSnapshot) }
    }

    private func makeDevice(
        from id: AudioDeviceID,
        powerSources: [PowerSourceBattery] = [],
        bluetoothBatterySnapshot: BluetoothBatterySnapshot = .init()
    ) -> AudioDevice? {
        guard
            let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
            let name = stringProperty(id, kAudioDevicePropertyDeviceNameCFString)
        else { return nil }

        let transport = fetchTransportType(id)

        // Filter all aggregate devices — this removes macOS-internal auto-aggregates
        // (CADefaultDeviceAggregate-*, created and destroyed on every device change)
        // as well as user-created aggregate devices from Audio MIDI Setup.
        if transport == .aggregate { return nil }

        let hasIn = hasStreams(id, scope: kAudioObjectPropertyScopeInput)
        let hasOut = hasStreams(id, scope: kAudioObjectPropertyScopeOutput)
        guard hasIn || hasOut else { return nil }

        let modelUID = stringProperty(id, kAudioDevicePropertyModelUID)

        let (iconBase, isAppleFromIconPath) = fetchIconInfo(id)
        var isAppleMade = isAppleFromIconPath
        var bluetoothMinorType: String? = nil
        if transport == .bluetooth {
            bluetoothMinorType = bluetoothMinorTypeFromBluetoothSnapshot(
                deviceName: name,
                uid: uid,
                snapshot: bluetoothBatterySnapshot
            )
            if let vendorID = bluetoothVendorIDFromBluetoothSnapshot(
                deviceName: name,
                uid: uid,
                snapshot: bluetoothBatterySnapshot
            ),
                vendorID == 0x004C
            {
                isAppleMade = true
            }
        }

        // Battery resolution order:
        //   1. IOPowerSources (when available)
        //   2. system_profiler SPBluetoothDataType (Bluetooth battery, incl. multi-cell)
        //   3. CoreAudio 'batt' (single value)
        //   4. IOKit HID fallback for third-party BT HID devices (single value)

        var batteryStates: [AudioDevice.BatteryState] = []
        batteryStates.append(contentsOf: batteryStatesFromPowerSources(name, powerSources))
        if transport == .bluetooth {
            batteryStates.append(contentsOf: batteryStatesFromBluetoothSnapshot(
                deviceName: name,
                uid: uid,
                snapshot: bluetoothBatterySnapshot
            ))
        }
        batteryStates = Self.normalizedBatteryStates(batteryStates)

        if batteryStates.isEmpty, let coreAudioBattery = fetchBatteryLevel(id) {
            batteryStates = [.init(kind: .device, level: coreAudioBattery, sourceName: "CoreAudio")]
        }
        if batteryStates.isEmpty, transport == .bluetooth, let fallback = fetchBluetoothBatteryViaIOKit(uid: uid) {
            batteryStates = [.init(kind: .device, level: fallback, sourceName: "IOKit")]
        }
        return AudioDevice(id: id, uid: uid, name: name,
                           hasInput: hasIn, hasOutput: hasOut,
                           transportType: transport,
                           iconBaseName: iconBase,
                           modelUID: modelUID,
                           isAppleMade: isAppleMade,
                           bluetoothMinorType: bluetoothMinorType,
                           batteryStates: batteryStates)
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
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &addr) else { return (nil, false) }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &dataSize) == noErr else { return (nil, false) }

        let expected = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        guard dataSize == expected else { return (nil, false) }

        var urlRef: Unmanaged<CFURL>? = nil
        var size = dataSize
        let status = withUnsafeMutablePointer(to: &urlRef) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let url = urlRef?.takeRetainedValue() as URL? else {
            return (nil, false)
        }
        let baseName = url.deletingPathExtension().lastPathComponent.lowercased()
        let isApple = url.path.lowercased().contains("apple")
        return (baseName, isApple)
    }

    /// kAudioDevicePropertyBatteryLevel ('batt') — [0…1], nil if not reported.
    /// Tries Global, Output, and Input scopes; uses AudioObjectHasProperty before each read.
    private func fetchBatteryLevel(_ id: AudioDeviceID) -> Float? {
        let kBatteryLevel: AudioObjectPropertySelector = 0x6261_7474 // 'batt'
        let scopes: [AudioObjectPropertyScope] = [
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyScopeOutput,
            kAudioObjectPropertyScopeInput,
        ]
        for scope in scopes {
            var addr = AudioObjectPropertyAddress(
                mSelector: kBatteryLevel, mScope: scope,
                mElement: kAudioObjectPropertyElementMain
            )
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

    private struct BluetoothBatterySnapshot {
        var byMAC: [String: [AudioDevice.BatteryState]] = [:] // key: aa:bb:cc:dd:ee:ff
        var byNameKey: [String: [AudioDevice.BatteryState]] = [:] // key: batteryMatchKey(deviceName)
        var vendorIDByMAC: [String: Int] = [:] // key: aa:bb:cc:dd:ee:ff
        var vendorIDByNameKey: [String: Int] = [:] // key: batteryMatchKey(deviceName)
        var productIDByMAC: [String: Int] = [:] // key: aa:bb:cc:dd:ee:ff
        var productIDByNameKey: [String: Int] = [:] // key: batteryMatchKey(deviceName)
        var minorTypeByMAC: [String: String] = [:] // key: aa:bb:cc:dd:ee:ff
        var minorTypeByNameKey: [String: String] = [:] // key: batteryMatchKey(deviceName)
    }

    private func refreshBluetoothBatterySnapshotIfNeeded(force: Bool = false) {
        if bluetoothBatterySnapshotRefreshInFlight { return }
        if !force, let last = bluetoothBatterySnapshotLastRefreshedAt, Date().timeIntervalSince(last) < 30 {
            return
        }
        bluetoothBatterySnapshotRefreshInFlight = true

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let snapshot = Self.fetchBluetoothBatterySnapshotFromSystemProfiler()
            DispatchQueue.main.async {
                guard let self else { return }
                self.bluetoothBatterySnapshot = snapshot
                self.bluetoothBatterySnapshotLastRefreshedAt = Date()
                self.bluetoothBatterySnapshotRefreshInFlight = false
                self.refreshDevicesAsync()
            }
        }
    }

    private static func fetchBluetoothBatterySnapshotFromSystemProfiler() -> BluetoothBatterySnapshot {
        let profilerPath = "/usr/sbin/system_profiler"
        guard FileManager.default.isExecutableFile(atPath: profilerPath) else { return BluetoothBatterySnapshot() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: profilerPath)
        process.arguments = ["SPBluetoothDataType", "-json"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return BluetoothBatterySnapshot() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return BluetoothBatterySnapshot() }

        guard
            let obj = try? JSONSerialization.jsonObject(with: data, options: []),
            let top = obj as? [String: Any],
            let roots = top["SPBluetoothDataType"] as? [[String: Any]]
        else { return BluetoothBatterySnapshot() }

        var snapshot = BluetoothBatterySnapshot()

        func ingestSection(from root: [String: Any], _ sectionKey: String) {
            guard let section = root[sectionKey] as? [Any] else { return }
            for entry in section {
                guard let entryDict = entry as? [String: Any] else { continue }
                for (deviceName, infoAny) in entryDict {
                    guard let info = infoAny as? [String: Any] else { continue }
                    let states = batteryStatesFromSystemProfilerDeviceInfo(info)
                    let vendorID = vendorIDFromSystemProfilerDeviceInfo(info)
                    let productID = productIDFromSystemProfilerDeviceInfo(info)
                    let minorType = minorTypeFromSystemProfilerDeviceInfo(info)

                    if let macRaw = info["device_address"] as? String {
                        let mac = macRaw.lowercased()
                        if !states.isEmpty {
                            snapshot.byMAC[mac] = normalizedBatteryStates((snapshot.byMAC[mac] ?? []) + states)
                        }
                        if let vendorID {
                            snapshot.vendorIDByMAC[mac] = vendorID
                        }
                        if let productID {
                            snapshot.productIDByMAC[mac] = productID
                        }
                        if let minorType {
                            snapshot.minorTypeByMAC[mac] = minorType
                        }
                    }

                    let nameKey = batteryMatchKey(deviceName)
                    if !nameKey.isEmpty {
                        if !states.isEmpty {
                            snapshot.byNameKey[nameKey] = normalizedBatteryStates((snapshot.byNameKey[nameKey] ?? []) + states)
                        }
                        if let vendorID {
                            snapshot.vendorIDByNameKey[nameKey] = vendorID
                        }
                        if let productID {
                            snapshot.productIDByNameKey[nameKey] = productID
                        }
                        if let minorType {
                            snapshot.minorTypeByNameKey[nameKey] = minorType
                        }
                    }
                }
            }
        }

        for root in roots {
            ingestSection(from: root, "device_connected")
            ingestSection(from: root, "device_not_connected")
        }

        return snapshot
    }

    private func batteryStatesFromBluetoothSnapshot(
        deviceName: String,
        uid: String,
        snapshot: BluetoothBatterySnapshot
    ) -> [AudioDevice.BatteryState] {
        if let mac = Self.bluetoothMAC(fromUID: uid),
           let states = snapshot.byMAC[mac]
        {
            return states
        }
        let key = Self.batteryMatchKey(deviceName)
        return snapshot.byNameKey[key] ?? []
    }

    private func bluetoothVendorIDFromBluetoothSnapshot(
        deviceName: String,
        uid: String,
        snapshot: BluetoothBatterySnapshot
    ) -> Int? {
        if let mac = Self.bluetoothMAC(fromUID: uid),
           let vendorID = snapshot.vendorIDByMAC[mac]
        {
            return vendorID
        }
        let key = Self.batteryMatchKey(deviceName)
        return snapshot.vendorIDByNameKey[key]
    }

    private func bluetoothProductIDFromBluetoothSnapshot(
        deviceName: String,
        uid: String,
        snapshot: BluetoothBatterySnapshot
    ) -> Int? {
        if let mac = Self.bluetoothMAC(fromUID: uid),
           let productID = snapshot.productIDByMAC[mac]
        {
            return productID
        }
        let key = Self.batteryMatchKey(deviceName)
        return snapshot.productIDByNameKey[key]
    }

    private func bluetoothMinorTypeFromBluetoothSnapshot(
        deviceName: String,
        uid: String,
        snapshot: BluetoothBatterySnapshot
    ) -> String? {
        if let mac = Self.bluetoothMAC(fromUID: uid),
           let minor = snapshot.minorTypeByMAC[mac]
        {
            return minor
        }
        let key = Self.batteryMatchKey(deviceName)
        return snapshot.minorTypeByNameKey[key]
    }

    private static func bluetoothMAC(fromUID uid: String) -> String? {
        // UID format for BT devices: "2C-32-6A-E9-E9-65:output"
        let parts = uid.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return nil }
        let macDash = String(first).lowercased()
        guard macDash.count == 17, macDash.filter({ $0 == "-" }).count == 5 else { return nil }
        return macDash.replacingOccurrences(of: "-", with: ":")
    }

    private static func batteryStatesFromSystemProfilerDeviceInfo(_ info: [String: Any]) -> [AudioDevice.BatteryState] {
        let candidates: [(String, AudioDevice.BatteryState.Kind)] = [
            ("device_batteryLevelLeft", .left),
            ("device_batteryLevelRight", .right),
            ("device_batteryLevelCase", .case),
            ("device_batteryLevelMain", .device),
            ("device_batteryLevelSingle", .device),
            ("device_batteryLevel", .device),
        ]

        var states: [AudioDevice.BatteryState] = []
        for (key, kind) in candidates {
            guard let raw = info[key], let level = parseBatteryPercentFraction(raw) else { continue }
            states.append(.init(kind: kind, level: level, sourceName: "Bluetooth"))
        }
        return normalizedBatteryStates(states)
    }

    private static func vendorIDFromSystemProfilerDeviceInfo(_ info: [String: Any]) -> Int? {
        guard let raw = info["device_vendorID"] else { return nil }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("0x") { return Int(trimmed.dropFirst(2), radix: 16) }
            return Int(trimmed)
        }
        if let n = raw as? NSNumber {
            return n.intValue
        }
        return nil
    }

    private static func productIDFromSystemProfilerDeviceInfo(_ info: [String: Any]) -> Int? {
        guard let raw = info["device_productID"] else { return nil }
        if let s = raw as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("0x") { return Int(trimmed.dropFirst(2), radix: 16) }
            return Int(trimmed)
        }
        if let n = raw as? NSNumber {
            return n.intValue
        }
        return nil
    }

    private static func minorTypeFromSystemProfilerDeviceInfo(_ info: [String: Any]) -> String? {
        guard let s = info["device_minorType"] as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseBatteryPercentFraction(_ value: Any) -> Float? {
        if let n = value as? NSNumber {
            let f = n.floatValue
            if f <= 1 { return f.clamped(to: 0 ... 1) }
            return (f / 100).clamped(to: 0 ... 1)
        }
        guard let s = value as? String else { return nil }
        let digits = s.filter(\.isNumber)
        guard let pct = Int(digits) else { return nil }
        return Float(pct).clamped(to: 0 ... 100) / 100
    }

    /// Reads all external power sources via the public IOPowerSources API — the same source
    /// that macOS Control Center uses to show AirPods battery.
    ///
    /// Returns a list of power source names and their battery fraction [0…1].
    private struct PowerSourceBattery {
        let name: String
        let level: Float
    }

    private func fetchPowerSourceBatteries() -> [PowerSourceBattery] {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return [] }

        var result: [PowerSourceBattery] = []
        for source in list {
            guard
                let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                let present = desc["Is Present"] as? Bool, present,
                let name = desc["Name"] as? String, !name.isEmpty,
                let current = desc["Current Capacity"] as? Int,
                let maxCap = desc["Max Capacity"] as? Int, maxCap > 0
            else { continue }
            let level = Float(current).clamped(to: 0 ... Float(maxCap)) / Float(maxCap)
            result.append(PowerSourceBattery(name: name, level: level))
        }
        // De-duplicate identical names (keep the lowest reading).
        var best: [String: PowerSourceBattery] = [:]
        for item in result {
            let key = item.name.lowercased()
            if let existing = best[key] {
                if item.level < existing.level { best[key] = item }
            } else {
                best[key] = item
            }
        }
        return best.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Matches a CoreAudio device name against the IOPowerSources list.
    /// Returns 0…N battery states (AirPods often have left/right/case).
    private func batteryStatesFromPowerSources(
        _ deviceName: String,
        _ ps: [PowerSourceBattery]
    ) -> [AudioDevice.BatteryState] {
        guard !ps.isEmpty else { return [] }
        let deviceLower = deviceName.lowercased()
        let deviceKey = Self.batteryMatchKey(deviceName)
        guard deviceKey.count >= 3 else { return [] }

        let matches = ps.filter { source in
            let sourceLower = source.name.lowercased()
            if sourceLower == deviceLower { return true }
            let sourceKey = Self.batteryMatchKey(source.name)
            guard !sourceKey.isEmpty else { return false }
            return deviceKey.contains(sourceKey) || sourceKey.contains(deviceKey)
        }

        var states = matches.map { source in
            AudioDevice.BatteryState(
                kind: Self.inferBatteryKind(from: source.name),
                level: source.level,
                sourceName: source.name
            )
        }
        states = Self.normalizedBatteryStates(states)
        return states
    }

    private static func inferBatteryKind(from name: String) -> AudioDevice.BatteryState.Kind {
        let n = name.lowercased()
        if n.contains("left") { return .left }
        if n.contains("right") { return .right }
        if n.contains("case") { return .case }
        return .device
    }

    private static func batteryMatchKey(_ s: String) -> String {
        var out = s.lowercased()
        let removeTokens = [
            // AirPods / multi-cell naming
            "left",
            "right",
            "case",
            "charging case",
            // Bluetooth profile suffixes
            "hands-free",
            "hands free",
            "handsfree",
            "headset",
            "hfp",
            "ag audio",
            "audio gateway",
        ]
        for token in removeTokens {
            out = out.replacingOccurrences(of: token, with: "")
        }
        out = out.replacingOccurrences(of: "[-–—_()\\[\\]]", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBatteryStates(_ states: [AudioDevice.BatteryState]) -> [AudioDevice.BatteryState] {
        guard !states.isEmpty else { return [] }
        var bestByKind: [AudioDevice.BatteryState.Kind: AudioDevice.BatteryState] = [:]
        for state in states {
            if let existing = bestByKind[state.kind] {
                if state.level < existing.level { bestByKind[state.kind] = state }
            } else {
                bestByKind[state.kind] = state
            }
        }
        let order: [AudioDevice.BatteryState.Kind: Int] = [
            .left: 0,
            .right: 1,
            .device: 2,
            .other: 3,
            .case: 4,
        ]
        return bestByKind.values.sorted { a, b in
            let l = order[a.kind] ?? 99
            let r = order[b.kind] ?? 99
            if l != r { return l < r }
            return (a.sourceName ?? "").localizedCaseInsensitiveCompare(b.sourceName ?? "") == .orderedAscending
        }
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

        let macDash = macWithDashes.lowercased()
        let macColon = macDash.replacingOccurrences(of: "-", with: ":")

        for serviceClass in ["IOBluetoothHIDDriver", "AppleBluetoothHIDDriver"] {
            if let level = ioKitHIDBattery(service: serviceClass,
                                           macDash: macDash, macColon: macColon)
            {
                return level
            }
        }
        return nil
    }

    private func ioKitHIDBattery(service: String, macDash: String, macColon: String) -> Float? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching(service), &iter
        ) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            var propRef: Unmanaged<CFMutableDictionary>? = nil
            guard IORegistryEntryCreateCFProperties(
                entry, &propRef, kCFAllocatorDefault, 0
            ) == KERN_SUCCESS,
                let dict = propRef?.takeRetainedValue() as? [String: Any] else { continue }

            let strings = dict.values.compactMap { $0 as? String }.map { $0.lowercased() }
            guard strings.contains(where: { $0.contains(macDash) || $0.contains(macColon) })
            else { continue }

            if let pct = dict["BatteryPercent"] as? Int { return Float(pct).clamped(to: 0 ... 100) / 100 }
            if let pct = dict["BatteryPercentRaw"] as? Int { return Float(pct).clamped(to: 0 ... 100) / 100 }
            if let lvl = dict["BatteryLevel"] as? Int { return Float(lvl).clamped(to: 0 ... 100) / 100 }
        }
        return nil
    }

    private func fetchTransportType(_ id: AudioDeviceID) -> AudioDevice.TransportType {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var raw: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &raw) == noErr else { return .unknown }
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn: return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
        case kAudioDeviceTransportTypeHDMI: return .hdmi
        case kAudioDeviceTransportTypeDisplayPort: return .displayPort
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: return .aggregate
        case kAudioDeviceTransportTypeVirtual: return .virtual
        case kAudioDeviceTransportTypePCI: return .pci
        default: return .unknown
        }
    }

    /// Returns the CoreAudio ID of the current system default device, or kAudioObjectUnknown.
    private func resolveDefaultID(input: Bool) -> AudioDeviceID {
        let selector = input
            ? kAudioHardwarePropertyDefaultInputDevice
            : kAudioHardwarePropertyDefaultOutputDevice
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &devID
        ) == noErr
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
        return makeDevice(
            from: devID,
            powerSources: powerSources,
            bluetoothBatterySnapshot: bluetoothBatterySnapshot
        )
    }

    // MARK: – Helpers

    private func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(id, &addr) else { return nil }

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &dataSize) == noErr else { return nil }

        // Some CoreAudio string properties (notably manufacturer on newer macOS versions)
        // can return raw C-string bytes instead of a CFString pointer. Only accept the
        // pointer-sized CFStringRef representation here to avoid bad-pointer crashes.
        let expected = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard dataSize == expected else { return nil }

        var cfRef: Unmanaged<CFString>? = nil
        var size = dataSize
        let status = withUnsafeMutablePointer(to: &cfRef) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let ref = cfRef else { return nil }
        return ref.takeRetainedValue() as String
    }

    private func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    // MARK: – Listeners

    private func addListeners() {
        let sys = AudioObjectID(kAudioObjectSystemObject)
        addListener(on: sys, selector: kAudioHardwarePropertyDevices) { [weak self] in
            self?.refreshDevicesAsync()
            self?.refreshBluetoothBatterySnapshotIfNeeded(force: true)
            NotificationCenter.default.post(name: .audioDevicesChanged, object: self)
        }
        addListener(on: sys, selector: kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            guard let self else { return }
            refreshDevicesAsync()
            refreshBluetoothBatterySnapshotIfNeeded(force: true)
        }
        addListener(on: sys, selector: kAudioHardwarePropertyDefaultInputDevice) { [weak self] in
            guard let self else { return }
            inputLevel = 0 // reset immediately
            refreshDevicesAsync()
            refreshBluetoothBatterySnapshotIfNeeded(force: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, isInputLevelMonitoringEnabled else { return }
                if let uid = defaultInput?.uid, isTemporarilyUnavailable(uid) {
                    inputLevel = 0
                    return
                }
                startInputLevelMonitor() // reattach tap to new device
            }
        }
    }

    private func refreshDevicesAsync() {
        coreAudioWorkQueue.async { [weak self] in
            self?.refreshDevices()
        }
    }

    static func didDefaultSwitchSucceed(
        status: OSStatus,
        resolvedDefaultID: AudioDeviceID,
        targetID: AudioDeviceID
    ) -> Bool {
        status == noErr && resolvedDefaultID == targetID
    }

    static func requiresManualConnection(
        uid: String,
        name: String,
        transportType: AudioDevice.TransportType,
        modelUID: String?
    ) -> Bool {
        let model = modelUID?.lowercased() ?? ""
        if model.contains("iphone mic") || model.contains("continuity") {
            return true
        }

        guard transportType == .unknown else { return false }
        let lowerName = name.lowercased()
        if model.contains("iphone") || lowerName.contains("iphone") {
            return true
        }
        return Self.looksLikeCoreAudioUUID(uid)
    }

    static func isDeviceUnavailable(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return until > now
    }

    static func looksLikeCoreAudioUUID(_ uid: String) -> Bool {
        let regex = try? NSRegularExpression(
            pattern: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        )
        let range = NSRange(uid.startIndex ..< uid.endIndex, in: uid)
        return regex?.firstMatch(in: uid, options: [], range: range) != nil
    }

    private func markDeviceTemporarilyUnavailable(_ uid: String, now: Date = Date()) {
        unavailableUntilByUIDLock.lock()
        unavailableUntilByUID[uid] = now.addingTimeInterval(unavailableCooldownSeconds)
        unavailableUntilByUIDLock.unlock()
    }

    private func clearTemporarilyUnavailable(_ uid: String) {
        unavailableUntilByUIDLock.lock()
        unavailableUntilByUID.removeValue(forKey: uid)
        unavailableUntilByUIDLock.unlock()
    }

    // MARK: – Volume listeners (default devices)

    private struct ListenerToken {
        let objectID: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private func rebuildVolumeListenersIfNeeded() {
        let outID = defaultOutput?.id ?? kAudioObjectUnknown
        let inID = defaultInput?.id ?? kAudioObjectUnknown
        guard outID != volumeListenerOutputID || inID != volumeListenerInputID else { return }

        removeVolumeListeners()
        if let out = defaultOutput { installVolumeListeners(for: out, isOutput: true) }
        if let inp = defaultInput { installVolumeListeners(for: inp, isOutput: false) }
        volumeListenerOutputID = outID
        volumeListenerInputID = inID
    }

    private func removeVolumeListeners() {
        for token in volumeListeners {
            var addr = token.address
            AudioObjectRemovePropertyListenerBlock(token.objectID, &addr, .main, token.block)
        }
        volumeListeners.removeAll()
        volumeListenerOutputID = kAudioObjectUnknown
        volumeListenerInputID = kAudioObjectUnknown
    }

    private func installVolumeListeners(for device: AudioDevice, isOutput: Bool) {
        let deviceObjectID = AudioObjectID(device.id)
        let scope: AudioObjectPropertyScope = isOutput
            ? kAudioObjectPropertyScopeOutput
            : kAudioObjectPropertyScopeInput
        let elements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]
        let selectors: [AudioObjectPropertySelector] = [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute]

        for selector in selectors {
            for element in elements {
                var addr = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: scope,
                    mElement: element
                )
                guard AudioObjectHasProperty(device.id, &addr) else { continue }
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                    DispatchQueue.main.async { self?.refreshVolumeFromSystem(isOutput: isOutput) }
                }
                AudioObjectAddPropertyListenerBlock(deviceObjectID, &addr, .main, block)
                volumeListeners.append(ListenerToken(objectID: deviceObjectID, address: addr, block: block))
            }
        }
    }

    private func refreshVolumeFromSystem(isOutput: Bool) {
        if isOutput {
            guard let out = defaultOutput else { return }
            let current = outputVolume
            let currentMuted = isOutputMuted
            coreAudioWorkQueue.async { [weak self] in
                guard let self else { return }
                let newValue = volume(for: out, isOutput: true) ?? current
                let newMuted = mute(for: out, isOutput: true) ?? currentMuted
                DispatchQueue.main.async { [weak self] in
                    guard let self, defaultOutput?.id == out.id else { return }
                    if abs(newValue - outputVolume) > 0.005 {
                        outputVolume = newValue
                    }
                    if newMuted != isOutputMuted {
                        isOutputMuted = newMuted
                    }
                }
            }
        } else {
            guard let inp = defaultInput else { return }
            let current = inputVolume
            coreAudioWorkQueue.async { [weak self] in
                guard let self else { return }
                let newValue = volume(for: inp, isOutput: false) ?? current
                DispatchQueue.main.async { [weak self] in
                    guard let self, defaultInput?.id == inp.id else { return }
                    if abs(newValue - inputVolume) > 0.005 {
                        inputVolume = newValue
                    }
                }
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
            mElement: kAudioObjectPropertyElementMain
        )
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

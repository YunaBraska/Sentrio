import Combine
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    // MARK: – Priority lists (enabled devices, in order)

    @Published var outputPriority: [String] {
        didSet { save("outputPriority", outputPriority) }
    }

    @Published var inputPriority: [String] {
        didSet { save("inputPriority", inputPriority) }
    }

    // MARK: – Disabled device sets (not used as fallbacks)

    @Published var disabledOutputDevices: Set<String> {
        didSet { save("disabledOutputDevices", Array(disabledOutputDevices)) }
    }

    @Published var disabledInputDevices: Set<String> {
        didSet { save("disabledInputDevices", Array(disabledInputDevices)) }
    }

    // MARK: – Volume memory   [uid: ["output": Float, "input": Float, "alert": Float]]

    @Published var volumeMemory: [String: [String: Float]] {
        didSet { save("volumeMemory", volumeMemory) }
    }

    // MARK: – Per-device custom names   [uid: ["output": name, "input": name]]

    @Published var customDeviceNames: [String: [String: String]] {
        didSet { save("customDeviceNames", customDeviceNames) }
    }

    // MARK: – Per-device custom icons   [uid: ["output": symbolName, "input": symbolName]]

    @Published var deviceIcons: [String: [String: String]] {
        didSet { save("deviceIcons", deviceIcons) }
    }

    // MARK: – Known devices (uid → name, persists across disconnections)

    @Published var knownDevices: [String: String] {
        didSet { save("knownDevices", knownDevices) }
    }

    // MARK: – Known device metadata (persists across disconnections)

    /// Last-seen transport type for a device UID (helps icon inference for disconnected devices).
    @Published var knownDeviceTransportTypes: [String: AudioDevice.TransportType] {
        didSet { save("knownDeviceTransportTypes", knownDeviceTransportTypes) }
    }

    /// Last-seen CoreAudio icon base name for a device UID (kAudioDevicePropertyIcon stem).
    @Published var knownDeviceIconBaseNames: [String: String] {
        didSet { save("knownDeviceIconBaseNames", knownDeviceIconBaseNames) }
    }

    /// Last-seen "Apple-made" hint derived from the CoreAudio icon URL path.
    @Published var knownDeviceIsAppleMade: [String: Bool] {
        didSet { save("knownDeviceIsAppleMade", knownDeviceIsAppleMade) }
    }

    /// Last-seen CoreAudio modelUID for a device UID (kAudioDevicePropertyModelUID).
    /// Useful for reliable Apple device-family detection even when the user renames the device.
    @Published var knownDeviceModelUIDs: [String: String] {
        didSet { save("knownDeviceModelUIDs", knownDeviceModelUIDs) }
    }

    /// Last-seen Bluetooth minor type from system_profiler (e.g. "Headphones", "Headset", "Phone").
    @Published var knownDeviceBluetoothMinorTypes: [String: String] {
        didSet { save("knownDeviceBluetoothMinorTypes", knownDeviceBluetoothMinorTypes) }
    }

    // MARK: – General

    @Published var isAutoMode: Bool {
        didSet { defaults.set(isAutoMode, forKey: "isAutoMode") }
    }

    @Published var hideMenuBarIcon: Bool {
        didSet { defaults.set(hideMenuBarIcon, forKey: "hideMenuBarIcon") }
    }

    @Published var showInputLevelMeter: Bool {
        didSet { defaults.set(showInputLevelMeter, forKey: "showInputLevelMeter") }
    }

    // MARK: – Stats

    @Published var autoSwitchCount: Int {
        didSet { defaults.set(autoSwitchCount, forKey: "autoSwitchCount") }
    }

    @Published var millisecondsSaved: Int {
        didSet { defaults.set(millisecondsSaved, forKey: "millisecondsSaved") }
    }

    @Published var signalIntegrityScore: Int {
        didSet { defaults.set(signalIntegrityScore, forKey: "signalIntegrityScore") }
    }

    // MARK: – Sounds

    @Published var testSound: AppSound {
        didSet { save("testSound", testSound) }
    }

    @Published var alertSound: AppSound {
        didSet { save("alertSound", alertSound) }
    }

    // MARK: – Storage

    private let defaults: UserDefaults

    // MARK: – Init (injectable for testing)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputPriority = defaults.jsonStringArray(forKey: "outputPriority") ?? []
        inputPriority = defaults.jsonStringArray(forKey: "inputPriority") ?? []
        disabledOutputDevices = Set(defaults.jsonStringArray(forKey: "disabledOutputDevices") ?? [])
        disabledInputDevices = Set(defaults.jsonStringArray(forKey: "disabledInputDevices") ?? [])
        isAutoMode = defaults.object(forKey: "isAutoMode") as? Bool ?? true
        hideMenuBarIcon = defaults.object(forKey: "hideMenuBarIcon") as? Bool ?? false
        showInputLevelMeter = defaults.object(forKey: "showInputLevelMeter") as? Bool ?? true
        autoSwitchCount = defaults.integer(forKey: "autoSwitchCount")
        millisecondsSaved = defaults.integer(forKey: "millisecondsSaved")
        signalIntegrityScore = defaults.integer(forKey: "signalIntegrityScore")
        volumeMemory = defaults.jsonDecode([String: [String: Float]].self, forKey: "volumeMemory") ?? [:]
        deviceIcons = defaults.jsonDecode([String: [String: String]].self, forKey: "deviceIcons") ?? [:]
        customDeviceNames = defaults.jsonDecode([String: [String: String]].self, forKey: "customDeviceNames") ?? [:]
        knownDevices = defaults.jsonDecode([String: String].self, forKey: "knownDevices") ?? [:]
        knownDeviceTransportTypes = defaults.jsonDecode([String: AudioDevice.TransportType].self, forKey: "knownDeviceTransportTypes") ?? [:]
        knownDeviceIconBaseNames = defaults.jsonDecode([String: String].self, forKey: "knownDeviceIconBaseNames") ?? [:]
        knownDeviceIsAppleMade = defaults.jsonDecode([String: Bool].self, forKey: "knownDeviceIsAppleMade") ?? [:]
        knownDeviceModelUIDs = defaults.jsonDecode([String: String].self, forKey: "knownDeviceModelUIDs") ?? [:]
        knownDeviceBluetoothMinorTypes = defaults.jsonDecode([String: String].self, forKey: "knownDeviceBluetoothMinorTypes") ?? [:]
        testSound = defaults.jsonDecode(AppSound.self, forKey: "testSound") ?? .defaultTestSound
        alertSound = defaults.jsonDecode(AppSound.self, forKey: "alertSound") ?? .defaultAlertSound
    }

    // MARK: – Volume memory

    func saveVolume(_ volume: Float, for uid: String, isOutput: Bool) {
        var entry = volumeMemory[uid] ?? [:]
        entry[isOutput ? "output" : "input"] = volume
        volumeMemory[uid] = entry
    }

    func savedVolume(for uid: String, isOutput: Bool) -> Float? {
        volumeMemory[uid]?[isOutput ? "output" : "input"]
    }

    func saveAlertVolume(_ volume: Float, for uid: String) {
        var entry = volumeMemory[uid] ?? [:]
        entry["alert"] = volume
        volumeMemory[uid] = entry
    }

    func savedAlertVolume(for uid: String) -> Float? {
        volumeMemory[uid]?["alert"]
    }

    // MARK: – Per-device icon

    /// All icons available in the per-device icon picker.
    /// Includes device-type icons (what the device IS) and transport-type icons (how it connects),
    /// because macOS can auto-detect and display all of them — the user should be able to pick any.
    /// Only uses SF Symbols confirmed available on macOS 13+.
    /// Note: "bluetooth" is a restricted Apple-internal symbol that renders empty — "wave.3.right" is used instead.
    static let iconOptions: [(symbol: String, label: String)] = [
        // ── Audio output ────────────────────────────────────────────
        ("speaker.wave.2", "Speaker"),
        ("speaker.wave.1", "Speaker (quiet)"),
        ("speaker.wave.3", "Speaker (loud)"),
        ("speaker.slash", "Muted"),
        ("hifispeaker", "Hi-Fi Speaker"),
        ("waveform", "Waveform"),
        // ── Audio input ─────────────────────────────────────────────
        ("mic", "Microphone"),
        ("mic.fill", "Microphone (filled)"),
        ("ear", "Ear"),
        // ── Headphones / earbuds ────────────────────────────────────
        ("headphones", "Headphones"),
        ("earbuds", "EarPods"),
        ("airpodspro", "AirPods Pro"),
        ("airpods", "AirPods"),
        ("airpodsmax", "AirPods Max"),
        // ── Apple devices ───────────────────────────────────────────
        ("homepod", "HomePod"),
        ("homepodmini", "HomePod mini"),
        ("iphone", "iPhone"),
        ("ipad", "iPad"),
        ("applewatch", "Apple Watch"),
        ("laptopcomputer", "MacBook"),
        ("macmini", "Mac mini"),
        ("desktopcomputer", "iMac / Desktop"),
        ("appletv", "Apple TV"),
        ("display", "Display / Monitor"),
        // ── Music ───────────────────────────────────────────────────
        ("music.note", "Music"),
        // ── Connection / transport type ─────────────────────────────
        ("internaldrive", "Built-in"),
        ("cable.connector", "USB"),
        ("bolt", "Thunderbolt"),
        ("wave.3.right", "Wireless / BT"),
        ("airplayaudio", "AirPlay"),
        ("antenna.radiowaves.left.and.right", "Radio"),
        ("link", "Linked / Aggregate"),
        ("waveform.path", "Virtual"),
        ("cpu", "PCI / CPU"),
        ("questionmark.circle", "Unknown"),
    ]

    // MARK: – Custom device names

    /// The display name for a device in a given role.
    /// Priority: custom role name → known device name → UID.
    func displayName(for uid: String, isOutput: Bool) -> String {
        customDeviceNames[uid]?[isOutput ? "output" : "input"] ?? knownDevices[uid] ?? uid
    }

    /// Sets a custom display name for a device in a given role.
    /// Passing an empty or whitespace-only string clears the custom name.
    func setCustomName(_ name: String, for uid: String, isOutput: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = customDeviceNames[uid] ?? [:]
        let key = isOutput ? "output" : "input"
        if trimmed.isEmpty { entry.removeValue(forKey: key) } else { entry[key] = trimmed }
        if entry.isEmpty { customDeviceNames.removeValue(forKey: uid) }
        else { customDeviceNames[uid] = entry }
    }

    func clearCustomName(for uid: String, isOutput: Bool) {
        customDeviceNames[uid]?[isOutput ? "output" : "input"] = nil
        if customDeviceNames[uid]?.isEmpty == true { customDeviceNames.removeValue(forKey: uid) }
    }

    // MARK: – Per-device icon

    /// Returns the custom icon for a device+role, or its auto-detected device-type icon.
    func iconName(for device: AudioDevice, isOutput: Bool) -> String {
        if let custom = deviceIcons[device.uid]?[isOutput ? "output" : "input"] { return custom }
        return device.deviceTypeSystemImage
    }

    /// Default icon for a known device UID (even if currently disconnected).
    /// Uses last-seen metadata where available; falls back to role-based generic icons.
    func defaultIconName(for uid: String, isOutput: Bool) -> String {
        let name = knownDevices[uid] ?? uid
        let transport = knownDeviceTransportTypes[uid] ?? .unknown
        let iconBase = knownDeviceIconBaseNames[uid]
        let isApple = knownDeviceIsAppleMade[uid] ?? false
        let modelUID = knownDeviceModelUIDs[uid]
        let minorType = knownDeviceBluetoothMinorTypes[uid]

        // Prefer a best-effort inference rather than a blank/unknown icon.
        let device = AudioDevice(
            uid: uid,
            name: name,
            hasInput: !isOutput,
            hasOutput: isOutput,
            transportType: transport,
            iconBaseName: iconBase,
            modelUID: modelUID,
            isAppleMade: isApple,
            bluetoothMinorType: minorType
        )
        let inferred = device.deviceTypeSystemImage
        if inferred != "questionmark.circle" { return inferred }
        return isOutput ? "speaker.wave.2" : "mic"
    }

    func setIcon(_ symbol: String, for uid: String, isOutput: Bool) {
        var entry = deviceIcons[uid] ?? [:]
        entry[isOutput ? "output" : "input"] = symbol
        deviceIcons[uid] = entry
    }

    func clearIcon(for uid: String, isOutput: Bool) {
        deviceIcons[uid]?[isOutput ? "output" : "input"] = nil
        if deviceIcons[uid]?.isEmpty == true { deviceIcons.removeValue(forKey: uid) }
    }

    // MARK: – Priority management

    /// Appends device to priority list if not disabled and not already present.
    func registerDevice(
        uid: String,
        name: String,
        isOutput: Bool,
        transportType: AudioDevice.TransportType? = nil,
        iconBaseName: String? = nil,
        modelUID: String? = nil,
        isAppleMade: Bool? = nil,
        bluetoothMinorType: String? = nil
    ) {
        knownDevices[uid] = name
        if let transportType { knownDeviceTransportTypes[uid] = transportType }
        if let iconBaseName { knownDeviceIconBaseNames[uid] = iconBaseName }
        if let modelUID { knownDeviceModelUIDs[uid] = modelUID }
        if let isAppleMade { knownDeviceIsAppleMade[uid] = isAppleMade }
        if let bluetoothMinorType { knownDeviceBluetoothMinorTypes[uid] = bluetoothMinorType }

        let disabled = isOutput ? disabledOutputDevices : disabledInputDevices
        guard !disabled.contains(uid) else { return }
        let list = isOutput ? outputPriority : inputPriority
        guard !list.contains(uid) else { return }
        if isOutput { outputPriority.append(uid) }
        else { inputPriority.append(uid) }
    }

    func disableDevice(uid: String, isOutput: Bool) {
        if isOutput {
            outputPriority.removeAll { $0 == uid }
            disabledOutputDevices.insert(uid)
        } else {
            inputPriority.removeAll { $0 == uid }
            disabledInputDevices.insert(uid)
        }
    }

    /// Permanently removes a device from all lists, known devices, and memory.
    /// It will reappear automatically if it reconnects (registered fresh).
    func deleteDevice(uid: String) {
        outputPriority.removeAll { $0 == uid }
        inputPriority.removeAll { $0 == uid }
        disabledOutputDevices.remove(uid)
        disabledInputDevices.remove(uid)
        knownDevices.removeValue(forKey: uid)
        knownDeviceTransportTypes.removeValue(forKey: uid)
        knownDeviceIconBaseNames.removeValue(forKey: uid)
        knownDeviceIsAppleMade.removeValue(forKey: uid)
        knownDeviceModelUIDs.removeValue(forKey: uid)
        knownDeviceBluetoothMinorTypes.removeValue(forKey: uid)
        volumeMemory.removeValue(forKey: uid)
        deviceIcons.removeValue(forKey: uid)
        customDeviceNames.removeValue(forKey: uid)
    }

    func enableDevice(uid: String, isOutput: Bool) {
        if isOutput {
            disabledOutputDevices.remove(uid)
            if !outputPriority.contains(uid) { outputPriority.append(uid) }
        } else {
            disabledInputDevices.remove(uid)
            if !inputPriority.contains(uid) { inputPriority.append(uid) }
        }
    }

    // MARK: – Launch at login

    var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { print("Launch-at-login error: \(error)") }
    }

    // MARK: – Import / export

    struct ExportedSettings: Codable {
        var schemaVersion: Int
        var exportedAt: Date

        var outputPriority: [String]
        var inputPriority: [String]
        var disabledOutputDevices: [String]
        var disabledInputDevices: [String]

        var volumeMemory: [String: [String: Float]]
        var customDeviceNames: [String: [String: String]]
        var deviceIcons: [String: [String: String]]
        var knownDevices: [String: String]
        var knownDeviceTransportTypes: [String: AudioDevice.TransportType]?
        var knownDeviceIconBaseNames: [String: String]?
        var knownDeviceIsAppleMade: [String: Bool]?
        var knownDeviceModelUIDs: [String: String]?
        var knownDeviceBluetoothMinorTypes: [String: String]?

        var isAutoMode: Bool
        var hideMenuBarIcon: Bool
        var showInputLevelMeter: Bool?

        var testSound: AppSound?
        var alertSound: AppSound?
    }

    enum ImportExportError: LocalizedError {
        case invalidFile
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                "That file doesn’t look like a Sentrio settings export."
            case let .unsupportedSchema(v):
                "Unsupported settings schema version: \(v)."
            }
        }
    }

    func exportSettingsData() throws -> Data {
        let export = ExportedSettings(
            schemaVersion: 1,
            exportedAt: Date(),
            outputPriority: outputPriority,
            inputPriority: inputPriority,
            disabledOutputDevices: Array(disabledOutputDevices).sorted(),
            disabledInputDevices: Array(disabledInputDevices).sorted(),
            volumeMemory: volumeMemory,
            customDeviceNames: customDeviceNames,
            deviceIcons: deviceIcons,
            knownDevices: knownDevices,
            knownDeviceTransportTypes: knownDeviceTransportTypes,
            knownDeviceIconBaseNames: knownDeviceIconBaseNames,
            knownDeviceIsAppleMade: knownDeviceIsAppleMade,
            knownDeviceModelUIDs: knownDeviceModelUIDs,
            knownDeviceBluetoothMinorTypes: knownDeviceBluetoothMinorTypes,
            isAutoMode: isAutoMode,
            hideMenuBarIcon: hideMenuBarIcon,
            showInputLevelMeter: showInputLevelMeter,
            testSound: testSound,
            alertSound: alertSound
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(export)
    }

    func exportSettings(to url: URL) throws {
        let data = try exportSettingsData()
        try data.write(to: url, options: [.atomic])
    }

    func importSettings(from url: URL) throws {
        let data = try Data(contentsOf: url)
        try importSettings(from: data)
    }

    func importSettings(from data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let export: ExportedSettings
        do {
            export = try decoder.decode(ExportedSettings.self, from: data)
        } catch {
            throw ImportExportError.invalidFile
        }

        guard export.schemaVersion == 1 else {
            throw ImportExportError.unsupportedSchema(export.schemaVersion)
        }

        outputPriority = Self.deduped(export.outputPriority)
        inputPriority = Self.deduped(export.inputPriority)
        disabledOutputDevices = Set(export.disabledOutputDevices)
        disabledInputDevices = Set(export.disabledInputDevices)
        volumeMemory = export.volumeMemory
        customDeviceNames = export.customDeviceNames
        deviceIcons = export.deviceIcons
        knownDevices = export.knownDevices
        knownDeviceTransportTypes = export.knownDeviceTransportTypes ?? [:]
        knownDeviceIconBaseNames = export.knownDeviceIconBaseNames ?? [:]
        knownDeviceIsAppleMade = export.knownDeviceIsAppleMade ?? [:]
        knownDeviceModelUIDs = export.knownDeviceModelUIDs ?? [:]
        knownDeviceBluetoothMinorTypes = export.knownDeviceBluetoothMinorTypes ?? [:]
        isAutoMode = export.isAutoMode
        hideMenuBarIcon = export.hideMenuBarIcon
        showInputLevelMeter = export.showInputLevelMeter ?? true
        testSound = export.testSound ?? .defaultTestSound
        alertSound = export.alertSound ?? .defaultAlertSound
    }

    private static func deduped(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    // MARK: – Persistence

    private func save(_ key: String, _ value: some Encodable) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

// MARK: – UserDefaults helpers

private extension UserDefaults {
    func jsonStringArray(forKey key: String) -> [String]? {
        if let arr = array(forKey: key) as? [String] { return arr }
        return jsonDecode([String].self, forKey: key)
    }

    func jsonDecode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

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

    // MARK: – General

    @Published var isAutoMode: Bool {
        didSet { defaults.set(isAutoMode, forKey: "isAutoMode") }
    }

    @Published var hideMenuBarIcon: Bool {
        didSet { defaults.set(hideMenuBarIcon, forKey: "hideMenuBarIcon") }
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
        volumeMemory = defaults.jsonDecode([String: [String: Float]].self, forKey: "volumeMemory") ?? [:]
        deviceIcons = defaults.jsonDecode([String: [String: String]].self, forKey: "deviceIcons") ?? [:]
        customDeviceNames = defaults.jsonDecode([String: [String: String]].self, forKey: "customDeviceNames") ?? [:]
        knownDevices = defaults.jsonDecode([String: String].self, forKey: "knownDevices") ?? [:]
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
        ("speaker.wave.3", "Speaker (loud)"),
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
        // ── Apple devices ───────────────────────────────────────────
        ("homepod", "HomePod"),
        ("homepodmini", "HomePod mini"),
        ("iphone", "iPhone"),
        ("ipad", "iPad"),
        ("applewatch", "Apple Watch"),
        ("laptopcomputer", "MacBook"),
        ("macmini", "Mac mini"),
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
    func registerDevice(uid: String, name: String, isOutput: Bool) {
        knownDevices[uid] = name
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

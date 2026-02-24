import Combine
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    // MARK: – Priority lists (enabled devices, in order)

    @Published var outputPriority: [String] {
        didSet { normalizeAndPersistPriority(isOutput: true) }
    }

    @Published var inputPriority: [String] {
        didSet { normalizeAndPersistPriority(isOutput: false) }
    }

    // MARK: – Disabled device sets (not used as fallbacks)

    @Published var disabledOutputDevices: Set<String> {
        didSet { save("disabledOutputDevices", Array(disabledOutputDevices)) }
    }

    @Published var disabledInputDevices: Set<String> {
        didSet { save("disabledInputDevices", Array(disabledInputDevices)) }
    }

    // MARK: – Hidden-device restore anchors (uid → last known priority index)

    @Published var hiddenOutputPriorityPositions: [String: Int] {
        didSet { save("hiddenOutputPriorityPositions", hiddenOutputPriorityPositions) }
    }

    @Published var hiddenInputPriorityPositions: [String: Int] {
        didSet { save("hiddenInputPriorityPositions", hiddenInputPriorityPositions) }
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

    /// Model groups where "group by model" is explicitly disabled.
    /// Missing key means enabled (default).
    @Published var disabledModelGroupKeys: Set<String> {
        didSet { save("disabledModelGroupKeys", Array(disabledModelGroupKeys).sorted()) }
    }

    // MARK: – General

    /// App language override:
    /// - "system" → follow macOS language
    /// - otherwise → one of `L10n.supportedLocalizations`
    @Published var appLanguage: String {
        didSet {
            defaults.set(appLanguage, forKey: "appLanguage")
            L10n.overrideLocalization = appLanguage == "system" ? nil : appLanguage
        }
    }

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

    func resetFooterStats() {
        autoSwitchCount = 0
        millisecondsSaved = 0
        signalIntegrityScore = 0
    }

    // MARK: – Sounds

    @Published var testSound: AppSound {
        didSet { save("testSound", testSound) }
    }

    @Published var alertSound: AppSound {
        didSet { save("alertSound", alertSound) }
    }

    // MARK: – BusyLight

    @Published var busyLightEnabled: Bool {
        didSet { defaults.set(busyLightEnabled, forKey: "busyLightEnabled") }
    }

    @Published var busyLightControlMode: BusyLightControlMode {
        didSet { save("busyLightControlMode", busyLightControlMode) }
    }

    @Published var busyLightManualAction: BusyLightAction {
        didSet { save("busyLightManualAction", busyLightManualAction) }
    }

    @Published var busyLightAPIEnabled: Bool {
        didSet { defaults.set(busyLightAPIEnabled, forKey: "busyLightAPIEnabled") }
    }

    @Published var busyLightAPIPort: Int {
        didSet {
            let normalized = Self.normalizedBusyLightAPIPort(busyLightAPIPort)
            if normalized != busyLightAPIPort {
                busyLightAPIPort = normalized
                return
            }
            defaults.set(normalized, forKey: "busyLightAPIPort")
        }
    }

    @Published var busyLightRules: [BusyLightRule] {
        didSet { save("busyLightRules", busyLightRules) }
    }

    // MARK: – Storage

    private let defaults: UserDefaults
    private var isNormalizingPriority = false

    // MARK: – Init (injectable for testing)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        outputPriority = defaults.jsonStringArray(forKey: "outputPriority") ?? []
        inputPriority = defaults.jsonStringArray(forKey: "inputPriority") ?? []
        disabledOutputDevices = Set(defaults.jsonStringArray(forKey: "disabledOutputDevices") ?? [])
        disabledInputDevices = Set(defaults.jsonStringArray(forKey: "disabledInputDevices") ?? [])
        hiddenOutputPriorityPositions = defaults.jsonDecode([String: Int].self, forKey: "hiddenOutputPriorityPositions") ?? [:]
        hiddenInputPriorityPositions = defaults.jsonDecode([String: Int].self, forKey: "hiddenInputPriorityPositions") ?? [:]

        let storedLanguage = defaults.string(forKey: "appLanguage") ?? "system"
        if storedLanguage == "system" || L10n.supportedLocalizations.contains(storedLanguage) {
            appLanguage = storedLanguage
        } else {
            appLanguage = "system"
        }

        isAutoMode = defaults.object(forKey: "isAutoMode") as? Bool ?? true
        hideMenuBarIcon = defaults.object(forKey: "hideMenuBarIcon") as? Bool ?? false
        showInputLevelMeter = defaults.object(forKey: "showInputLevelMeter") as? Bool ?? false
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
        disabledModelGroupKeys = Set(defaults.jsonStringArray(forKey: "disabledModelGroupKeys") ?? [])
        testSound = defaults.jsonDecode(AppSound.self, forKey: "testSound") ?? .defaultTestSound
        alertSound = defaults.jsonDecode(AppSound.self, forKey: "alertSound") ?? .defaultAlertSound

        busyLightEnabled = defaults.object(forKey: "busyLightEnabled") as? Bool ?? false
        busyLightControlMode = defaults.string(forKey: "busyLightControlMode")
            .flatMap(BusyLightControlMode.init(rawValue:)) ?? .auto
        busyLightManualAction = defaults.jsonDecode(BusyLightAction.self, forKey: "busyLightManualAction") ?? .defaultBusy
        busyLightAPIEnabled = defaults.object(forKey: "busyLightAPIEnabled") as? Bool ?? false
        let storedBusyLightPort = defaults.object(forKey: "busyLightAPIPort") as? Int
        busyLightAPIPort = Self.normalizedBusyLightAPIPort(storedBusyLightPort ?? 47833)
        busyLightRules = defaults.jsonDecode([BusyLightRule].self, forKey: "busyLightRules") ?? BusyLightRule.defaultRules()
        outputPriority = normalizePriorityList(outputPriority)
        inputPriority = normalizePriorityList(inputPriority)

        // Property observers do not fire during init.
        L10n.overrideLocalization = appLanguage == "system" ? nil : appLanguage
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
    static let iconOptions: [(symbol: String, labelKey: String)] = [
        // ── Audio output ────────────────────────────────────────────
        ("speaker.wave.2", "icon.speaker"),
        ("speaker.wave.1", "icon.speakerQuiet"),
        ("speaker.wave.3", "icon.speakerLoud"),
        ("speaker.slash", "icon.muted"),
        ("hifispeaker", "icon.hiFiSpeaker"),
        ("waveform", "icon.waveform"),
        // ── Audio input ─────────────────────────────────────────────
        ("mic", "icon.microphone"),
        ("mic.fill", "icon.microphoneFilled"),
        ("ear", "icon.ear"),
        // ── Headphones / earbuds ────────────────────────────────────
        ("headphones", "icon.headphones"),
        ("earbuds", "icon.earpods"),
        ("airpodspro", "icon.airpodsPro"),
        ("airpods", "icon.airpods"),
        ("airpodsmax", "icon.airpodsMax"),
        // ── Apple devices ───────────────────────────────────────────
        ("homepod", "icon.homepod"),
        ("homepodmini", "icon.homepodMini"),
        ("iphone", "icon.iphone"),
        ("ipad", "icon.ipad"),
        ("applewatch", "icon.appleWatch"),
        ("laptopcomputer", "icon.macbook"),
        ("macmini", "icon.macMini"),
        ("desktopcomputer", "icon.imacDesktop"),
        ("appletv", "icon.appleTV"),
        ("display", "icon.displayMonitor"),
        // ── Music ───────────────────────────────────────────────────
        ("music.note", "icon.music"),
        // ── Connection / transport type ─────────────────────────────
        ("internaldrive", "icon.builtIn"),
        ("cable.connector", "icon.usb"),
        ("bolt", "icon.thunderbolt"),
        ("wave.3.right", "icon.wirelessBt"),
        ("airplayaudio", "icon.airPlay"),
        ("antenna.radiowaves.left.and.right", "icon.radio"),
        ("link", "icon.linkedAggregate"),
        ("waveform.path", "icon.virtual"),
        ("cpu", "icon.pciCpu"),
        ("questionmark.circle", "icon.unknown"),
    ]

    // MARK: – Custom device names

    /// The display name for a device in a given role.
    /// Priority: custom role name → known device name → provided fallback → inferred UID name → UID.
    func displayName(for uid: String, isOutput: Bool, fallbackName: String? = nil) -> String {
        if let custom = customDeviceNames[uid]?[isOutput ? "output" : "input"] {
            return custom
        }
        if let known = knownDevices[uid] {
            return known
        }
        if let fallback = fallbackName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fallback.isEmpty
        {
            return fallback
        }
        return Self.inferredDisplayName(fromUID: uid) ?? uid
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
        let key = isOutput ? "output" : "input"
        for target in groupedActionUIDs(for: uid) {
            var entry = deviceIcons[target] ?? [:]
            entry[key] = symbol
            deviceIcons[target] = entry
        }
    }

    func clearIcon(for uid: String, isOutput: Bool) {
        let key = isOutput ? "output" : "input"
        for target in groupedActionUIDs(for: uid) {
            deviceIcons[target]?[key] = nil
            if deviceIcons[target]?.isEmpty == true { deviceIcons.removeValue(forKey: target) }
        }
    }

    /// Reorders priority by moving the source device (or source group block)
    /// before the target device (or target group block).
    func movePriority(uid sourceUID: String, before targetUID: String, isOutput: Bool) {
        let list = isOutput ? outputPriority : inputPriority
        let reordered = Self.reorderedPriorityList(
            list,
            sourceUID: sourceUID,
            targetUID: targetUID,
            groupKeyForUID: { [weak self] uid in
                guard let self, isGroupByModelEnabled(for: uid) else { return nil }
                return modelGroupKey(for: uid)
            }
        )
        guard reordered != list else { return }
        if isOutput { outputPriority = reordered }
        else { inputPriority = reordered }
    }

    /// Reorders priority while dragging.
    /// If dragging downward, the source block is inserted after the target block.
    /// If dragging upward, the source block is inserted before the target block.
    func reorderPriorityForDrag(uid sourceUID: String, over targetUID: String, isOutput: Bool) {
        let list = isOutput ? outputPriority : inputPriority
        let reordered = Self.reorderedPriorityListForDrag(
            list,
            sourceUID: sourceUID,
            targetUID: targetUID,
            groupKeyForUID: { [weak self] uid in
                guard let self, isGroupByModelEnabled(for: uid) else { return nil }
                return modelGroupKey(for: uid)
            }
        )
        guard reordered != list else { return }
        if isOutput { outputPriority = reordered }
        else { inputPriority = reordered }
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
        synchronizeGroupIcons(for: uid)

        let disabled = isOutput ? disabledOutputDevices : disabledInputDevices
        guard !disabled.contains(uid) else { return }
        let list = isOutput ? outputPriority : inputPriority
        guard !list.contains(uid) else { return }
        if isOutput { outputPriority.append(uid) }
        else { inputPriority.append(uid) }
    }

    func disableDevice(uid: String, isOutput: Bool) {
        hideSingleDevice(uid: uid, isOutput: isOutput)
    }

    /// Hide device from auto-switching. When model grouping is enabled for this UID,
    /// hide applies to every device in that group across input and output roles.
    func hideDevice(uid: String, isOutput: Bool) {
        let targets = groupedActionUIDs(for: uid)
        if targets.count <= 1 {
            hideSingleDevice(uid: uid, isOutput: isOutput)
            return
        }
        for target in targets {
            hideSingleDevice(uid: target, isOutput: true)
            hideSingleDevice(uid: target, isOutput: false)
        }
    }

    /// Permanently removes a device from all lists, known devices, and memory.
    /// It will reappear automatically if it reconnects (registered fresh).
    func deleteDevice(uid: String) {
        let groupKey = modelGroupKey(for: uid)
        outputPriority.removeAll { $0 == uid }
        inputPriority.removeAll { $0 == uid }
        disabledOutputDevices.remove(uid)
        disabledInputDevices.remove(uid)
        hiddenOutputPriorityPositions.removeValue(forKey: uid)
        hiddenInputPriorityPositions.removeValue(forKey: uid)
        knownDevices.removeValue(forKey: uid)
        knownDeviceTransportTypes.removeValue(forKey: uid)
        knownDeviceIconBaseNames.removeValue(forKey: uid)
        knownDeviceIsAppleMade.removeValue(forKey: uid)
        knownDeviceModelUIDs.removeValue(forKey: uid)
        knownDeviceBluetoothMinorTypes.removeValue(forKey: uid)
        volumeMemory.removeValue(forKey: uid)
        deviceIcons.removeValue(forKey: uid)
        customDeviceNames.removeValue(forKey: uid)
        if let groupKey,
           !knownDevices.keys.contains(where: { modelGroupKey(for: $0) == groupKey })
        {
            disabledModelGroupKeys.remove(groupKey)
        }
    }

    func enableDevice(uid: String, isOutput: Bool) {
        if isOutput {
            disabledOutputDevices.remove(uid)
            insertWithStoredPriority(uid: uid, isOutput: true)
        } else {
            disabledInputDevices.remove(uid)
            insertWithStoredPriority(uid: uid, isOutput: false)
        }
    }

    /// Permanently removes disconnected devices. When grouping is active, removal applies
    /// to all disconnected members of that model group.
    func forgetDevice(uid: String, connectedUIDs: Set<String>) {
        for target in forgettableUIDs(for: uid, connectedUIDs: connectedUIDs) {
            deleteDevice(uid: target)
        }
    }

    func forgettableUIDs(for uid: String, connectedUIDs: Set<String>) -> [String] {
        groupedActionUIDs(for: uid).filter { !connectedUIDs.contains($0) }
    }

    func canForgetDevice(uid: String, connectedUIDs: Set<String>) -> Bool {
        !forgettableUIDs(for: uid, connectedUIDs: connectedUIDs).isEmpty
    }

    /// Default is enabled when a model key can be derived.
    func isGroupByModelEnabled(for uid: String) -> Bool {
        guard let key = modelGroupKey(for: uid) else { return false }
        return !disabledModelGroupKeys.contains(key)
    }

    func setGroupByModelEnabled(_ enabled: Bool, for uid: String) {
        guard let key = modelGroupKey(for: uid) else { return }
        if enabled {
            disabledModelGroupKeys.remove(key)
            synchronizeGroupIcons(for: uid)
        } else {
            disabledModelGroupKeys.insert(key)
        }
        normalizeAllPriorities()
    }

    /// Number of known devices that belong to the same model group as `uid`.
    /// Returns at least 1 when a model group key is available.
    func groupByModelDeviceCount(for uid: String) -> Int {
        guard let key = modelGroupKey(for: uid) else { return 0 }
        var members = Set(knownDevices.keys.filter { modelGroupKey(for: $0) == key })
        members.insert(uid)
        return members.count
    }

    func modelGroupKey(for uid: String) -> String? {
        if let transport = knownDeviceTransportTypes[uid], transport != .usb {
            return nil
        }
        if let key = Self.usbVendorProductGroupKey(fromUID: uid) { return key }
        guard let modelUID = knownDeviceModelUIDs[uid],
              let key = Self.usbVendorProductGroupKey(fromModelUID: modelUID)
        else { return nil }
        return key
    }

    private func groupedActionUIDs(for uid: String) -> [String] {
        guard isGroupByModelEnabled(for: uid), let key = modelGroupKey(for: uid) else { return [uid] }
        var targets = Set(knownDevices.keys.filter {
            modelGroupKey(for: $0) == key && isGroupByModelEnabled(for: $0)
        })
        targets.insert(uid)
        if targets.count <= 1 { return [uid] }
        return orderedUIDs(from: targets)
    }

    private func orderedUIDs(from uids: Set<String>) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for uid in outputPriority + inputPriority {
            guard uids.contains(uid), seen.insert(uid).inserted else { continue }
            ordered.append(uid)
        }
        for uid in knownDevices.keys.sorted() {
            guard uids.contains(uid), seen.insert(uid).inserted else { continue }
            ordered.append(uid)
        }
        return ordered
    }

    private func synchronizeGroupIcons(for uid: String) {
        let members = groupedActionUIDs(for: uid)
        guard members.count > 1 else { return }

        for key in ["output", "input"] {
            guard let symbol = members.compactMap({ deviceIcons[$0]?[key] }).first else { continue }
            for member in members {
                var entry = deviceIcons[member] ?? [:]
                guard entry[key] != symbol else { continue }
                entry[key] = symbol
                deviceIcons[member] = entry
            }
        }
    }

    private func hideSingleDevice(uid: String, isOutput: Bool) {
        if isOutput {
            if let index = outputPriority.firstIndex(of: uid) {
                hiddenOutputPriorityPositions[uid] = index
            }
            outputPriority.removeAll { $0 == uid }
            disabledOutputDevices.insert(uid)
        } else {
            if let index = inputPriority.firstIndex(of: uid) {
                hiddenInputPriorityPositions[uid] = index
            }
            inputPriority.removeAll { $0 == uid }
            disabledInputDevices.insert(uid)
        }
    }

    private func insertWithStoredPriority(uid: String, isOutput: Bool) {
        if isOutput {
            guard !outputPriority.contains(uid) else { return }
            let target = min(max(hiddenOutputPriorityPositions[uid] ?? outputPriority.count, 0), outputPriority.count)
            outputPriority.insert(uid, at: target)
            hiddenOutputPriorityPositions.removeValue(forKey: uid)
        } else {
            guard !inputPriority.contains(uid) else { return }
            let target = min(max(hiddenInputPriorityPositions[uid] ?? inputPriority.count, 0), inputPriority.count)
            inputPriority.insert(uid, at: target)
            hiddenInputPriorityPositions.removeValue(forKey: uid)
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
        var hiddenOutputDevices: [String]?
        var hiddenInputDevices: [String]?
        var disabledOutputDevices: [String]?
        var disabledInputDevices: [String]?
        var hiddenOutputPriorityPositions: [String: Int]?
        var hiddenInputPriorityPositions: [String: Int]?

        var volumeMemory: [String: [String: Float]]
        var customDeviceNames: [String: [String: String]]
        var deviceIcons: [String: [String: String]]
        var knownDevices: [String: String]
        var knownDeviceTransportTypes: [String: AudioDevice.TransportType]?
        var knownDeviceIconBaseNames: [String: String]?
        var knownDeviceIsAppleMade: [String: Bool]?
        var knownDeviceModelUIDs: [String: String]?
        var knownDeviceBluetoothMinorTypes: [String: String]?
        var disabledModelGroupKeys: [String]?
        var groupByModelEnabledByGroup: [String: Bool]?

        var appLanguage: String?
        var isAutoMode: Bool
        var hideMenuBarIcon: Bool
        var showInputLevelMeter: Bool?

        var testSound: AppSound?
        var alertSound: AppSound?

        var busyLightEnabled: Bool?
        var busyLightRulesEnabled: Bool?
        var busyLightControlMode: BusyLightControlMode?
        var busyLightManualAction: BusyLightAction?
        var busyLightAPIEnabled: Bool?
        var busyLightAPIPort: Int?
        var busyLightRules: [BusyLightRule]?
    }

    enum ImportExportError: LocalizedError {
        case invalidFile
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .invalidFile:
                L10n.tr("error.importExport.invalidFile")
            case let .unsupportedSchema(v):
                L10n.format("error.importExport.unsupportedSchemaFormat", v)
            }
        }
    }

    func exportSettingsData() throws -> Data {
        let export = ExportedSettings(
            schemaVersion: 5,
            exportedAt: Date(),
            outputPriority: outputPriority,
            inputPriority: inputPriority,
            hiddenOutputDevices: Array(disabledOutputDevices).sorted(),
            hiddenInputDevices: Array(disabledInputDevices).sorted(),
            disabledOutputDevices: nil,
            disabledInputDevices: nil,
            hiddenOutputPriorityPositions: hiddenOutputPriorityPositions,
            hiddenInputPriorityPositions: hiddenInputPriorityPositions,
            volumeMemory: volumeMemory,
            customDeviceNames: customDeviceNames,
            deviceIcons: deviceIcons,
            knownDevices: knownDevices,
            knownDeviceTransportTypes: knownDeviceTransportTypes,
            knownDeviceIconBaseNames: knownDeviceIconBaseNames,
            knownDeviceIsAppleMade: knownDeviceIsAppleMade,
            knownDeviceModelUIDs: knownDeviceModelUIDs,
            knownDeviceBluetoothMinorTypes: knownDeviceBluetoothMinorTypes,
            disabledModelGroupKeys: Array(disabledModelGroupKeys).sorted(),
            groupByModelEnabledByGroup: exportGroupByModelEnabledByGroup(),
            appLanguage: appLanguage,
            isAutoMode: isAutoMode,
            hideMenuBarIcon: hideMenuBarIcon,
            showInputLevelMeter: showInputLevelMeter,
            testSound: testSound,
            alertSound: alertSound,
            busyLightEnabled: busyLightEnabled,
            busyLightRulesEnabled: busyLightControlMode == .auto,
            busyLightControlMode: busyLightControlMode,
            busyLightManualAction: busyLightManualAction,
            busyLightAPIEnabled: busyLightAPIEnabled,
            busyLightAPIPort: busyLightAPIPort,
            busyLightRules: busyLightRules
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

        guard (1 ... 5).contains(export.schemaVersion) else {
            throw ImportExportError.unsupportedSchema(export.schemaVersion)
        }

        outputPriority = Self.deduped(export.outputPriority)
        inputPriority = Self.deduped(export.inputPriority)
        let importedHiddenOutputDevices = export.hiddenOutputDevices ?? export.disabledOutputDevices ?? []
        let importedHiddenInputDevices = export.hiddenInputDevices ?? export.disabledInputDevices ?? []
        disabledOutputDevices = Set(importedHiddenOutputDevices)
        disabledInputDevices = Set(importedHiddenInputDevices)
        hiddenOutputPriorityPositions = export.hiddenOutputPriorityPositions ?? [:]
        hiddenInputPriorityPositions = export.hiddenInputPriorityPositions ?? [:]
        volumeMemory = export.volumeMemory
        customDeviceNames = export.customDeviceNames
        deviceIcons = export.deviceIcons
        knownDevices = export.knownDevices
        knownDeviceTransportTypes = export.knownDeviceTransportTypes ?? [:]
        knownDeviceIconBaseNames = export.knownDeviceIconBaseNames ?? [:]
        knownDeviceIsAppleMade = export.knownDeviceIsAppleMade ?? [:]
        knownDeviceModelUIDs = export.knownDeviceModelUIDs ?? [:]
        knownDeviceBluetoothMinorTypes = export.knownDeviceBluetoothMinorTypes ?? [:]
        var importedDisabledModelGroupKeys = Set(export.disabledModelGroupKeys ?? [])
        if let explicitGroupMap = export.groupByModelEnabledByGroup {
            for (key, isEnabled) in explicitGroupMap {
                if isEnabled {
                    importedDisabledModelGroupKeys.remove(key)
                } else {
                    importedDisabledModelGroupKeys.insert(key)
                }
            }
        }
        disabledModelGroupKeys = importedDisabledModelGroupKeys

        let importedLanguage = export.appLanguage ?? "system"
        if importedLanguage == "system" || L10n.supportedLocalizations.contains(importedLanguage) {
            appLanguage = importedLanguage
        } else {
            appLanguage = "system"
        }

        isAutoMode = export.isAutoMode
        hideMenuBarIcon = export.hideMenuBarIcon
        showInputLevelMeter = export.showInputLevelMeter ?? false
        testSound = export.testSound ?? .defaultTestSound
        alertSound = export.alertSound ?? .defaultAlertSound

        busyLightEnabled = export.busyLightEnabled ?? false
        if let importedMode = export.busyLightControlMode {
            busyLightControlMode = importedMode
        } else {
            busyLightControlMode = (export.busyLightRulesEnabled ?? true) ? .auto : .manual
        }
        busyLightManualAction = export.busyLightManualAction ?? .defaultBusy
        busyLightAPIEnabled = export.busyLightAPIEnabled ?? false
        busyLightAPIPort = Self.normalizedBusyLightAPIPort(export.busyLightAPIPort ?? 47833)
        busyLightRules = export.busyLightRules ?? BusyLightRule.defaultRules()
        outputPriority = normalizePriorityList(outputPriority)
        inputPriority = normalizePriorityList(inputPriority)
    }

    private func normalizeAndPersistPriority(isOutput: Bool) {
        if isNormalizingPriority {
            save(isOutput ? "outputPriority" : "inputPriority", isOutput ? outputPriority : inputPriority)
            return
        }
        let current = isOutput ? outputPriority : inputPriority
        let normalized = normalizePriorityList(current)
        if normalized != current {
            isNormalizingPriority = true
            if isOutput { outputPriority = normalized }
            else { inputPriority = normalized }
            isNormalizingPriority = false
            return
        }
        save(isOutput ? "outputPriority" : "inputPriority", current)
    }

    private func normalizeAllPriorities() {
        let normalizedOutput = normalizePriorityList(outputPriority)
        let normalizedInput = normalizePriorityList(inputPriority)
        guard normalizedOutput != outputPriority || normalizedInput != inputPriority else { return }
        isNormalizingPriority = true
        outputPriority = normalizedOutput
        inputPriority = normalizedInput
        isNormalizingPriority = false
    }

    private func normalizePriorityList(_ items: [String]) -> [String] {
        let deduped = Self.deduped(items)
        var result: [String] = []
        var consumed = Set<String>()

        for uid in deduped {
            guard consumed.insert(uid).inserted else { continue }
            guard isGroupByModelEnabled(for: uid), let groupKey = modelGroupKey(for: uid) else {
                result.append(uid)
                continue
            }
            let members = deduped.filter {
                !consumed.contains($0) &&
                    isGroupByModelEnabled(for: $0) &&
                    modelGroupKey(for: $0) == groupKey
            }
            result.append(uid)
            for member in members {
                consumed.insert(member)
                result.append(member)
            }
        }
        return result
    }

    private static func reorderedPriorityList(
        _ list: [String],
        sourceUID: String,
        targetUID: String,
        groupKeyForUID: (String) -> String?
    ) -> [String] {
        guard sourceUID != targetUID else { return list }
        guard list.contains(sourceUID), list.contains(targetUID) else { return list }

        let sourceBlock = block(for: sourceUID, in: list, groupKeyForUID: groupKeyForUID)
        let targetBlock = block(for: targetUID, in: list, groupKeyForUID: groupKeyForUID)
        guard !sourceBlock.isEmpty, !targetBlock.isEmpty else { return list }
        guard Set(sourceBlock) != Set(targetBlock) else { return list }

        let sourceSet = Set(sourceBlock)
        var withoutSource = list.filter { !sourceSet.contains($0) }
        guard let targetHead = targetBlock.first,
              let targetInsertIndex = withoutSource.firstIndex(of: targetHead)
        else { return list }

        withoutSource.insert(contentsOf: sourceBlock, at: targetInsertIndex)
        return withoutSource
    }

    private static func reorderedPriorityListForDrag(
        _ list: [String],
        sourceUID: String,
        targetUID: String,
        groupKeyForUID: (String) -> String?
    ) -> [String] {
        guard sourceUID != targetUID else { return list }
        guard list.contains(sourceUID), list.contains(targetUID) else { return list }

        let sourceBlock = block(for: sourceUID, in: list, groupKeyForUID: groupKeyForUID)
        let targetBlock = block(for: targetUID, in: list, groupKeyForUID: groupKeyForUID)
        guard !sourceBlock.isEmpty, !targetBlock.isEmpty else { return list }
        guard Set(sourceBlock) != Set(targetBlock) else { return list }

        guard let sourceHead = sourceBlock.first,
              let targetHead = targetBlock.first,
              let sourceHeadIndex = list.firstIndex(of: sourceHead),
              let targetHeadIndex = list.firstIndex(of: targetHead)
        else { return list }

        let movingDown = sourceHeadIndex < targetHeadIndex

        let sourceSet = Set(sourceBlock)
        var withoutSource = list.filter { !sourceSet.contains($0) }

        let insertIndex: Int
        if movingDown {
            guard let targetTail = targetBlock.last,
                  let tailIndex = withoutSource.firstIndex(of: targetTail)
            else { return list }
            insertIndex = tailIndex + 1
        } else {
            guard let headIndex = withoutSource.firstIndex(of: targetHead) else { return list }
            insertIndex = headIndex
        }

        withoutSource.insert(contentsOf: sourceBlock, at: insertIndex)
        return withoutSource
    }

    private static func block(
        for uid: String,
        in list: [String],
        groupKeyForUID: (String) -> String?
    ) -> [String] {
        guard let key = groupKeyForUID(uid) else { return [uid] }
        let members = list.filter { groupKeyForUID($0) == key }
        return members.isEmpty ? [uid] : members
    }

    private static func usbVendorProductGroupKey(fromUID uid: String) -> String? {
        let parts = uid.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "AppleUSBAudioEngine" else { return nil }
        let vendor = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let product = parts[2].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !vendor.isEmpty, !product.isEmpty else { return nil }
        return "usbname:\(vendor):\(product)"
    }

    private static func usbVendorProductGroupKey(fromModelUID modelUID: String) -> String? {
        let parts = modelUID.split(separator: ":")
        guard parts.count >= 3 else { return nil }
        let vendor = String(parts[parts.count - 2]).lowercased()
        let product = String(parts[parts.count - 1]).lowercased()
        guard Self.isHex(vendor), Self.isHex(product) else { return nil }
        return "usbid:\(vendor):\(product)"
    }

    private static func isHex(_ value: String) -> Bool {
        let hex = CharacterSet(charactersIn: "0123456789abcdef")
        return !value.isEmpty && value.unicodeScalars.allSatisfy { hex.contains($0) }
    }

    private static func inferredDisplayName(fromUID uid: String) -> String? {
        let parts = uid.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "AppleUSBAudioEngine" else { return nil }
        let product = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
        return product.isEmpty ? nil : product
    }

    private static func deduped(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private static func normalizedBusyLightAPIPort(_ port: Int) -> Int {
        min(max(port, 1024), 65535)
    }

    // MARK: – Persistence

    private func save(_ key: String, _ value: some Encodable) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private func exportGroupByModelEnabledByGroup() -> [String: Bool] {
        var keys = Set<String>()
        for uid in knownDevices.keys {
            if let key = modelGroupKey(for: uid) {
                keys.insert(key)
            }
        }
        guard !keys.isEmpty else { return [:] }

        var map: [String: Bool] = [:]
        for key in keys {
            map[key] = !disabledModelGroupKeys.contains(key)
        }
        return map
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

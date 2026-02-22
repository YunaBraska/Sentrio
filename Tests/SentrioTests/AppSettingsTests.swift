@testable import SentrioCore
import XCTest

final class AppSettingsTests: XCTestCase {
    var settings: AppSettings!
    var suiteName: String!

    override func setUp() {
        suiteName = "SentrioTests.\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        settings = nil
    }

    // MARK: – Defaults

    func test_autoModeDefaultIsTrue() {
        XCTAssertTrue(settings.isAutoMode)
    }

    func test_hideMenuBarIconDefaultIsFalse() {
        XCTAssertFalse(settings.hideMenuBarIcon)
    }

    func test_priorityListsStartEmpty() {
        XCTAssertTrue(settings.outputPriority.isEmpty)
    }

    // MARK: – registerDevice

    func test_registerAddsToCorrectList() {
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        settings.registerDevice(uid: "M", name: "Mic M", isOutput: false)
        XCTAssertTrue(settings.outputPriority.contains("A"))
        XCTAssertTrue(settings.inputPriority.contains("M"))
        XCTAssertFalse(settings.inputPriority.contains("A"))
        XCTAssertFalse(settings.outputPriority.contains("M"))
    }

    func test_registerDoesNotDuplicate() {
        settings.registerDevice(uid: "A", name: "X", isOutput: true)
        settings.registerDevice(uid: "A", name: "X", isOutput: true)
        XCTAssertEqual(settings.outputPriority.filter { $0 == "A" }.count, 1)
    }

    func test_registerAppendsInOrder() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.registerDevice(uid: "B", name: "B", isOutput: true)
        settings.registerDevice(uid: "C", name: "C", isOutput: true)
        XCTAssertEqual(settings.outputPriority, ["A", "B", "C"])
    }

    func test_registerUpdatesName() {
        settings.registerDevice(uid: "A", name: "Old", isOutput: true)
        settings.registerDevice(uid: "A", name: "New", isOutput: true)
        XCTAssertEqual(settings.knownDevices["A"], "New")
    }

    // MARK: – disableDevice / enableDevice

    func test_disableRemovesFromPriorityAndAddsToDisabled() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.disableDevice(uid: "A", isOutput: true)
        XCTAssertFalse(settings.outputPriority.contains("A"))
        XCTAssertTrue(settings.disabledOutputDevices.contains("A"))
    }

    func test_disabledDeviceNotReaddedOnRegister() {
        settings.disableDevice(uid: "A", isOutput: true)
        settings.knownDevices["A"] = "Speaker A"
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        XCTAssertFalse(settings.outputPriority.contains("A"),
                       "Disabled device must not re-enter priority list via registerDevice")
    }

    func test_enableMovesFromDisabledToPriority() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.disableDevice(uid: "A", isOutput: true)
        settings.enableDevice(uid: "A", isOutput: true)
        XCTAssertTrue(settings.outputPriority.contains("A"))
        XCTAssertFalse(settings.disabledOutputDevices.contains("A"))
    }

    func test_enableDoesNotDuplicateInPriority() {
        settings.outputPriority = ["A", "B"]
        settings.disabledOutputDevices = ["A"] // Simulate inconsistent state
        settings.enableDevice(uid: "A", isOutput: true)
        XCTAssertEqual(settings.outputPriority.filter { $0 == "A" }.count, 1)
    }

    func test_disableInputDoesNotAffectOutput() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.registerDevice(uid: "A", name: "A", isOutput: false)
        settings.disableDevice(uid: "A", isOutput: false)
        XCTAssertTrue(settings.outputPriority.contains("A"), "Output list must be unaffected")
        XCTAssertTrue(settings.disabledInputDevices.contains("A"))
    }

    // MARK: – Volume memory

    func test_saveAndRetrieveOutputVolume() {
        settings.saveVolume(0.75, for: "A", isOutput: true)
        XCTAssertEqual(settings.savedVolume(for: "A", isOutput: true) ?? 0, 0.75, accuracy: 0.001)
    }

    func test_inputAndOutputVolumeStoredSeparately() {
        settings.saveVolume(0.8, for: "A", isOutput: true)
        settings.saveVolume(0.3, for: "A", isOutput: false)
        XCTAssertEqual(settings.savedVolume(for: "A", isOutput: true) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(settings.savedVolume(for: "A", isOutput: false) ?? 0, 0.3, accuracy: 0.001)
    }

    func test_alertVolumeStoredSeparately() {
        settings.saveVolume(0.8, for: "A", isOutput: true)
        settings.saveAlertVolume(0.4, for: "A")
        XCTAssertEqual(settings.savedVolume(for: "A", isOutput: true) ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(settings.savedAlertVolume(for: "A") ?? 0, 0.4, accuracy: 0.001)
    }

    func test_savedVolumeReturnsNilForUnknown() {
        XCTAssertNil(settings.savedVolume(for: "X", isOutput: true))
    }

    func test_savedAlertVolumeReturnsNilForUnknown() {
        XCTAssertNil(settings.savedAlertVolume(for: "X"))
    }

    // MARK: – Per-device icons

    func test_setAndGetCustomIcon() {
        let device = AudioDevice(uid: "A", name: "Test", hasInput: false, hasOutput: true)
        settings.setIcon("mic", for: "A", isOutput: true)
        XCTAssertEqual(settings.iconName(for: device, isOutput: true), "mic")
    }

    func test_clearIconFallsBackToDeviceType() {
        let device = AudioDevice(uid: "A", name: "AirPods Pro", hasInput: true, hasOutput: true)
        settings.setIcon("mic", for: "A", isOutput: true)
        settings.clearIcon(for: "A", isOutput: true)
        // Should now return the auto-detected icon for AirPods Pro
        XCTAssertEqual(settings.iconName(for: device, isOutput: true), device.deviceTypeSystemImage)
    }

    func test_inputAndOutputIconsStoredSeparately() {
        settings.setIcon("mic", for: "A", isOutput: false)
        settings.setIcon("speaker.wave.2", for: "A", isOutput: true)
        let d = AudioDevice(uid: "A", name: "X", hasInput: true, hasOutput: true)
        XCTAssertEqual(settings.iconName(for: d, isOutput: false), "mic")
        XCTAssertEqual(settings.iconName(for: d, isOutput: true), "speaker.wave.2")
    }

    // MARK: – hideMenuBarIcon

    func test_hideMenuBarIconCanBeToggled() {
        settings.hideMenuBarIcon = true
        XCTAssertTrue(settings.hideMenuBarIcon)
        settings.hideMenuBarIcon = false
        XCTAssertFalse(settings.hideMenuBarIcon)
    }

    func test_hideMenuBarIconPublishesChange() {
        var count = 0
        let c = settings.objectWillChange.sink { count += 1 }
        settings.hideMenuBarIcon = true
        XCTAssertGreaterThan(count, 0, "objectWillChange must fire when hideMenuBarIcon changes")
        c.cancel()
    }

    // MARK: – Persistence round-trip

    func test_settingsPersistAcrossReinit() throws {
        settings.registerDevice(uid: "X", name: "Device X", isOutput: true)
        settings.saveVolume(0.65, for: "X", isOutput: true)
        settings.saveAlertVolume(0.3, for: "X")
        settings.isAutoMode = false
        settings.hideMenuBarIcon = true
        settings.disableDevice(uid: "X", isOutput: true)
        settings.setIcon("mic", for: "X", isOutput: true)

        let s2 = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(s2.knownDevices["X"], "Device X")
        XCTAssertEqual(s2.savedVolume(for: "X", isOutput: true) ?? 0, 0.65, accuracy: 0.001)
        XCTAssertEqual(s2.savedAlertVolume(for: "X") ?? 0, 0.3, accuracy: 0.001)
        XCTAssertFalse(s2.isAutoMode)
        XCTAssertTrue(s2.hideMenuBarIcon)
        XCTAssertTrue(s2.disabledOutputDevices.contains("X"))
        XCTAssertEqual(s2.deviceIcons["X"]?["output"], "mic")
    }

    // MARK: – deleteDevice

    func test_deleteRemovesFromPriorityAndKnown() {
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        settings.deleteDevice(uid: "A")
        XCTAssertFalse(settings.outputPriority.contains("A"))
        XCTAssertNil(settings.knownDevices["A"])
    }

    func test_deleteRemovesVolumeMemoryAndIcons() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.saveVolume(0.7, for: "A", isOutput: true)
        settings.setIcon("mic", for: "A", isOutput: true)
        settings.deleteDevice(uid: "A")
        XCTAssertNil(settings.volumeMemory["A"])
        XCTAssertNil(settings.deviceIcons["A"])
    }

    func test_deleteDisabledDeviceClearsDisabledSet() {
        settings.registerDevice(uid: "A", name: "A", isOutput: true)
        settings.disableDevice(uid: "A", isOutput: true)
        settings.deleteDevice(uid: "A")
        XCTAssertFalse(settings.disabledOutputDevices.contains("A"))
        XCTAssertNil(settings.knownDevices["A"])
    }

    func test_deleteInputDevice() {
        settings.registerDevice(uid: "M", name: "Mic", isOutput: false)
        settings.deleteDevice(uid: "M")
        XCTAssertFalse(settings.inputPriority.contains("M"))
        XCTAssertNil(settings.knownDevices["M"])
    }

    func test_deleteNonExistentDeviceIsNoop() {
        XCTAssertNoThrow(settings.deleteDevice(uid: "nonexistent"))
    }

    // MARK: – Disabled row icon fallback (mirrors DisabledRow.iconName logic)

    func test_disabledDeviceRetainsCustomIconAfterDisable() {
        // Custom icon set before disable must still be readable for the disabled row
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        settings.setIcon("hifispeaker", for: "A", isOutput: true)
        settings.disableDevice(uid: "A", isOutput: true)
        XCTAssertEqual(settings.deviceIcons["A"]?["output"], "hifispeaker",
                       "Custom icon must survive disableDevice()")
    }

    func test_disabledDeviceIconClearedOnDelete() {
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        settings.setIcon("hifispeaker", for: "A", isOutput: true)
        settings.disableDevice(uid: "A", isOutput: true)
        settings.deleteDevice(uid: "A")
        XCTAssertNil(settings.deviceIcons["A"],
                     "deleteDevice must remove icons so disabled-row icon lookup returns nil")
    }

    func test_disabledDeviceWithNoStoredIconFallsBackToNil() {
        // Device with no custom icon → deviceIcons[uid] should be nil → UI falls back to generic
        settings.registerDevice(uid: "B", name: "Generic Speaker", isOutput: true)
        settings.disableDevice(uid: "B", isOutput: true)
        XCTAssertNil(settings.deviceIcons["B"],
                     "Devices without a custom icon must not have a deviceIcons entry")
    }

    // MARK: – Icon options integrity

    func test_iconOptionsHaveUniqueSymbols() {
        let symbols = AppSettings.iconOptions.map(\.symbol)
        XCTAssertEqual(symbols.count, Set(symbols).count, "Duplicate symbols found in iconOptions")
    }

    func test_iconOptionsAllNonEmpty() {
        for opt in AppSettings.iconOptions {
            XCTAssertFalse(opt.symbol.isEmpty, "Empty symbol in iconOptions")
            XCTAssertFalse(opt.label.isEmpty, "Empty label for symbol '\(opt.symbol)'")
        }
    }

    func test_iconNameFallsBackToDeviceTypeWhenNoCustom() {
        let device = AudioDevice(uid: "X", name: "AirPods Pro", hasInput: true, hasOutput: true)
        XCTAssertEqual(settings.iconName(for: device, isOutput: true), "airpodspro")
    }

    func test_customIconOverridesDeviceType() {
        let device = AudioDevice(uid: "X", name: "AirPods Pro", hasInput: true, hasOutput: true)
        settings.setIcon("headphones", for: "X", isOutput: true)
        XCTAssertEqual(settings.iconName(for: device, isOutput: true), "headphones")
    }

    func test_clearIconRestoresDeviceTypeIcon() {
        let device = AudioDevice(uid: "X", name: "AirPods Pro", hasInput: true, hasOutput: true)
        settings.setIcon("headphones", for: "X", isOutput: true)
        settings.clearIcon(for: "X", isOutput: true)
        XCTAssertEqual(settings.iconName(for: device, isOutput: true), "airpodspro")
    }

    // MARK: – Custom device names

    func test_displayNameFallsBackToKnownDevice() {
        settings.knownDevices["A"] = "My Speaker"
        XCTAssertEqual(settings.displayName(for: "A", isOutput: true), "My Speaker")
    }

    func test_displayNameFallsBackToUID() {
        XCTAssertEqual(settings.displayName(for: "uid-xyz", isOutput: true), "uid-xyz")
    }

    func test_customNameOverridesKnownName() {
        settings.knownDevices["A"] = "My Speaker"
        settings.setCustomName("Studio Monitor", for: "A", isOutput: true)
        XCTAssertEqual(settings.displayName(for: "A", isOutput: true), "Studio Monitor")
    }

    func test_customNameIsRoleSpecific() {
        settings.setCustomName("Studio Out", for: "A", isOutput: true)
        settings.setCustomName("USB Mic In", for: "A", isOutput: false)
        XCTAssertEqual(settings.displayName(for: "A", isOutput: true), "Studio Out")
        XCTAssertEqual(settings.displayName(for: "A", isOutput: false), "USB Mic In")
    }

    func test_clearCustomNameRestoresKnownName() {
        settings.knownDevices["A"] = "My Speaker"
        settings.setCustomName("Custom", for: "A", isOutput: true)
        settings.clearCustomName(for: "A", isOutput: true)
        XCTAssertEqual(settings.displayName(for: "A", isOutput: true), "My Speaker")
    }

    func test_setEmptyCustomNameActsAsClear() {
        settings.knownDevices["A"] = "My Speaker"
        settings.setCustomName("Custom", for: "A", isOutput: true)
        settings.setCustomName("   ", for: "A", isOutput: true) // whitespace-only
        XCTAssertEqual(settings.displayName(for: "A", isOutput: true), "My Speaker")
    }

    func test_deleteDeviceRemovesCustomNames() {
        settings.setCustomName("Custom Out", for: "A", isOutput: true)
        settings.setCustomName("Custom In", for: "A", isOutput: false)
        settings.deleteDevice(uid: "A")
        XCTAssertNil(settings.customDeviceNames["A"])
    }

    func test_customNamesPersistedAcrossReinit() throws {
        settings.setCustomName("My AirPods", for: "X", isOutput: true)
        let s2 = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(s2.displayName(for: "X", isOutput: true), "My AirPods")
    }

    // MARK: – Auto mode default

    func test_isAutoModeDefaultTrue() {
        XCTAssertTrue(settings.isAutoMode)
    }

    // MARK: – Priority reordering

    func test_movingPriorityChangesOrder() {
        settings.outputPriority = ["A", "B", "C"]
        settings.outputPriority.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(settings.outputPriority, ["C", "A", "B"])
    }
}

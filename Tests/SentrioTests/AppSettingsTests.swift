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

    func test_appLanguageDefaultIsSystem() {
        XCTAssertEqual(settings.appLanguage, "system")
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

    func test_hideThenEnableRestoresNearestPriorityPosition() {
        settings.outputPriority = ["A", "B", "C"]
        settings.hideDevice(uid: "B", isOutput: true)
        XCTAssertEqual(settings.outputPriority, ["A", "C"])

        settings.enableDevice(uid: "B", isOutput: true)
        XCTAssertEqual(settings.outputPriority, ["A", "B", "C"])
    }

    func test_groupByModelDefaultEnabledForUSBUID() {
        let uid = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        settings.registerDevice(uid: uid, name: "Shure MV7+", isOutput: true, transportType: .usb)

        XCTAssertNotNil(settings.modelGroupKey(for: uid))
        XCTAssertTrue(settings.isGroupByModelEnabled(for: uid))
    }

    func test_groupedDevicesAreKeptAdjacentInPriority() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"
        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: true, transportType: .usb)

        settings.outputPriority = [a, "X", b, "Y"]
        XCTAssertEqual(settings.outputPriority, [a, b, "X", "Y"])
    }

    func test_hideDeviceWithGroupingHidesWholeGroupAcrossRoles() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"

        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: false, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: false, transportType: .usb)

        settings.hideDevice(uid: a, isOutput: true)

        XCTAssertTrue(settings.disabledOutputDevices.contains(a))
        XCTAssertTrue(settings.disabledOutputDevices.contains(b))
        XCTAssertTrue(settings.disabledInputDevices.contains(a))
        XCTAssertTrue(settings.disabledInputDevices.contains(b))
        XCTAssertFalse(settings.outputPriority.contains(a))
        XCTAssertFalse(settings.outputPriority.contains(b))
        XCTAssertFalse(settings.inputPriority.contains(a))
        XCTAssertFalse(settings.inputPriority.contains(b))
    }

    func test_forgetDeviceWithGroupingDeletesOnlyDisconnectedMembers() {
        let connected = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let disconnected = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"
        settings.registerDevice(uid: connected, name: "Shure MV7+ A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: disconnected, name: "Shure MV7+ B", isOutput: true, transportType: .usb)

        settings.forgetDevice(uid: connected, connectedUIDs: [connected])

        XCTAssertNotNil(settings.knownDevices[connected])
        XCTAssertNil(settings.knownDevices[disconnected])
    }

    func test_setIconSyncsAcrossGroupedDevices() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"
        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: false, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: false, transportType: .usb)

        settings.setIcon("mic", for: a, isOutput: false)

        XCTAssertEqual(settings.deviceIcons[a]?["input"], "mic")
        XCTAssertEqual(settings.deviceIcons[b]?["input"], "mic")
    }

    func test_clearIconSyncsAcrossGroupedDevices() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"
        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: false, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: false, transportType: .usb)
        settings.setIcon("mic", for: a, isOutput: false)

        settings.clearIcon(for: b, isOutput: false)

        XCTAssertNil(settings.deviceIcons[a]?["input"])
        XCTAssertNil(settings.deviceIcons[b]?["input"])
    }

    func test_registerDeviceCopiesGroupedIconFromExistingPeer() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:MV7+#12-aad43524b65c6b5e856dfe9c14610cf7:2,3"
        settings.registerDevice(uid: a, name: "Shure MV7+ A", isOutput: false, transportType: .usb)
        settings.setIcon("mic", for: a, isOutput: false)

        settings.registerDevice(uid: b, name: "Shure MV7+ B", isOutput: false, transportType: .usb)

        XCTAssertEqual(settings.deviceIcons[b]?["input"], "mic")
    }

    func test_displayNameUsesFallbackNameForUnknownUID() {
        let uid = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        XCTAssertEqual(
            settings.displayName(for: uid, isOutput: false, fallbackName: "Shure MV7+"),
            "Shure MV7+"
        )
    }

    func test_hiddenDeviceCanSetIcon() {
        let uid = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        settings.registerDevice(uid: uid, name: "Shure MV7+", isOutput: false, transportType: .usb)
        settings.hideDevice(uid: uid, isOutput: false)

        settings.setIcon("mic", for: uid, isOutput: false)

        XCTAssertEqual(settings.deviceIcons[uid]?["input"], "mic")
    }

    func test_movePriorityMovesWholeGroupBlockForThreeMembers() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        let c = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:C:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: c, name: "Shure C", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, c, "X", "Y"]

        settings.movePriority(uid: b, before: "Y", isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["X", a, b, c, "Y"])
    }

    func test_movePriorityInsertsBeforeTargetGroupHead() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        let c = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:C:2,3"
        let x1 = "AppleUSBAudioEngine:Other Vendor:Other Device:X1:2,3"
        let x2 = "AppleUSBAudioEngine:Other Vendor:Other Device:X2:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: c, name: "Shure C", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: x1, name: "Other 1", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: x2, name: "Other 2", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, c, "Z", x1, x2]

        settings.movePriority(uid: c, before: x2, isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["Z", a, b, c, x1, x2])
    }

    func test_movePriorityWithSourceTargetInSameGroupIsNoop() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, "X"]

        settings.movePriority(uid: a, before: b, isOutput: true)

        XCTAssertEqual(settings.outputPriority, [a, b, "X"])
    }

    func test_movePriorityWithMissingSourceIsNoop() {
        settings.outputPriority = ["A", "B", "C"]

        settings.movePriority(uid: "missing", before: "B", isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["A", "B", "C"])
    }

    func test_movePriorityWithMissingTargetIsNoop() {
        settings.outputPriority = ["A", "B", "C"]

        settings.movePriority(uid: "A", before: "missing", isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["A", "B", "C"])
    }

    func test_reorderPriorityForDragMovesTwoDeviceGroupDown() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, "X", "Y"]

        settings.reorderPriorityForDrag(uid: a, over: "Y", isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["X", "Y", a, b])
    }

    func test_reorderPriorityForDragMovesTwoDeviceGroupUp() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.outputPriority = ["X", "Y", a, b]

        settings.reorderPriorityForDrag(uid: b, over: "X", isOutput: true)

        XCTAssertEqual(settings.outputPriority, [a, b, "X", "Y"])
    }

    func test_reorderPriorityForDragMovesWholeGroupIncludingDisconnectedPeer() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        let c = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:C:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: c, name: "Shure C", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, c, "X", "Y"]

        settings.reorderPriorityForDrag(uid: b, over: "Y", isOutput: true)

        XCTAssertEqual(settings.outputPriority, ["X", "Y", a, b, c])
    }

    func test_reorderPriorityForDragWithSourceAndTargetInSameGroupIsNoop() {
        let a = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:A:2,3"
        let b = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:B:2,3"
        settings.registerDevice(uid: a, name: "Shure A", isOutput: true, transportType: .usb)
        settings.registerDevice(uid: b, name: "Shure B", isOutput: true, transportType: .usb)
        settings.outputPriority = [a, b, "X"]

        settings.reorderPriorityForDrag(uid: a, over: b, isOutput: true)

        XCTAssertEqual(settings.outputPriority, [a, b, "X"])
    }

    func test_exportIncludesGroupByModelEnabledByGroup() throws {
        let uid = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        settings.registerDevice(uid: uid, name: "Shure MV7+", isOutput: true, transportType: .usb)
        settings.setGroupByModelEnabled(false, for: uid)

        let data = try settings.exportSettingsData()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(AppSettings.ExportedSettings.self, from: data)

        let key = try XCTUnwrap(settings.modelGroupKey(for: uid))
        XCTAssertEqual(exported.groupByModelEnabledByGroup?[key], false)
    }

    func test_importGroupByModelEnabledByGroupOverridesDisabledModelGroupKeys() throws {
        let uid = "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3"
        let key = "usbname:shure inc:shure mv7+"
        let json = """
        {
          "schemaVersion": 5,
          "exportedAt": "2026-02-24T00:00:00Z",
          "outputPriority": ["\(uid)"],
          "inputPriority": [],
          "disabledOutputDevices": [],
          "disabledInputDevices": [],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {"\(uid)": "Shure MV7+"},
          "knownDeviceTransportTypes": {"\(uid)": "usb"},
          "disabledModelGroupKeys": [],
          "groupByModelEnabledByGroup": {"\(key)": false},
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """

        try settings.importSettings(from: Data(json.utf8))

        XCTAssertFalse(settings.isGroupByModelEnabled(for: uid))
        XCTAssertTrue(settings.disabledModelGroupKeys.contains(key))
    }

    func test_importGroupByModelEnabledByGroupMergesWithDisabledModelGroupKeys() throws {
        let json = """
        {
          "schemaVersion": 5,
          "exportedAt": "2026-02-24T00:00:00Z",
          "outputPriority": [],
          "inputPriority": [],
          "disabledOutputDevices": [],
          "disabledInputDevices": [],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {},
          "disabledModelGroupKeys": ["usbname:vendor:a", "usbname:vendor:b"],
          "groupByModelEnabledByGroup": {
            "usbname:vendor:a": true,
            "usbname:vendor:c": false
          },
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """

        try settings.importSettings(from: Data(json.utf8))

        XCTAssertEqual(settings.disabledModelGroupKeys, ["usbname:vendor:b", "usbname:vendor:c"])
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

    func test_resetFooterStatsClearsCounters() {
        settings.autoSwitchCount = 12
        settings.millisecondsSaved = 34000
        settings.signalIntegrityScore = -5

        settings.resetFooterStats()

        XCTAssertEqual(settings.autoSwitchCount, 0)
        XCTAssertEqual(settings.millisecondsSaved, 0)
        XCTAssertEqual(settings.signalIntegrityScore, 0)
    }

    func test_resetFooterStatsPersistsAcrossReinit() throws {
        settings.autoSwitchCount = 12
        settings.millisecondsSaved = 34000
        settings.signalIntegrityScore = -5
        settings.resetFooterStats()

        let s2 = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(s2.autoSwitchCount, 0)
        XCTAssertEqual(s2.millisecondsSaved, 0)
        XCTAssertEqual(s2.signalIntegrityScore, 0)
    }

    // MARK: – Persistence round-trip

    func test_settingsPersistAcrossReinit() throws {
        settings.registerDevice(
            uid: "X",
            name: "Device X",
            isOutput: true,
            transportType: .bluetooth,
            iconBaseName: "airpodspro",
            modelUID: "2014 4c",
            isAppleMade: true,
            bluetoothMinorType: "Headphones"
        )
        settings.saveVolume(0.65, for: "X", isOutput: true)
        settings.saveAlertVolume(0.3, for: "X")
        settings.isAutoMode = false
        settings.hideMenuBarIcon = true
        settings.autoSwitchCount = 12
        settings.millisecondsSaved = 34000
        settings.signalIntegrityScore = -5
        settings.disableDevice(uid: "X", isOutput: true)
        settings.setIcon("mic", for: "X", isOutput: true)

        let s2 = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: suiteName)))
        XCTAssertEqual(s2.knownDevices["X"], "Device X")
        XCTAssertEqual(s2.knownDeviceTransportTypes["X"], .bluetooth)
        XCTAssertEqual(s2.knownDeviceIconBaseNames["X"], "airpodspro")
        XCTAssertEqual(s2.knownDeviceIsAppleMade["X"], true)
        XCTAssertEqual(s2.knownDeviceModelUIDs["X"], "2014 4c")
        XCTAssertEqual(s2.knownDeviceBluetoothMinorTypes["X"], "Headphones")
        XCTAssertEqual(s2.savedVolume(for: "X", isOutput: true) ?? 0, 0.65, accuracy: 0.001)
        XCTAssertEqual(s2.savedAlertVolume(for: "X") ?? 0, 0.3, accuracy: 0.001)
        XCTAssertFalse(s2.isAutoMode)
        XCTAssertTrue(s2.hideMenuBarIcon)
        XCTAssertEqual(s2.autoSwitchCount, 12)
        XCTAssertEqual(s2.millisecondsSaved, 34000)
        XCTAssertEqual(s2.signalIntegrityScore, -5)
        XCTAssertTrue(s2.disabledOutputDevices.contains("X"))
        XCTAssertEqual(s2.deviceIcons["X"]?["output"], "mic")
    }

    // MARK: – Import / export

    func test_exportImportRoundTrip() throws {
        settings.outputPriority = ["A", "A", "B"]
        settings.inputPriority = ["M"]
        settings.disabledOutputDevices = ["X"]
        settings.disabledInputDevices = ["Y"]
        settings.volumeMemory = ["A": ["output": 0.8, "alert": 0.4]]
        settings.customDeviceNames = ["A": ["output": "My Speaker"]]
        settings.deviceIcons = ["A": ["output": "speaker.wave.2"]]
        settings.knownDevices = ["A": "Speaker A"]
        settings.knownDeviceTransportTypes = ["A": .bluetooth]
        settings.knownDeviceIconBaseNames = ["A": "airpodspro"]
        settings.knownDeviceIsAppleMade = ["A": true]
        settings.knownDeviceModelUIDs = ["A": "2014 4c"]
        settings.knownDeviceBluetoothMinorTypes = ["A": "Headphones"]
        settings.appLanguage = "de"
        settings.isAutoMode = false
        settings.hideMenuBarIcon = true
        settings.testSound = .system(name: "Tink")
        settings.alertSound = .none
        settings.busyLightEnabled = true
        settings.busyLightControlMode = .manual
        settings.busyLightManualAction = BusyLightAction(
            mode: .solid,
            color: BusyLightColor(red: 10, green: 20, blue: 30),
            periodMilliseconds: 777
        )
        settings.busyLightAPIEnabled = true
        settings.busyLightAPIPort = 51234
        let ruleID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        settings.busyLightRules = [
            BusyLightRule(
                id: ruleID,
                name: "Mic busy",
                isEnabled: true,
                expression: BusyLightExpression(
                    conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
                    operators: []
                ),
                action: BusyLightAction(
                    mode: .blink,
                    color: BusyLightColor(red: 255, green: 140, blue: 0),
                    periodMilliseconds: 900
                )
            ),
        ]
        settings.busyLightRuleMetrics = [
            AppSettings.busyLightRuleMetricsKey(for: ruleID): BusyLightRuleMetrics(
                totalActiveMilliseconds: 12345,
                recentIntervals: [BusyLightRuleActiveInterval(
                    startEpochMilliseconds: 1_700_000_000_000,
                    endEpochMilliseconds: 1_700_000_010_000
                )]
            ),
        ]

        let data = try settings.exportSettingsData()

        let otherSuite = "SentrioTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: otherSuite) }

        let imported = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: otherSuite)))
        try imported.importSettings(from: data)

        XCTAssertEqual(imported.outputPriority, ["A", "B"], "Import should de-duplicate priority lists")
        XCTAssertEqual(imported.inputPriority, ["M"])
        XCTAssertEqual(imported.disabledOutputDevices, ["X"])
        XCTAssertEqual(imported.disabledInputDevices, ["Y"])
        XCTAssertEqual(imported.volumeMemory["A"]?["output"] ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(imported.volumeMemory["A"]?["alert"] ?? 0, 0.4, accuracy: 0.001)
        XCTAssertEqual(imported.customDeviceNames["A"]?["output"], "My Speaker")
        XCTAssertEqual(imported.deviceIcons["A"]?["output"], "speaker.wave.2")
        XCTAssertEqual(imported.knownDevices["A"], "Speaker A")
        XCTAssertEqual(imported.knownDeviceTransportTypes["A"], .bluetooth)
        XCTAssertEqual(imported.knownDeviceIconBaseNames["A"], "airpodspro")
        XCTAssertEqual(imported.knownDeviceIsAppleMade["A"], true)
        XCTAssertEqual(imported.knownDeviceModelUIDs["A"], "2014 4c")
        XCTAssertEqual(imported.knownDeviceBluetoothMinorTypes["A"], "Headphones")
        XCTAssertEqual(imported.appLanguage, "de")
        XCTAssertFalse(imported.isAutoMode)
        XCTAssertTrue(imported.hideMenuBarIcon)
        XCTAssertEqual(imported.testSound, .system(name: "Tink"))
        XCTAssertEqual(imported.alertSound, .none)
        XCTAssertTrue(imported.busyLightEnabled)
        XCTAssertEqual(imported.busyLightControlMode, .manual)
        XCTAssertEqual(imported.busyLightManualAction, settings.busyLightManualAction)
        XCTAssertTrue(imported.busyLightAPIEnabled)
        XCTAssertEqual(imported.busyLightAPIPort, 51234)
        XCTAssertEqual(imported.busyLightRules, settings.busyLightRules)
        XCTAssertEqual(imported.busyLightRuleMetrics, settings.busyLightRuleMetrics)
    }

    func test_exportUsesHiddenDeviceKeys() throws {
        settings.disabledOutputDevices = ["X"]
        settings.disabledInputDevices = ["Y"]

        let data = try settings.exportSettingsData()
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"hiddenOutputDevices\""))
        XCTAssertTrue(json.contains("\"hiddenInputDevices\""))
        XCTAssertFalse(json.contains("\"disabledOutputDevices\""))
        XCTAssertFalse(json.contains("\"disabledInputDevices\""))
    }

    func test_importRejectsNonSettingsJSON() throws {
        let data = Data("{\"hello\":\"world\"}".utf8)
        XCTAssertThrowsError(try settings.importSettings(from: data)) { error in
            XCTAssertTrue(error is AppSettings.ImportExportError)
        }
    }

    func test_importRejectsUnsupportedSchema() throws {
        let json = """
        {
          "schemaVersion": 99,
          "exportedAt": "2026-02-22T00:00:00Z",
          "outputPriority": [],
          "inputPriority": [],
          "disabledOutputDevices": [],
          "disabledInputDevices": [],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {},
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """
        let data = Data(json.utf8)
        XCTAssertThrowsError(try settings.importSettings(from: data)) { error in
            guard case let AppSettings.ImportExportError.unsupportedSchema(v) = error else {
                return XCTFail("Expected unsupportedSchema error, got: \(error)")
            }
            XCTAssertEqual(v, 99)
        }
    }

    func test_importSettingsWithMissingOptionalFieldsUsesDefaults() throws {
        // Simulates an older settings export with optional keys missing.
        let json = """
        {
          "schemaVersion": 1,
          "exportedAt": "2026-02-22T00:00:00Z",
          "outputPriority": ["A"],
          "inputPriority": ["M"],
          "disabledOutputDevices": [],
          "disabledInputDevices": [],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {"A": "Speaker A"},
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """
        try settings.importSettings(from: Data(json.utf8))
        XCTAssertEqual(settings.outputPriority, ["A"])
        XCTAssertEqual(settings.inputPriority, ["M"])
        XCTAssertEqual(settings.appLanguage, "system")
        XCTAssertFalse(settings.showInputLevelMeter, "Missing showInputLevelMeter should default to false")
        XCTAssertTrue(settings.knownDeviceTransportTypes.isEmpty)
        XCTAssertTrue(settings.knownDeviceIconBaseNames.isEmpty)
        XCTAssertTrue(settings.knownDeviceIsAppleMade.isEmpty)
        XCTAssertTrue(settings.knownDeviceModelUIDs.isEmpty)
        XCTAssertTrue(settings.knownDeviceBluetoothMinorTypes.isEmpty)
        XCTAssertFalse(settings.busyLightEnabled)
        XCTAssertEqual(settings.busyLightControlMode, .auto)
        XCTAssertEqual(settings.busyLightManualAction, .defaultBusy)
        XCTAssertFalse(settings.busyLightAPIEnabled)
        XCTAssertEqual(settings.busyLightAPIPort, 47833)
        XCTAssertEqual(settings.busyLightRules.count, 3)
    }

    func test_importLegacyDisabledDeviceKeysStillSupported() throws {
        let json = """
        {
          "schemaVersion": 4,
          "exportedAt": "2026-02-24T00:00:00Z",
          "outputPriority": [],
          "inputPriority": [],
          "disabledOutputDevices": ["A"],
          "disabledInputDevices": ["B"],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {},
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """

        try settings.importSettings(from: Data(json.utf8))

        XCTAssertEqual(settings.disabledOutputDevices, ["A"])
        XCTAssertEqual(settings.disabledInputDevices, ["B"])
    }

    func test_importPrefersHiddenDeviceKeysWhenBothArePresent() throws {
        let json = """
        {
          "schemaVersion": 5,
          "exportedAt": "2026-02-24T00:00:00Z",
          "outputPriority": [],
          "inputPriority": [],
          "hiddenOutputDevices": ["H1"],
          "hiddenInputDevices": ["H2"],
          "disabledOutputDevices": ["D1"],
          "disabledInputDevices": ["D2"],
          "volumeMemory": {},
          "customDeviceNames": {},
          "deviceIcons": {},
          "knownDevices": {},
          "isAutoMode": true,
          "hideMenuBarIcon": false
        }
        """

        try settings.importSettings(from: Data(json.utf8))

        XCTAssertEqual(settings.disabledOutputDevices, ["H1"])
        XCTAssertEqual(settings.disabledInputDevices, ["H2"])
    }

    func test_exportImportRoundTripPreservesDisabledModelGroupKeysWithoutKnownDevices() throws {
        settings.disabledModelGroupKeys = ["usbname:shure inc:shure mv7+"]

        let data = try settings.exportSettingsData()

        let otherSuite = "SentrioTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: otherSuite) }
        let imported = try AppSettings(defaults: XCTUnwrap(UserDefaults(suiteName: otherSuite)))

        try imported.importSettings(from: data)

        XCTAssertEqual(imported.disabledModelGroupKeys, ["usbname:shure inc:shure mv7+"])
    }

    func test_busyLightRuleMetricsRemovedWhenRuleDeleted() throws {
        let keepID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000AA"))
        let dropID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000BB"))
        settings.busyLightRules = [
            BusyLightRule(
                id: keepID,
                name: "Keep",
                expression: BusyLightExpression(
                    conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
                    operators: []
                ),
                action: .defaultBusy
            ),
            BusyLightRule(
                id: dropID,
                name: "Drop",
                expression: BusyLightExpression(
                    conditions: [BusyLightCondition(signal: .camera, expectedValue: true)],
                    operators: []
                ),
                action: .defaultBusy
            ),
        ]

        settings.busyLightRuleMetrics = [
            AppSettings.busyLightRuleMetricsKey(for: keepID): BusyLightRuleMetrics(totalActiveMilliseconds: 100),
            AppSettings.busyLightRuleMetricsKey(for: dropID): BusyLightRuleMetrics(totalActiveMilliseconds: 200),
        ]

        settings.busyLightRules = [settings.busyLightRules[0]]

        XCTAssertNotNil(settings.busyLightRuleMetrics[AppSettings.busyLightRuleMetricsKey(for: keepID)])
        XCTAssertNil(settings.busyLightRuleMetrics[AppSettings.busyLightRuleMetricsKey(for: dropID)])
    }

    func test_recordBusyLightRuleActiveInterval_ignoresUnknownRule() throws {
        let knownID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000CC"))
        settings.busyLightRules = [
            BusyLightRule(
                id: knownID,
                name: "Known",
                expression: BusyLightExpression(
                    conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
                    operators: []
                ),
                action: .defaultBusy
            ),
        ]

        let unknownID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000DD"))
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_000_001)

        settings.recordBusyLightRuleActiveInterval(ruleID: unknownID, start: start, end: end, now: end)

        XCTAssertTrue(settings.busyLightRuleMetrics.isEmpty)
    }

    func test_recordBusyLightRuleActiveInterval_recordsDurationForKnownRule() throws {
        let ruleID = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-0000000000EE"))
        settings.busyLightRules = [
            BusyLightRule(
                id: ruleID,
                name: "Known",
                expression: BusyLightExpression(
                    conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
                    operators: []
                ),
                action: .defaultBusy
            ),
        ]

        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = Date(timeIntervalSince1970: 1_700_000_004)

        settings.recordBusyLightRuleActiveInterval(ruleID: ruleID, start: start, end: end, now: end)

        let key = AppSettings.busyLightRuleMetricsKey(for: ruleID)
        XCTAssertEqual(settings.busyLightRuleMetrics[key]?.totalActiveMilliseconds, 4000)
        XCTAssertEqual(settings.busyLightRuleMetrics[key]?.recentIntervals.count, 1)
    }

    // MARK: – deleteDevice

    func test_deleteRemovesFromPriorityAndKnown() {
        settings.registerDevice(uid: "A", name: "Speaker A", isOutput: true)
        settings.deleteDevice(uid: "A")
        XCTAssertFalse(settings.outputPriority.contains("A"))
        XCTAssertNil(settings.knownDevices["A"])
    }

    func test_deleteClearsKnownDeviceMetadata() {
        settings.registerDevice(
            uid: "A",
            name: "Device A",
            isOutput: true,
            transportType: .bluetooth,
            iconBaseName: "airpodspro",
            modelUID: "2014 4c",
            isAppleMade: true,
            bluetoothMinorType: "Headphones"
        )
        settings.deleteDevice(uid: "A")
        XCTAssertNil(settings.knownDeviceTransportTypes["A"])
        XCTAssertNil(settings.knownDeviceIconBaseNames["A"])
        XCTAssertNil(settings.knownDeviceIsAppleMade["A"])
        XCTAssertNil(settings.knownDeviceModelUIDs["A"])
        XCTAssertNil(settings.knownDeviceBluetoothMinorTypes["A"])
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
            XCTAssertFalse(opt.labelKey.isEmpty, "Empty labelKey for symbol '\(opt.symbol)'")
            XCTAssertFalse(L10n.tr(opt.labelKey).isEmpty, "Empty localized label for symbol '\(opt.symbol)'")
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

    // MARK: – defaultIconName (disconnected rows)

    func test_defaultIconNameFallsBackToGenericRoleIcons() {
        XCTAssertEqual(settings.defaultIconName(for: "unknown-uid", isOutput: true), "speaker.wave.2")
        XCTAssertEqual(settings.defaultIconName(for: "unknown-uid", isOutput: false), "mic")
    }

    func test_defaultIconNameUsesPersistedModelUIDForAirPods() {
        settings.knownDevices["X"] = "[Yuna] ClayWave"
        settings.knownDeviceTransportTypes["X"] = .bluetooth
        settings.knownDeviceIsAppleMade["X"] = true
        settings.knownDeviceModelUIDs["X"] = "2014 4c"
        settings.knownDeviceBluetoothMinorTypes["X"] = "Headphones"

        XCTAssertEqual(settings.defaultIconName(for: "X", isOutput: true), "airpodspro")
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

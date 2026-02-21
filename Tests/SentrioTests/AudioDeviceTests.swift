import XCTest
import CoreAudio
@testable import SentrioCore

final class AudioDeviceTests: XCTestCase {

    // MARK: – Equality / Hashing

    func test_equalityByUID() {
        let a = d("uid-A"); let b = AudioDevice(id: 99, uid: "uid-A", name: "Other", hasInput: false, hasOutput: true)
        XCTAssertEqual(a, b)
    }

    func test_differentUIDsNotEqual() {
        XCTAssertNotEqual(d("uid-A"), d("uid-B"))
    }

    func test_hashConsistentWithEquality() {
        let a = d("uid-A")
        let b = AudioDevice(id: 9, uid: "uid-A", name: "B", hasInput: false, hasOutput: false)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func test_usableInSet() {
        let s: Set<AudioDevice> = [d("A"), AudioDevice(id: 2, uid: "A", name: "A2", hasInput: true, hasOutput: true), d("B")]
        XCTAssertEqual(s.count, 2)
    }

    // MARK: – TransportType labels and icons

    func test_allTransportTypesHaveConnectionImage() {
        for t in AudioDevice.TransportType.allCases {
            XCTAssertFalse(t.connectionSystemImage.isEmpty, "\(t) has empty connectionSystemImage")
            XCTAssertFalse(t.label.isEmpty,                 "\(t) has empty label")
        }
    }

    func test_defaultTransportIsUnknown() {
        XCTAssertEqual(d("A").transportType, .unknown)
    }

    func test_bluetoothTransportIcon() {
        let device = AudioDevice(uid: "X", name: "Generic BT", hasInput: false, hasOutput: true, transportType: .bluetooth)
        XCTAssertEqual(device.deviceTypeSystemImage, AudioDevice.TransportType.bluetooth.connectionSystemImage)
    }

    func test_usbTransportIcon() {
        let device = AudioDevice(uid: "X", name: "Generic USB", hasInput: false, hasOutput: true, transportType: .usb)
        XCTAssertEqual(device.deviceTypeSystemImage, AudioDevice.TransportType.usb.connectionSystemImage)
    }

    func test_airPlayTransportIcon() {
        let device = AudioDevice(uid: "X", name: "Generic AirPlay", hasInput: false, hasOutput: true, transportType: .airPlay)
        XCTAssertEqual(device.deviceTypeSystemImage, AudioDevice.TransportType.airPlay.connectionSystemImage)
    }

    func test_thunderboltTransportIcon() {
        let device = AudioDevice(uid: "X", name: "DAC Interface", hasInput: false, hasOutput: true, transportType: .thunderbolt)
        XCTAssertEqual(device.deviceTypeSystemImage, AudioDevice.TransportType.thunderbolt.connectionSystemImage)
    }

    // MARK: – Device-type icon heuristic (name-based)

    func test_airPodsProIcon() {
        XCTAssertEqual(dev("AirPods Pro").deviceTypeSystemImage, "airpodspro")
    }

    func test_airPodsMaxIcon() {
        XCTAssertEqual(dev("AirPods Max").deviceTypeSystemImage, "airpodsmax")
    }

    func test_airPodsIcon() {
        XCTAssertEqual(dev("AirPods").deviceTypeSystemImage, "airpods")
    }

    func test_earPodsIcon() {
        XCTAssertEqual(dev("EarPods").deviceTypeSystemImage, "earbuds")
    }

    func test_headphonesIcon() {
        XCTAssertEqual(dev("Headphones").deviceTypeSystemImage, "headphones")
    }

    func test_headsetIcon() {
        XCTAssertEqual(dev("USB Headset").deviceTypeSystemImage, "headphones")
    }

    func test_homePodIcon() {
        XCTAssertEqual(dev("HomePod").deviceTypeSystemImage, "homepod")
    }

    func test_homePodMiniIcon() {
        XCTAssertEqual(dev("HomePod mini").deviceTypeSystemImage, "homepodmini")
    }

    func test_iPhoneIcon() {
        XCTAssertEqual(dev("Yuna's iPhone").deviceTypeSystemImage, "iphone")
    }

    func test_iPadIcon() {
        XCTAssertEqual(dev("Yuna's iPad").deviceTypeSystemImage, "ipad")
    }

    func test_macBookIcon() {
        XCTAssertEqual(dev("MacBook Pro").deviceTypeSystemImage, "laptopcomputer")
    }

    func test_builtInSpeakerIcon() {
        let device = AudioDevice(uid: "X", name: "Built-in Output", hasInput: false, hasOutput: true)
        XCTAssertEqual(device.deviceTypeSystemImage, "speaker.wave.2")
    }

    func test_builtInMicIcon() {
        let device = AudioDevice(uid: "X", name: "Built-in Microphone", hasInput: true, hasOutput: false)
        XCTAssertEqual(device.deviceTypeSystemImage, "mic")
    }

    func test_builtInBothIcon() {
        // Built-in with both input and output → macmini fallback
        let device = AudioDevice(uid: "X", name: "Built-in", hasInput: true, hasOutput: true)
        XCTAssertEqual(device.deviceTypeSystemImage, "macmini")
    }

    func test_speakerNameIcon() {
        XCTAssertEqual(dev("Studio Speaker").deviceTypeSystemImage, "hifispeaker")
    }

    func test_outputNameIcon() {
        XCTAssertEqual(dev("Audio Output").deviceTypeSystemImage, "hifispeaker")
    }

    func test_microphoneNameIcon() {
        XCTAssertEqual(dev("Studio Microphone").deviceTypeSystemImage, "mic")
    }

    func test_displayNameIcon() {
        XCTAssertEqual(dev("LG Display").deviceTypeSystemImage, "display")
    }

    func test_monitorNameIcon() {
        XCTAssertEqual(dev("Dell Monitor").deviceTypeSystemImage, "display")
    }

    func test_usbNameIcon() {
        // "usb" in name but no matching device-type keyword → cable.connector
        XCTAssertEqual(dev("USB Audio Device").deviceTypeSystemImage, "cable.connector")
    }

    func test_unknownDeviceFallsBackToTransportIcon() {
        let device = AudioDevice(uid: "X", name: "Mystery Device",
                                 hasInput: true, hasOutput: true, transportType: .usb)
        XCTAssertEqual(device.deviceTypeSystemImage, AudioDevice.TransportType.usb.connectionSystemImage)
    }

    func test_unknownNameUnknownTransportFallsBackToQuestionMark() {
        let device = AudioDevice(uid: "X", name: "XYZZY 3000", hasInput: false, hasOutput: true, transportType: .unknown)
        XCTAssertEqual(device.deviceTypeSystemImage, "questionmark.circle")
    }

    // MARK: – iconBaseName resolution (kAudioDevicePropertyIcon stem → SF Symbol)

    func test_iconBaseNameTakesPriorityOverNameHeuristic() {
        // iconBaseName "airpodspro" should win even if name says something generic
        let device = AudioDevice(uid: "X", name: "Generic BT Headset",
                                 hasInput: true, hasOutput: true,
                                 transportType: .bluetooth,
                                 iconBaseName: "airpodspro")
        XCTAssertEqual(device.deviceTypeSystemImage, "airpodspro")
    }

    func test_iconBaseNameAlternativeSpelling() {
        let device = AudioDevice(uid: "X", name: "AirPods",
                                 hasInput: true, hasOutput: true,
                                 transportType: .bluetooth,
                                 iconBaseName: "airpodsheadphonespro")
        XCTAssertEqual(device.deviceTypeSystemImage, "airpodspro")
    }

    func test_iconBaseNameHomePodMini() {
        let device = AudioDevice(uid: "X", name: "HomePod mini",
                                 hasInput: false, hasOutput: true,
                                 transportType: .airPlay,
                                 iconBaseName: "homepodmini")
        XCTAssertEqual(device.deviceTypeSystemImage, "homepodmini")
    }

    func test_iconBaseNameUnknownFallsBackToNameHeuristic() {
        // Unrecognised icon file stem → fall through to name matching
        let device = AudioDevice(uid: "X", name: "AirPods Pro",
                                 hasInput: true, hasOutput: true,
                                 transportType: .bluetooth,
                                 iconBaseName: "someunknowndevice")
        XCTAssertEqual(device.deviceTypeSystemImage, "airpodspro",
                       "Unknown icon stem must fall through to name heuristic")
    }

    func test_nilIconBaseNameFallsBackToNameHeuristic() {
        let device = AudioDevice(uid: "X", name: "AirPods Pro",
                                 hasInput: true, hasOutput: true,
                                 transportType: .bluetooth,
                                 iconBaseName: nil)
        XCTAssertEqual(device.deviceTypeSystemImage, "airpodspro")
    }

    func test_iconBaseNameNotPersistedInCodable() throws {
        let original = AudioDevice(uid: "X", name: "AirPods Pro",
                                   hasInput: true, hasOutput: true,
                                   transportType: .bluetooth,
                                   iconBaseName: "airpodspro")
        let decoded  = try JSONDecoder().decode(AudioDevice.self, from: JSONEncoder().encode(original))
        XCTAssertNil(decoded.iconBaseName, "iconBaseName must not be persisted — it is live-only data")
        // Name heuristic must still give the right answer after decode
        XCTAssertEqual(decoded.deviceTypeSystemImage, "airpodspro")
    }

    func test_airPodsMaxHeuristicUsesAirpodsMaxSymbol() {
        // Previously mapped to "headphones" — now uses "airpodsmax"
        XCTAssertEqual(dev("AirPods Max").deviceTypeSystemImage, "airpodsmax")
    }

    // MARK: – Apple Bluetooth fallback (renamed devices like "[Yuna] ClayWave")

    // NOTE: kAudioDevicePropertyDeviceManufacturer is NOT used — on macOS 26 it writes raw
    // C-string bytes into the buffer instead of a CFString pointer, causing a bad-pointer crash.
    // isAppleMade is derived from the icon URL path (Apple icons live in Apple framework bundles).

    func test_appleBTDeviceWithCustomNameFallsBackToAirpods() {
        // Simulates AirPods renamed by the user — name contains no "airpods" keyword,
        // but isAppleMade=true (icon URL was in an Apple framework path) and transport is Bluetooth.
        let device = AudioDevice(uid: "2C-32-6A-E9-E9-65:output",
                                 name: "[Yuna] ClayWave",
                                 hasInput: false, hasOutput: true,
                                 transportType: .bluetooth,
                                 isAppleMade: true)
        XCTAssertEqual(device.deviceTypeSystemImage, "airpods",
                       "Apple BT device with renamed name must fall back to 'airpods'")
    }

    func test_nonAppleBTDeviceDoesNotGetAirpodsIcon() {
        // Name must not trigger any name heuristic so we reach the isAppleMade check
        let device = AudioDevice(uid: "X", name: "XZ-9000 Wireless",
                                 hasInput: false, hasOutput: true,
                                 transportType: .bluetooth,
                                 isAppleMade: false)
        XCTAssertEqual(device.deviceTypeSystemImage, "wave.3.right",
                       "Non-Apple BT device must fall back to transport icon, not airpods")
    }

    func test_iconBaseNameBeatsAreHeadphones() {
        let device = AudioDevice(uid: "X", name: "Beats Studio 3",
                                 hasInput: true, hasOutput: true,
                                 transportType: .bluetooth,
                                 iconBaseName: "beatsstudio3")
        XCTAssertEqual(device.deviceTypeSystemImage, "headphones")
    }

    // MARK: – Volume-adapted speaker icon

    func test_volumeAdaptedIconMuted() {
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("speaker.wave.2", volume: 0), "speaker.slash")
    }

    func test_volumeAdaptedIconLow() {
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("speaker.wave.3", volume: 0.1), "speaker.wave.1")
    }

    func test_volumeAdaptedIconMid() {
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("hifispeaker", volume: 0.5), "speaker.wave.2")
    }

    func test_volumeAdaptedIconHigh() {
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("speaker.wave.1", volume: 0.9), "speaker.wave.3")
    }

    func test_volumeAdaptedIconDoesNotChangeNonSpeakerIcons() {
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("airpodspro", volume: 0), "airpodspro",
                       "AirPods icon must not be replaced by volume-reactive speaker")
        XCTAssertEqual(AudioDevice.volumeAdaptedIcon("mic", volume: 0), "mic")
    }

    // MARK: – Battery

    func test_batteryIconFullCharge() {
        let d = AudioDevice(uid: "X", name: "X", hasInput: false, hasOutput: true,
                            batteryLevel: 0.95)
        XCTAssertEqual(d.batterySystemImage, "battery.100percent")
    }

    func test_batteryIconLow() {
        let d = AudioDevice(uid: "X", name: "X", hasInput: false, hasOutput: true,
                            batteryLevel: 0.10)
        XCTAssertEqual(d.batterySystemImage, "battery.0percent")
    }

    func test_batteryIconNilWhenNoBattery() {
        let d = AudioDevice(uid: "X", name: "X", hasInput: false, hasOutput: true)
        XCTAssertNil(d.batterySystemImage)
    }

    func test_batteryNotPersistedInCodable() throws {
        let original = AudioDevice(uid: "X", name: "X", hasInput: false, hasOutput: true,
                                   batteryLevel: 0.8)
        let decoded  = try JSONDecoder().decode(AudioDevice.self, from: JSONEncoder().encode(original))
        XCTAssertNil(decoded.batteryLevel, "batteryLevel must not be persisted")
    }

    // MARK: – Codable roundtrip

    func test_codableRoundtrip() throws {
        let original = AudioDevice(id: 42, uid: "uid-test", name: "Test Mic",
                                   hasInput: true, hasOutput: false, transportType: .usb)
        let decoded  = try JSONDecoder().decode(AudioDevice.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.uid,           original.uid)
        XCTAssertEqual(decoded.name,          original.name)
        XCTAssertEqual(decoded.hasInput,      original.hasInput)
        XCTAssertEqual(decoded.hasOutput,     original.hasOutput)
        XCTAssertEqual(decoded.transportType, original.transportType)
        XCTAssertEqual(decoded.id,            kAudioObjectUnknown)
    }

    func test_codableRoundtripBluetoothDevice() throws {
        let original = AudioDevice(id: 5, uid: "bt-001", name: "BT Speaker",
                                   hasInput: false, hasOutput: true, transportType: .bluetooth)
        let decoded  = try JSONDecoder().decode(AudioDevice.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.transportType, .bluetooth)
    }

    // MARK: – Helpers

    private func d(_ uid: String) -> AudioDevice {
        AudioDevice(uid: uid, name: uid, hasInput: true, hasOutput: true)
    }
    private func dev(_ name: String) -> AudioDevice {
        AudioDevice(uid: name, name: name, hasInput: true, hasOutput: true)
    }
}

import CoreAudio
import Foundation
@testable import SentrioCore
import XCTest

@MainActor
final class IsolatedRuntimeTests: XCTestCase {
    func test_audioManager_isolatedMode_updatesDefaultsAndVolumesInMemoryOnly() {
        let audio = AudioManager(mode: .isolated)
        let mic = AudioDevice(
            id: AudioDeviceID(501),
            uid: "mock:mic",
            name: "Mock Mic",
            hasInput: true,
            hasOutput: false,
            transportType: .virtual
        )
        let speakers = AudioDevice(
            id: AudioDeviceID(502),
            uid: "mock:speakers",
            name: "Mock Speakers",
            hasInput: false,
            hasOutput: true,
            transportType: .virtual
        )

        audio.setDefault(mic, isInput: true)
        audio.setDefault(speakers, isInput: false)

        audio.setVolume(0.42, for: mic, isOutput: false)
        audio.setVolume(0, for: speakers, isOutput: true)
        audio.setAlertVolume(0.27)

        XCTAssertEqual(audio.defaultInput?.uid, "mock:mic")
        XCTAssertEqual(audio.defaultOutput?.uid, "mock:speakers")
        XCTAssertEqual(audio.volume(for: mic, isOutput: false) ?? -1, Float(0.42), accuracy: 0.0001)
        XCTAssertEqual(audio.volume(for: speakers, isOutput: true) ?? -1, Float(0), accuracy: 0.0001)
        XCTAssertEqual(audio.alertVolume, Float(0.27), accuracy: 0.0001)
        XCTAssertEqual(audio.mute(for: speakers, isOutput: true), true)
    }

    func test_busyLightUSBClient_isolatedMode_hasNoHardwareSideEffects() {
        let client = BusyLightUSBClient(mode: .isolated)
        XCTAssertTrue(client.devices.isEmpty)
        XCTAssertTrue(client.setSolidColor(.redColor).isEmpty)
        XCTAssertTrue(client.turnOff().isEmpty)
    }

    func test_busyLightSignalsMonitor_isolatedMode_staysIdle() {
        let audio = AudioManager(mode: .isolated)
        let monitor = BusyLightSignalsMonitor(audio: audio, mode: .isolated)
        XCTAssertEqual(
            monitor.signals,
            BusyLightSignals(
                microphoneInUse: false,
                cameraInUse: false,
                screenRecordingInUse: false,
                musicPlaying: false
            )
        )
    }

    func test_busyLightEngine_isolatedMode_doesNotStartAPI() {
        let suiteName = "Sentrio.IsolatedRuntimeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to allocate isolated defaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults)
        settings.busyLightAPIEnabled = true
        let audio = AudioManager(mode: .isolated)
        let engine = BusyLightEngine(audio: audio, settings: settings, mode: .isolated)
        defer { engine.shutdown() }

        XCTAssertFalse(engine.apiServerRunning)
        XCTAssertNil(engine.apiServerError)
    }

    func test_rulesEngine_autoMode_restoresHighestPriorityInputAfterDefaultDrift() async throws {
        let suiteName = "Sentrio.IsolatedRuntimeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to allocate isolated defaults suite.")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let settings = AppSettings(defaults: defaults)
        settings.isAutoMode = true
        settings.inputPriority = ["shure-mv7", "airpods-mic"]

        let shureMic = AudioDevice(
            uid: "shure-mv7",
            name: "Shure MV7+",
            hasInput: true,
            hasOutput: false,
            transportType: .usb
        )
        let airPodsMic = AudioDevice(
            uid: "airpods-mic",
            name: "AirPods Pro",
            hasInput: true,
            hasOutput: true,
            transportType: .bluetooth
        )

        let audio = AudioManager(mode: .isolated)
        audio.inputDevices = [shureMic, airPodsMic]
        audio.defaultInput = shureMic

        let rules = RulesEngine(audio: audio, settings: settings)
        _ = rules

        // Simulate macOS forcing both roles onto AirPods when they connect.
        audio.defaultInput = airPodsMic

        try await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(
            audio.defaultInput?.uid,
            "shure-mv7",
            "Auto mode should restore the highest-priority input device."
        )
    }
}

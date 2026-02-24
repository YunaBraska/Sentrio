import CoreAudio
@testable import SentrioCore
import XCTest

final class AudioManagerTests: XCTestCase {
    func test_didDefaultSwitchSucceed_whenStatusIsNoErrAndResolvedMatchesTarget_returnsTrue() {
        XCTAssertTrue(
            AudioManager.didDefaultSwitchSucceed(
                status: noErr,
                resolvedDefaultID: 42,
                targetID: 42
            )
        )
    }

    func test_didDefaultSwitchSucceed_whenStatusIsError_returnsFalse() {
        XCTAssertFalse(
            AudioManager.didDefaultSwitchSucceed(
                status: -50,
                resolvedDefaultID: 42,
                targetID: 42
            )
        )
    }

    func test_didDefaultSwitchSucceed_whenResolvedDoesNotMatchTarget_returnsFalse() {
        XCTAssertFalse(
            AudioManager.didDefaultSwitchSucceed(
                status: noErr,
                resolvedDefaultID: 7,
                targetID: 42
            )
        )
    }

    func test_isDeviceUnavailable_whenUntilIsNil_returnsFalse() {
        let now = Date()
        XCTAssertFalse(AudioManager.isDeviceUnavailable(until: nil, now: now))
    }

    func test_isDeviceUnavailable_whenUntilIsPast_returnsFalse() {
        let now = Date()
        XCTAssertFalse(
            AudioManager.isDeviceUnavailable(
                until: now.addingTimeInterval(-1),
                now: now
            )
        )
    }

    func test_isDeviceUnavailable_whenUntilIsFuture_returnsTrue() {
        let now = Date()
        XCTAssertTrue(
            AudioManager.isDeviceUnavailable(
                until: now.addingTimeInterval(30),
                now: now
            )
        )
    }

    func test_requiresManualConnection_whenModelUIDIsIPhoneMic_returnsTrue() {
        XCTAssertTrue(
            AudioManager.requiresManualConnection(
                uid: "8FD81C81-7471-4F4C-A9F3-3C0100000003",
                name: "HellishSky Microphone",
                transportType: .unknown,
                modelUID: "iPhone Mic"
            )
        )
    }

    func test_requiresManualConnection_whenUSBMic_returnsFalse() {
        XCTAssertFalse(
            AudioManager.requiresManualConnection(
                uid: "AppleUSBAudioEngine:Shure Inc:Shure MV7+:132000:2,3",
                name: "Shure MV7+",
                transportType: .usb,
                modelUID: "Shure MV7+:14ED:1019"
            )
        )
    }

    func test_looksLikeCoreAudioUUID_detectsUUIDShape() {
        XCTAssertTrue(AudioManager.looksLikeCoreAudioUUID("8FD81C81-7471-4F4C-A9F3-3C0100000003"))
        XCTAssertFalse(AudioManager.looksLikeCoreAudioUUID("BuiltInMicrophoneDevice"))
    }
}

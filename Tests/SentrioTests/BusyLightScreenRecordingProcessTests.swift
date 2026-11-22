@testable import SentrioCore
import XCTest

final class BusyLightScreenRecordingProcessTests: XCTestCase {
    func test_isScreenRecordingUI_acceptsTheActiveMacOSRecorder() {
        XCTAssertTrue(BusyLightScreenRecordingProcess.isScreenRecordingUI(
            bundleIdentifier: "com.apple.screencaptureui"
        ))
    }

    func test_isScreenRecordingUI_rejectsOtherApplicationsAndMissingIdentifiers() {
        XCTAssertFalse(BusyLightScreenRecordingProcess.isScreenRecordingUI(
            bundleIdentifier: "com.apple.controls.screenshot"
        ))
        XCTAssertFalse(BusyLightScreenRecordingProcess.isScreenRecordingUI(
            bundleIdentifier: "com.apple.QuickTimePlayerX"
        ))
        XCTAssertFalse(BusyLightScreenRecordingProcess.isScreenRecordingUI(bundleIdentifier: nil))
    }
}

import XCTest
@testable import SentrioCore

final class BusyLightPlaybackProcessFilterTests: XCTestCase {
    func test_isActiveOutputProcess_returnsFalseWhenOutputNotRunning() {
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: nil,
            ioRunning: 1,
            processID: 123,
            ownProcessID: 999,
            bundleID: "org.mozilla.firefox"
        ))
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 0,
            ioRunning: 1,
            processID: 123,
            ownProcessID: 999,
            bundleID: "org.mozilla.firefox"
        ))
    }

    func test_isActiveOutputProcess_returnsFalseWhenIONotRunning() {
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: nil,
            processID: 123,
            ownProcessID: 999,
            bundleID: "com.google.Chrome"
        ))
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: 0,
            processID: 123,
            ownProcessID: 999,
            bundleID: "com.google.Chrome"
        ))
    }

    func test_isActiveOutputProcess_returnsFalseWhenPIDMissingOrOwnProcess() {
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: 1,
            processID: nil,
            ownProcessID: 999,
            bundleID: "com.apple.Safari"
        ))
        XCTAssertFalse(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: 1,
            processID: 999,
            ownProcessID: 999,
            bundleID: "com.apple.Safari"
        ))
    }

    func test_isActiveOutputProcess_returnsTrueForSafariWebKitHelper() {
        XCTAssertTrue(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: 1,
            processID: 123,
            ownProcessID: 999,
            bundleID: "com.apple.WebKit.WebContent"
        ))
    }

    func test_isActiveOutputProcess_returnsTrueWhenBundleIDMissing() {
        XCTAssertTrue(BusyLightPlaybackProcessFilter.isActiveOutputProcess(
            outputRunning: 1,
            ioRunning: 1,
            processID: 123,
            ownProcessID: 999,
            bundleID: nil
        ))
    }
}

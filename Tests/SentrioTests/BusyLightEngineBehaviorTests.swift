@testable import SentrioCore
import XCTest

final class BusyLightEngineBehaviorTests: XCTestCase {
    func test_shouldRunConnectHello_requiresEnabledAndAddedDevices() {
        XCTAssertFalse(BusyLightEngine.shouldRunConnectHello(busyLightEnabled: false, addedDeviceCount: 1))
        XCTAssertFalse(BusyLightEngine.shouldRunConnectHello(busyLightEnabled: true, addedDeviceCount: 0))
        XCTAssertFalse(BusyLightEngine.shouldRunConnectHello(busyLightEnabled: false, addedDeviceCount: 0))
        XCTAssertTrue(BusyLightEngine.shouldRunConnectHello(busyLightEnabled: true, addedDeviceCount: 2))
    }

    func test_connectHelloSequence_containsShortThreeStepGreeting() {
        let frames = BusyLightEngine.connectHelloSequence()
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames[0].color, BusyLightColor(red: 0, green: 122, blue: 255))
        XCTAssertEqual(frames[1].color, .yellowColor)
        XCTAssertEqual(frames[2].color, .greenColor)
        XCTAssertEqual(frames.map(\.duration), [0.12, 0.12, 0.12])
    }
}

import XCTest
@testable import SentrioCore

final class RulesEngineTests: XCTestCase {

    // MARK: – selectDevice (core logic)

    func test_selectsHighestPriorityConnected() {
        let result = RulesEngine.selectDevice(from: [d("B"), d("C")], priority: ["A", "B", "C"])
        XCTAssertEqual(result?.uid, "B")
    }

    func test_selectsTopWhenAllConnected() {
        let result = RulesEngine.selectDevice(from: [d("C"), d("B"), d("A")], priority: ["A", "B", "C"])
        XCTAssertEqual(result?.uid, "A")
    }

    func test_returnsNilWhenNoPriorityDeviceConnected() {
        XCTAssertNil(RulesEngine.selectDevice(from: [d("B")], priority: ["A", "C"]))
    }

    func test_returnsNilWhenNothingConnected() {
        XCTAssertNil(RulesEngine.selectDevice(from: [], priority: ["A"]))
    }

    func test_returnsNilWhenPriorityEmpty() {
        XCTAssertNil(RulesEngine.selectDevice(from: [d("A")], priority: []))
    }

    func test_returnsNilWhenBothEmpty() {
        XCTAssertNil(RulesEngine.selectDevice(from: [], priority: []))
    }

    func test_singleMatch() {
        XCTAssertEqual(RulesEngine.selectDevice(from: [d("A")], priority: ["A"])?.uid, "A")
    }

    func test_deviceNotInPriorityIsIgnored() {
        XCTAssertNil(RulesEngine.selectDevice(from: [d("X")], priority: ["A", "B"]))
    }

    func test_airPodsScenario_outputAirPodsInputMic() {
        // AirPods connects, but mic is top-priority for input → mic wins for input
        let mic     = d("mic-uid")
        let airPods = d("airpods-uid")
        let builtIn = d("builtin-uid")

        let outputResult = RulesEngine.selectDevice(
            from: [airPods, builtIn],
            priority: ["airpods-uid", "builtin-uid"])
        XCTAssertEqual(outputResult?.uid, "airpods-uid")

        let inputResult = RulesEngine.selectDevice(
            from: [mic],
            priority: ["mic-uid", "airpods-uid"])
        XCTAssertEqual(inputResult?.uid, "mic-uid",
                       "Mic should win for input even though AirPods has higher output priority")
    }

    // MARK: – Disabled device filtering

    func test_disabledDeviceNotSelected() {
        // "A" is highest priority but disabled → B wins
        let eligible = [d("B"), d("C")]  // A is excluded before calling selectDevice
        let result = RulesEngine.selectDevice(from: eligible, priority: ["A", "B", "C"])
        XCTAssertEqual(result?.uid, "B")
    }

    func test_allDevicesDisabledReturnsNil() {
        XCTAssertNil(RulesEngine.selectDevice(from: [], priority: ["A", "B"]))
    }

    // MARK: – Helpers

    private func d(_ uid: String) -> AudioDevice {
        AudioDevice(uid: uid, name: uid, hasInput: true, hasOutput: true)
    }
}

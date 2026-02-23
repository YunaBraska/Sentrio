@testable import SentrioCore
import XCTest

final class BusyLightUSBClientTests: XCTestCase {
    func test_makeOutputReport_programsLoopingStep0AndChecksum() {
        let report = BusyLightUSBClient.makeOutputReport(color: BusyLightColor(red: 255, green: 0, blue: 0))
        XCTAssertEqual(report.count, 64)

        XCTAssertEqual(report[0], 0x10, "cmd should jump to step 0")
        XCTAssertEqual(report[1], 0xFF, "repeat should be 255 for a long-running loop")
        XCTAssertEqual(report[2], 100, "red intensity should be percent (0...100)")
        XCTAssertEqual(report[3], 0)
        XCTAssertEqual(report[4], 0)
        XCTAssertEqual(report[5], 0xFF, "on_time should be 25.5s")
        XCTAssertEqual(report[6], 0x00, "off_time should be 0s")
        XCTAssertEqual(report[7], 0x80, "ringtone should force sound off")

        XCTAssertEqual(report[56], 0)
        XCTAssertEqual(report[57], 0)
        XCTAssertEqual(report[58], 0xFF)
        XCTAssertEqual(report[59], 0xFF)
        XCTAssertEqual(report[60], 0xFF)
        XCTAssertEqual(report[61], 0xFF)

        let checksum = report[0 ..< 62].reduce(0) { $0 + Int($1) }
        XCTAssertEqual(report[62], UInt8((checksum >> 8) & 0xFF))
        XCTAssertEqual(report[63], UInt8(checksum & 0xFF))
    }

    func test_makeOutputReport_scalesComponentsToPercent() {
        // 128/255 ≈ 50.2%, 64/255 ≈ 25.1%
        let report = BusyLightUSBClient.makeOutputReport(color: BusyLightColor(red: 128, green: 64, blue: 0))
        XCTAssertEqual(report[2], 50)
        XCTAssertEqual(report[3], 25)
        XCTAssertEqual(report[4], 0)
    }
}

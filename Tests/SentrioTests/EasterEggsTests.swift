@testable import SentrioCore
import XCTest

final class EasterEggsTests: XCTestCase {
    func test_audioDaemonStirs_0300To0303Inclusive() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))

        func date(_ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(
                calendar.date(from: DateComponents(year: 2026, month: 2, day: 22, hour: hour, minute: minute))
            )
        }

        XCTAssertFalse(try EasterEggs.audioDaemonStirs(now: date(2, 59), calendar: calendar))
        XCTAssertTrue(try EasterEggs.audioDaemonStirs(now: date(3, 0), calendar: calendar))
        XCTAssertTrue(try EasterEggs.audioDaemonStirs(now: date(3, 1), calendar: calendar))
        XCTAssertTrue(try EasterEggs.audioDaemonStirs(now: date(3, 2), calendar: calendar))
        XCTAssertTrue(try EasterEggs.audioDaemonStirs(now: date(3, 3), calendar: calendar))
        XCTAssertFalse(try EasterEggs.audioDaemonStirs(now: date(3, 4), calendar: calendar))
    }
}

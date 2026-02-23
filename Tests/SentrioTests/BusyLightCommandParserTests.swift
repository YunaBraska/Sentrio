@testable import SentrioCore
import XCTest

final class BusyLightCommandParserTests: XCTestCase {
    func test_parsePath_stateAndLogs() {
        XCTAssertEqual(
            tryParse(path: "/v1/busylight"),
            .state
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/state"),
            .state
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/logs"),
            .logs
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/log"),
            .logs
        )
    }

    func test_parsePath_autoAndRules() {
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/auto"),
            .auto
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/rules/on"),
            .rules(true)
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/rules/off"),
            .rules(false)
        )
    }

    func test_parsePath_manualSolidDefaultPeriod() {
        let command = tryParse(path: "/v1/busylight/red", manualDefaultPeriodMilliseconds: 777)
        XCTAssertEqual(
            command,
            .manual(BusyLightAction(mode: .solid, color: .redColor, periodMilliseconds: 777))
        )
    }

    func test_parsePath_manualPulseWithPeriod() {
        let command = tryParse(path: "/v1/busylight/red/pulse/234", manualDefaultPeriodMilliseconds: 600)
        XCTAssertEqual(
            command,
            .manual(BusyLightAction(mode: .pulse, color: .redColor, periodMilliseconds: 234))
        )
    }

    func test_parsePath_manualHexAndRGBColors() {
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/hex/ff7f00", manualDefaultPeriodMilliseconds: 910),
            .manual(BusyLightAction(
                mode: .solid,
                color: BusyLightColor(red: 255, green: 127, blue: 0),
                periodMilliseconds: 910
            ))
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/hex/33cc99/pulse/234", manualDefaultPeriodMilliseconds: 600),
            .manual(BusyLightAction(
                mode: .pulse,
                color: BusyLightColor(red: 51, green: 204, blue: 153),
                periodMilliseconds: 234
            ))
        )
        XCTAssertEqual(
            tryParse(path: "/v1/busylight/rgb/12/34/56/blink/777", manualDefaultPeriodMilliseconds: 600),
            .manual(BusyLightAction(
                mode: .blink,
                color: BusyLightColor(red: 12, green: 34, blue: 56),
                periodMilliseconds: 777
            ))
        )
    }

    func test_parsePath_manualOff() {
        let command = tryParse(path: "/v1/busylight/off", manualDefaultPeriodMilliseconds: 888)
        XCTAssertEqual(
            command,
            .manual(BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: 600))
        )
    }

    func test_parseURL_hostForm() {
        let command = tryParse(url: "sentrio://busylight/red/pulse/400", manualDefaultPeriodMilliseconds: 600)
        XCTAssertEqual(
            command,
            .manual(BusyLightAction(mode: .pulse, color: .redColor, periodMilliseconds: 400))
        )
    }

    func test_parseURL_v1HostForm() {
        let command = tryParse(url: "sentrio://v1/busylight/auto", manualDefaultPeriodMilliseconds: 600)
        XCTAssertEqual(command, .auto)
    }

    func test_parseURL_hexWithEscapedHash() {
        let command = tryParse(url: "sentrio://busylight/hex/%23ff00aa/pulse/500", manualDefaultPeriodMilliseconds: 600)
        XCTAssertEqual(
            command,
            .manual(BusyLightAction(
                mode: .pulse,
                color: BusyLightColor(red: 255, green: 0, blue: 170),
                periodMilliseconds: 500
            ))
        )
    }

    func test_parsePath_failures() {
        assertFailure(path: "/v1/nope/red", expected: .unknownResource, statusCode: 404)
        assertFailure(path: "/v1/busylight/rules", expected: .missingRulesState, statusCode: 400)
        assertFailure(path: "/v1/busylight/rules/maybe", expected: .invalidRulesState("maybe"), statusCode: 400)
        assertFailure(path: "/v1/busylight/notAColor", expected: .unknownColor("notacolor"), statusCode: 400)
        assertFailure(path: "/v1/busylight/hex", expected: .missingHexColor, statusCode: 400)
        assertFailure(path: "/v1/busylight/hex/gg00aa", expected: .invalidHexColor("gg00aa"), statusCode: 400)
        assertFailure(path: "/v1/busylight/rgb/255/0", expected: .missingRGBComponents, statusCode: 400)
        assertFailure(path: "/v1/busylight/rgb/256/0/0", expected: .invalidRGBComponent("256"), statusCode: 400)
        assertFailure(path: "/v1/busylight/red/fade", expected: .unknownMode("fade"), statusCode: 400)
        assertFailure(path: "/v1/busylight/red/pulse/abc", expected: .invalidPeriod("abc"), statusCode: 400)
        assertFailure(path: "/v1/busylight/red/pulse/123/extra", expected: .tooManyPathSegments, statusCode: 400)
        assertFailure(path: "/v1/busylight/rgb/1/2/3/pulse/123/extra", expected: .tooManyPathSegments, statusCode: 400)
    }

    private func tryParse(path: String, manualDefaultPeriodMilliseconds: Int = 600) -> BusyLightCommand {
        switch BusyLightCommandParser.parse(
            path: path,
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        ) {
        case let .success(command):
            return command
        case let .failure(error):
            XCTFail("Unexpected parse failure: \(error)")
            return .state
        }
    }

    private func tryParse(url: String, manualDefaultPeriodMilliseconds: Int = 600) -> BusyLightCommand {
        guard let parsedURL = URL(string: url) else {
            XCTFail("Invalid test URL: \(url)")
            return .state
        }
        switch BusyLightCommandParser.parse(
            url: parsedURL,
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        ) {
        case let .success(command):
            return command
        case let .failure(error):
            XCTFail("Unexpected parse failure: \(error)")
            return .state
        }
    }

    private func assertFailure(
        path: String,
        expected: BusyLightCommandParseError,
        statusCode: Int
    ) {
        let result = BusyLightCommandParser.parse(path: path, manualDefaultPeriodMilliseconds: 600)
        switch result {
        case .success:
            XCTFail("Expected failure for \(path)")
        case let .failure(error):
            XCTAssertEqual(error, expected)
            XCTAssertEqual(error.statusCode, statusCode)
        }
    }
}

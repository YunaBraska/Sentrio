@testable import SentrioCore
import XCTest

final class BusyLightIntentActionBuilderTests: XCTestCase {
    func test_fromPreset_clampsPeriodForAnimatedModes() {
        let action = BusyLightIntentActionBuilder.fromPreset(
            mode: .pulse,
            color: BusyLightColor(red: 12, green: 34, blue: 56),
            periodMilliseconds: 10
        )

        XCTAssertEqual(action.mode, .pulse)
        XCTAssertEqual(action.color, BusyLightColor(red: 12, green: 34, blue: 56))
        XCTAssertEqual(action.periodMilliseconds, 120)
    }

    func test_fromPreset_offForcesOffAction() {
        let action = BusyLightIntentActionBuilder.fromPreset(
            mode: .off,
            color: BusyLightColor(red: 200, green: 100, blue: 50),
            periodMilliseconds: 1_999
        )

        XCTAssertEqual(action.mode, .off)
        XCTAssertEqual(action.color, .offColor)
        XCTAssertEqual(action.periodMilliseconds, 600)
    }

    func test_fromRGB_buildsActionWhenValuesAreValid() throws {
        let action = try BusyLightIntentActionBuilder.fromRGB(
            mode: .blink,
            red: 255,
            green: 127,
            blue: 0,
            periodMilliseconds: 400
        )

        XCTAssertEqual(action.mode, .blink)
        XCTAssertEqual(action.color, BusyLightColor(red: 255, green: 127, blue: 0))
        XCTAssertEqual(action.periodMilliseconds, 400)
    }

    func test_fromRGB_clampsPeriodToMax() throws {
        let action = try BusyLightIntentActionBuilder.fromRGB(
            mode: .pulse,
            red: 1,
            green: 2,
            blue: 3,
            periodMilliseconds: 100_000
        )

        XCTAssertEqual(action.periodMilliseconds, 3_000)
    }

    func test_fromRGB_offModeIgnoresComponents() throws {
        let action = try BusyLightIntentActionBuilder.fromRGB(
            mode: .off,
            red: -1,
            green: 9_999,
            blue: -400,
            periodMilliseconds: 250
        )

        XCTAssertEqual(action.mode, .off)
        XCTAssertEqual(action.color, .offColor)
        XCTAssertEqual(action.periodMilliseconds, 600)
    }

    func test_fromRGB_rejectsOutOfRangeComponents() {
        XCTAssertThrowsError(
            try BusyLightIntentActionBuilder.fromRGB(
                mode: .solid,
                red: -1,
                green: 0,
                blue: 0,
                periodMilliseconds: 600
            )
        ) { error in
            XCTAssertEqual(
                error as? BusyLightIntentActionBuildError,
                .invalidRGBComponent(name: "red", value: -1)
            )
        }

        XCTAssertThrowsError(
            try BusyLightIntentActionBuilder.fromRGB(
                mode: .solid,
                red: 0,
                green: 256,
                blue: 0,
                periodMilliseconds: 600
            )
        ) { error in
            XCTAssertEqual(
                error as? BusyLightIntentActionBuildError,
                .invalidRGBComponent(name: "green", value: 256)
            )
        }

        XCTAssertThrowsError(
            try BusyLightIntentActionBuilder.fromRGB(
                mode: .solid,
                red: 0,
                green: 0,
                blue: 300,
                periodMilliseconds: 600
            )
        ) { error in
            XCTAssertEqual(
                error as? BusyLightIntentActionBuildError,
                .invalidRGBComponent(name: "blue", value: 300)
            )
        }
    }
}

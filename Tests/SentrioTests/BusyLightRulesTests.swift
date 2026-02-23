@testable import SentrioCore
import XCTest

final class BusyLightRulesTests: XCTestCase {
    func test_defaultRules_matchBusyAndIdle() {
        let rules = BusyLightRule.defaultRules()
        XCTAssertEqual(rules.count, 3)

        let idleSignals = BusyLightSignals(microphoneInUse: false, cameraInUse: false, screenRecordingInUse: false)
        XCTAssertFalse(rules[0].matches(using: idleSignals))
        XCTAssertFalse(rules[1].matches(using: idleSignals))
        XCTAssertTrue(rules[2].matches(using: idleSignals))

        let micSignals = BusyLightSignals(microphoneInUse: true, cameraInUse: false, screenRecordingInUse: false)
        XCTAssertTrue(rules[0].matches(using: micSignals))
        XCTAssertFalse(rules[2].matches(using: micSignals))

        let playbackSignals = BusyLightSignals(
            microphoneInUse: false,
            cameraInUse: false,
            screenRecordingInUse: false,
            musicPlaying: true
        )
        XCTAssertFalse(rules[0].matches(using: playbackSignals))
        XCTAssertTrue(rules[1].matches(using: playbackSignals))
        XCTAssertFalse(rules[2].matches(using: playbackSignals))
    }

    func test_expression_normalizesOperatorCount() {
        let expr = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .microphone, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: true),
            ],
            operators: []
        )
        let normalized = expr.normalized()
        XCTAssertEqual(normalized.operators.count, 1)
        XCTAssertEqual(normalized.operators[0], .and)
    }

    func test_expression_evaluatesLeftToRight() {
        // (true OR false) AND false => false (left-to-right)
        let expr = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .microphone, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: true),
                BusyLightCondition(signal: .screenRecording, expectedValue: true),
            ],
            operators: [.or, .and]
        )

        let signals = BusyLightSignals(microphoneInUse: true, cameraInUse: false, screenRecordingInUse: false)
        XCTAssertFalse(expr.evaluate(using: signals))
    }
}

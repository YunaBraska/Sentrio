@testable import SentrioCore
import XCTest

final class BusyLightRuleConditionEditorTests: XCTestCase {
    func test_canonicalized_removesDuplicateSignals_andUsesStableSignalOrder() {
        let expression = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .music, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: false),
                BusyLightCondition(signal: .music, expectedValue: false),
                BusyLightCondition(signal: .microphone, expectedValue: true),
            ],
            operators: [.or, .or, .or]
        )

        let canonicalized = BusyLightRuleConditionEditor.canonicalized(expression)
        XCTAssertEqual(canonicalized.conditions.map(\.signal), [.microphone, .camera, .music])
        XCTAssertEqual(canonicalized.conditions.map(\.expectedValue), [true, false, true])
        XCTAssertEqual(canonicalized.operators, [.or, .or])
    }

    func test_setSignal_enabledAddsCondition_withoutDuplicates() {
        var expression = BusyLightExpression(
            conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
            operators: []
        )

        BusyLightRuleConditionEditor.setSignal(.camera, enabled: true, in: &expression)
        XCTAssertEqual(expression.conditions.map(\.signal), [.microphone, .camera])
        XCTAssertEqual(expression.operators, [.and])

        BusyLightRuleConditionEditor.setSignal(.camera, enabled: true, in: &expression)
        XCTAssertEqual(expression.conditions.map(\.signal), [.microphone, .camera])
        XCTAssertEqual(expression.operators, [.and])
    }

    func test_setSignal_disabledRemovesSignal_andNormalizesOperators() {
        var expression = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .camera, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: false),
                BusyLightCondition(signal: .microphone, expectedValue: true),
            ],
            operators: [.or, .and]
        )

        BusyLightRuleConditionEditor.setSignal(.camera, enabled: false, in: &expression)

        XCTAssertEqual(expression.conditions.map(\.signal), [.microphone])
        XCTAssertEqual(expression.operators, [])
    }

    func test_setExpectedValue_updatesExistingCondition_only() {
        var expression = BusyLightExpression(
            conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
            operators: []
        )

        BusyLightRuleConditionEditor.setExpectedValue(false, for: .microphone, in: &expression)
        XCTAssertEqual(BusyLightRuleConditionEditor.expectedValue(for: .microphone, in: expression), false)

        BusyLightRuleConditionEditor.setExpectedValue(false, for: .camera, in: &expression)
        XCTAssertFalse(BusyLightRuleConditionEditor.isSignalEnabled(.camera, in: expression))
        XCTAssertEqual(expression.conditions.count, 1)
    }

    func test_logicalOperator_defaultsToAnd_forEmptyOrMissingOperators() {
        let empty = BusyLightExpression(conditions: [], operators: [])
        XCTAssertEqual(BusyLightRuleConditionEditor.logicalOperator(in: empty), .and)

        let missing = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .microphone, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: true),
            ],
            operators: []
        )
        XCTAssertEqual(BusyLightRuleConditionEditor.logicalOperator(in: missing), .and)
    }

    func test_setLogicalOperator_appliesToAllConditionLinks() {
        var expression = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .microphone, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: false),
                BusyLightCondition(signal: .music, expectedValue: true),
            ],
            operators: [.and, .or]
        )

        BusyLightRuleConditionEditor.setLogicalOperator(.or, in: &expression)
        XCTAssertEqual(expression.operators, [.or, .or])

        BusyLightRuleConditionEditor.setSignal(.camera, enabled: false, in: &expression)
        BusyLightRuleConditionEditor.setLogicalOperator(.and, in: &expression)
        XCTAssertEqual(expression.operators, [.and])
    }

    func test_selectedSignalCount_usesCanonicalizedConditionCount() {
        let expression = BusyLightExpression(
            conditions: [
                BusyLightCondition(signal: .camera, expectedValue: true),
                BusyLightCondition(signal: .camera, expectedValue: false),
                BusyLightCondition(signal: .music, expectedValue: true),
            ],
            operators: [.or, .or]
        )

        XCTAssertEqual(BusyLightRuleConditionEditor.selectedSignalCount(in: expression), 2)
    }
}

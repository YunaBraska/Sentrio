import Foundation

enum BusyLightRuleConditionEditor {
    static let signalOrder: [BusyLightSignal] = [
        .microphone,
        .camera,
        .screenRecording,
        .music,
    ]

    static func isSignalEnabled(
        _ signal: BusyLightSignal,
        in expression: BusyLightExpression
    ) -> Bool {
        expression.conditions.contains(where: { $0.signal == signal })
    }

    static func expectedValue(
        for signal: BusyLightSignal,
        in expression: BusyLightExpression
    ) -> Bool {
        expression.conditions.first(where: { $0.signal == signal })?.expectedValue ?? true
    }

    static func selectedSignalCount(in expression: BusyLightExpression) -> Int {
        canonicalized(expression).conditions.count
    }

    static func setSignal(
        _ signal: BusyLightSignal,
        enabled: Bool,
        in expression: inout BusyLightExpression
    ) {
        if enabled {
            if !isSignalEnabled(signal, in: expression) {
                expression.conditions.append(BusyLightCondition(signal: signal, expectedValue: true))
            }
        } else {
            expression.conditions.removeAll(where: { $0.signal == signal })
        }
        expression = canonicalized(expression)
    }

    static func setExpectedValue(
        _ expectedValue: Bool,
        for signal: BusyLightSignal,
        in expression: inout BusyLightExpression
    ) {
        guard let index = expression.conditions.firstIndex(where: { $0.signal == signal }) else { return }
        expression.conditions[index].expectedValue = expectedValue
    }

    static func logicalOperator(
        in expression: BusyLightExpression
    ) -> BusyLightLogicalOperator {
        expression.normalized().operators.first ?? .and
    }

    static func setLogicalOperator(
        _ logicalOperator: BusyLightLogicalOperator,
        in expression: inout BusyLightExpression
    ) {
        let normalized = canonicalized(expression)
        let requiredOperators = max(normalized.conditions.count - 1, 0)
        expression.conditions = normalized.conditions
        expression.operators = Array(repeating: logicalOperator, count: requiredOperators)
    }

    static func canonicalized(_ expression: BusyLightExpression) -> BusyLightExpression {
        var conditionsBySignal: [BusyLightSignal: BusyLightCondition] = [:]
        for condition in expression.conditions {
            if conditionsBySignal[condition.signal] == nil {
                conditionsBySignal[condition.signal] = condition
            }
        }

        var orderedConditions: [BusyLightCondition] = []
        for signal in signalOrder {
            if let condition = conditionsBySignal[signal] {
                orderedConditions.append(condition)
            }
        }

        return BusyLightExpression(
            conditions: orderedConditions,
            operators: expression.operators
        ).normalized()
    }
}

import Foundation

// MARK: - Signals

struct BusyLightSignals: Codable, Equatable {
    var microphoneInUse: Bool
    var cameraInUse: Bool
    var screenRecordingInUse: Bool
    var musicPlaying: Bool = false
}

enum BusyLightSignal: String, Codable, CaseIterable, Equatable {
    case microphone
    case camera
    case screenRecording
    case music
}

// MARK: - Actions

public enum BusyLightMode: String, Codable, CaseIterable, Equatable {
    case off
    case solid
    case blink
    case pulse
}

enum BusyLightControlMode: String, Codable, CaseIterable, Equatable {
    case auto
    case manual
}

public struct BusyLightColor: Codable, Equatable, Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let redColor = BusyLightColor(red: 255, green: 0, blue: 0)
    public static let greenColor = BusyLightColor(red: 0, green: 255, blue: 0)
    public static let yellowColor = BusyLightColor(red: 255, green: 190, blue: 0)
    public static let offColor = BusyLightColor(red: 0, green: 0, blue: 0)
}

public struct BusyLightAction: Codable, Equatable {
    /// The output style applied to the BusyLight.
    var mode: BusyLightMode
    /// Used by `.solid`, `.blink`, `.pulse`. Ignored by `.off`.
    var color: BusyLightColor
    /// Used by `.blink` and `.pulse` as the animation period in milliseconds.
    var periodMilliseconds: Int

    public init(mode: BusyLightMode, color: BusyLightColor, periodMilliseconds: Int) {
        self.mode = mode
        self.color = color
        self.periodMilliseconds = periodMilliseconds
    }

    static let defaultBusy = BusyLightAction(mode: .solid, color: .redColor, periodMilliseconds: 600)
    static let defaultPlayback = BusyLightAction(mode: .solid, color: .yellowColor, periodMilliseconds: 600)
    static let defaultIdle = BusyLightAction(mode: .solid, color: .greenColor, periodMilliseconds: 600)
}

// MARK: - Rules

enum BusyLightLogicalOperator: String, Codable, CaseIterable, Equatable {
    case and
    case or
}

struct BusyLightCondition: Codable, Equatable, Identifiable {
    var id: UUID
    var signal: BusyLightSignal
    var expectedValue: Bool

    init(id: UUID = UUID(), signal: BusyLightSignal, expectedValue: Bool) {
        self.id = id
        self.signal = signal
        self.expectedValue = expectedValue
    }

    func evaluate(using signals: BusyLightSignals) -> Bool {
        let actual: Bool = switch signal {
        case .microphone: signals.microphoneInUse
        case .camera: signals.cameraInUse
        case .screenRecording: signals.screenRecordingInUse
        case .music: signals.musicPlaying
        }
        return actual == expectedValue
    }
}

struct BusyLightExpression: Codable, Equatable {
    /// Conditions are evaluated left-to-right.
    /// `operators.count` should be `max(conditions.count - 1, 0)`.
    var conditions: [BusyLightCondition]
    var operators: [BusyLightLogicalOperator]

    func normalized() -> BusyLightExpression {
        if conditions.count <= 1 { return BusyLightExpression(conditions: conditions, operators: []) }
        if operators.count == conditions.count - 1 { return self }

        var ops = operators
        while ops.count < conditions.count - 1 {
            ops.append(.and)
        }
        if ops.count > conditions.count - 1 { ops = Array(ops.prefix(conditions.count - 1)) }
        return BusyLightExpression(conditions: conditions, operators: ops)
    }

    func evaluate(using signals: BusyLightSignals) -> Bool {
        guard !conditions.isEmpty else { return false }
        let normalized = normalized()

        var result = normalized.conditions[0].evaluate(using: signals)
        guard normalized.conditions.count > 1 else { return result }

        for index in 1 ..< normalized.conditions.count {
            let op = normalized.operators[index - 1]
            let value = normalized.conditions[index].evaluate(using: signals)
            switch op {
            case .and: result = result && value
            case .or: result = result || value
            }
        }
        return result
    }
}

struct BusyLightRule: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var expression: BusyLightExpression
    var action: BusyLightAction

    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        expression: BusyLightExpression,
        action: BusyLightAction
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.expression = expression
        self.action = action
    }

    func matches(using signals: BusyLightSignals) -> Bool {
        isEnabled && expression.evaluate(using: signals)
    }

    static func defaultRules() -> [BusyLightRule] {
        let busy = BusyLightRule(
            name: "Busy",
            expression: BusyLightExpression(
                conditions: [
                    BusyLightCondition(signal: .microphone, expectedValue: true),
                    BusyLightCondition(signal: .camera, expectedValue: true),
                    BusyLightCondition(signal: .screenRecording, expectedValue: true),
                ],
                operators: [.or, .or]
            ),
            action: .defaultBusy
        )

        let playback = BusyLightRule(
            name: "Alerts",
            expression: BusyLightExpression(
                conditions: [
                    BusyLightCondition(signal: .music, expectedValue: true),
                ],
                operators: []
            ),
            action: .defaultPlayback
        )

        let idle = BusyLightRule(
            name: "Available",
            expression: BusyLightExpression(
                conditions: [
                    BusyLightCondition(signal: .microphone, expectedValue: false),
                    BusyLightCondition(signal: .camera, expectedValue: false),
                    BusyLightCondition(signal: .screenRecording, expectedValue: false),
                    BusyLightCondition(signal: .music, expectedValue: false),
                ],
                operators: [.and, .and, .and]
            ),
            action: .defaultIdle
        )

        return [busy, playback, idle]
    }
}

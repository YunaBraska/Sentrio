import Foundation

enum BusyLightCommand: Equatable {
    case state
    case logs
    case auto
    case rules(Bool)
    case manual(BusyLightAction)
}

enum BusyLightCommandParseError: Error, Equatable {
    case unknownResource
    case missingRulesState
    case invalidRulesState(String)
    case tooManyPathSegments
    case unknownColor(String)
    case missingHexColor
    case invalidHexColor(String)
    case missingRGBComponents
    case invalidRGBComponent(String)
    case unknownMode(String)
    case invalidPeriod(String)

    var statusCode: Int {
        switch self {
        case .unknownResource:
            404
        default:
            400
        }
    }

    var message: String {
        switch self {
        case .unknownResource:
            "Unknown resource"
        case .missingRulesState:
            "Missing rules state. Use /rules/on or /rules/off"
        case let .invalidRulesState(state):
            "Invalid rules state '\(state)'. Use on/off"
        case .tooManyPathSegments:
            "Too many path segments"
        case let .unknownColor(color):
            "Unknown color '\(color)'"
        case .missingHexColor:
            "Missing hex color. Use /hex/RRGGBB"
        case let .invalidHexColor(color):
            "Invalid hex color '\(color)'. Use RRGGBB"
        case .missingRGBComponents:
            "Missing RGB components. Use /rgb/R/G/B"
        case let .invalidRGBComponent(component):
            "Invalid RGB component '\(component)'. Use 0...255"
        case let .unknownMode(mode):
            "Unknown mode '\(mode)'"
        case let .invalidPeriod(period):
            "Invalid period '\(period)'"
        }
    }
}

enum BusyLightCommandParser {
    private static let hexCharacterSet = CharacterSet(charactersIn: "0123456789abcdef")

    private static let namedColors: [String: BusyLightColor] = [
        "red": .redColor,
        "green": .greenColor,
        "yellow": .yellowColor,
        "orange": BusyLightColor(red: 255, green: 140, blue: 0),
        "blue": BusyLightColor(red: 0, green: 122, blue: 255),
        "purple": BusyLightColor(red: 160, green: 80, blue: 255),
        "pink": BusyLightColor(red: 255, green: 0, blue: 128),
        "cyan": BusyLightColor(red: 0, green: 200, blue: 255),
        "white": BusyLightColor(red: 255, green: 255, blue: 255),
        "off": .offColor,
    ]

    private static let defaultActionPeriodMilliseconds = 600

    static func parse(path: String, manualDefaultPeriodMilliseconds: Int) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        let rawSegments = path.split(separator: "/").map { normalizeSegment(String($0)) }
        return parse(segments: rawSegments, manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds)
    }

    static func parse(url: URL, manualDefaultPeriodMilliseconds: Int) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        var segments: [String] = []
        if let host = url.host?.lowercased(), !host.isEmpty {
            segments.append(normalizeSegment(host))
        }
        segments += url.path.split(separator: "/").map { normalizeSegment(String($0)) }
        return parse(segments: segments, manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds)
    }

    private static func parse(
        segments rawSegments: [String],
        manualDefaultPeriodMilliseconds: Int
    ) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        var segments = rawSegments
        if segments.first == "v1" {
            segments.removeFirst()
        }

        guard !segments.isEmpty else {
            return .success(.state)
        }

        guard segments.first == "busylight" || segments.first == "busyligt" else {
            return .failure(.unknownResource)
        }
        segments.removeFirst()

        if segments.isEmpty || segments[0] == "state" {
            return .success(.state)
        }
        if segments[0] == "logs" || segments[0] == "log" {
            return .success(.logs)
        }
        if segments[0] == "auto" {
            return .success(.auto)
        }
        if segments[0] == "rules" {
            guard segments.count >= 2 else {
                return .failure(.missingRulesState)
            }
            let state = segments[1]
            switch state {
            case "on", "true", "1", "enabled":
                return .success(.rules(true))
            case "off", "false", "0", "disabled":
                return .success(.rules(false))
            default:
                return .failure(.invalidRulesState(state))
            }
        }

        return parseManualAction(
            segments: segments,
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        )
    }

    private static func parseManualAction(
        segments: [String],
        manualDefaultPeriodMilliseconds: Int
    ) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        if segments[0] == "off" {
            guard segments.count == 1 else {
                return .failure(.tooManyPathSegments)
            }
            return .success(.manual(
                BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: defaultActionPeriodMilliseconds)
            ))
        }

        if segments[0] == "hex" {
            return parseHexAction(
                segments: segments,
                manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
            )
        }
        if segments[0] == "rgb" {
            return parseRGBAction(
                segments: segments,
                manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
            )
        }

        guard segments.count <= 3 else {
            return .failure(.tooManyPathSegments)
        }

        guard let color = namedColors[segments[0]] else {
            return .failure(.unknownColor(segments[0]))
        }

        return makeManualCommand(
            color: color,
            modeSegment: segment(segments, at: 1),
            periodSegment: segment(segments, at: 2),
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        )
    }

    private static func parseHexAction(
        segments: [String],
        manualDefaultPeriodMilliseconds: Int
    ) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        guard segments.count >= 2 else {
            return .failure(.missingHexColor)
        }
        guard segments.count <= 4 else {
            return .failure(.tooManyPathSegments)
        }
        let token = segments[1]
        guard let color = parseHexColor(token) else {
            return .failure(.invalidHexColor(token))
        }

        return makeManualCommand(
            color: color,
            modeSegment: segment(segments, at: 2),
            periodSegment: segment(segments, at: 3),
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        )
    }

    private static func parseRGBAction(
        segments: [String],
        manualDefaultPeriodMilliseconds: Int
    ) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        guard segments.count >= 4 else {
            return .failure(.missingRGBComponents)
        }
        guard segments.count <= 6 else {
            return .failure(.tooManyPathSegments)
        }
        guard
            let red = parseRGBComponent(segments[1]),
            let green = parseRGBComponent(segments[2]),
            let blue = parseRGBComponent(segments[3])
        else {
            let invalid = segment(segments, at: 1).flatMap(parseRGBComponent) == nil ? segments[1] :
                segment(segments, at: 2).flatMap(parseRGBComponent) == nil ? segments[2] : segments[3]
            return .failure(.invalidRGBComponent(invalid))
        }
        let color = BusyLightColor(red: red, green: green, blue: blue)

        return makeManualCommand(
            color: color,
            modeSegment: segment(segments, at: 4),
            periodSegment: segment(segments, at: 5),
            manualDefaultPeriodMilliseconds: manualDefaultPeriodMilliseconds
        )
    }

    private static func makeManualCommand(
        color: BusyLightColor,
        modeSegment: String?,
        periodSegment: String?,
        manualDefaultPeriodMilliseconds: Int
    ) -> Result<BusyLightCommand, BusyLightCommandParseError> {
        let mode: BusyLightMode
        if let modeSegment {
            guard let parsed = BusyLightMode(rawValue: modeSegment) else {
                return .failure(.unknownMode(modeSegment))
            }
            mode = parsed
        } else {
            mode = .solid
        }

        let period: Int
        if let periodSegment {
            guard let parsed = Int(periodSegment), parsed > 0 else {
                return .failure(.invalidPeriod(periodSegment))
            }
            period = parsed
        } else {
            period = manualDefaultPeriodMilliseconds
        }

        return .success(.manual(BusyLightAction(mode: mode, color: color, periodMilliseconds: period)))
    }

    private static func parseHexColor(_ token: String) -> BusyLightColor? {
        let normalized = token.hasPrefix("#") ? String(token.dropFirst()) : token
        guard normalized.count == 6 else { return nil }
        guard normalized.unicodeScalars.allSatisfy({ hexCharacterSet.contains($0) }) else { return nil }

        guard
            let red = UInt8(normalized.prefix(2), radix: 16),
            let green = UInt8(normalized.dropFirst(2).prefix(2), radix: 16),
            let blue = UInt8(normalized.suffix(2), radix: 16)
        else {
            return nil
        }

        return BusyLightColor(red: red, green: green, blue: blue)
    }

    private static func parseRGBComponent(_ token: String) -> UInt8? {
        guard let value = Int(token), (0 ... 255).contains(value) else { return nil }
        return UInt8(value)
    }

    private static func normalizeSegment(_ token: String) -> String {
        let decoded = token.removingPercentEncoding ?? token
        return decoded.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func segment(_ segments: [String], at index: Int) -> String? {
        guard segments.indices.contains(index) else { return nil }
        return segments[index]
    }
}

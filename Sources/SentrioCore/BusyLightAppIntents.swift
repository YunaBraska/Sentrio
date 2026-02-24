import AppIntents
import Foundation

enum BusyLightIntegrationError: LocalizedError {
    case unavailable
    case invalidURLScheme(String)
    case unsupportedExternalCommand(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Busy Light is currently unavailable."
        case let .invalidURLScheme(scheme):
            "Unsupported URL scheme '\(scheme)'."
        case let .unsupportedExternalCommand(message):
            message
        }
    }
}

@MainActor
public final class BusyLightIntegrationBridge {
    public static let shared = BusyLightIntegrationBridge()

    private weak var engine: BusyLightEngine?

    private init() {}

    func bind(engine: BusyLightEngine) {
        self.engine = engine
    }

    public func shutdownIfAvailable() {
        engine?.shutdown()
    }

    public func setAuto(trigger: String) throws {
        guard let engine else { throw BusyLightIntegrationError.unavailable }
        engine.enableAutoControl(source: trigger)
    }

    public func setManual(action: BusyLightAction, trigger: String) throws {
        guard let engine else { throw BusyLightIntegrationError.unavailable }
        engine.setManualControl(action: action, source: trigger)
    }

    public func handleIncomingURL(_ url: URL) throws {
        let scheme = url.scheme?.lowercased() ?? ""
        guard scheme == "sentrio" else {
            throw BusyLightIntegrationError.invalidURLScheme(scheme)
        }
        guard let engine else { throw BusyLightIntegrationError.unavailable }

        let source = "Integration URL \(url.absoluteString)"
        let result = engine.handleExternalURL(url, source: source)
        if case let .failure(error) = result {
            throw BusyLightIntegrationError.unsupportedExternalCommand(error.message)
        }
    }
}

enum BusyLightIntentActionBuildError: LocalizedError, Equatable {
    case invalidRGBComponent(name: String, value: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidRGBComponent(name, value):
            "Invalid \(name) value \(value). Use 0...255."
        }
    }
}

enum BusyLightIntentActionBuilder {
    static let minPeriodMilliseconds = 120
    static let maxPeriodMilliseconds = 3000
    static let offPeriodMilliseconds = 600

    static func fromPreset(mode: BusyLightMode, color: BusyLightColor, periodMilliseconds: Int) -> BusyLightAction {
        if mode == .off {
            return BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: offPeriodMilliseconds)
        }
        let period = min(max(periodMilliseconds, minPeriodMilliseconds), maxPeriodMilliseconds)
        return BusyLightAction(mode: mode, color: color, periodMilliseconds: period)
    }

    static func fromRGB(
        mode: BusyLightMode,
        red: Int,
        green: Int,
        blue: Int,
        periodMilliseconds: Int
    ) throws -> BusyLightAction {
        if mode == .off {
            return BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: offPeriodMilliseconds)
        }
        let r = try normalizeComponent(name: "red", value: red)
        let g = try normalizeComponent(name: "green", value: green)
        let b = try normalizeComponent(name: "blue", value: blue)

        let period = min(max(periodMilliseconds, minPeriodMilliseconds), maxPeriodMilliseconds)
        return BusyLightAction(
            mode: mode,
            color: BusyLightColor(red: r, green: g, blue: b),
            periodMilliseconds: period
        )
    }

    private static func normalizeComponent(name: String, value: Int) throws -> UInt8 {
        guard (0 ... 255).contains(value) else {
            throw BusyLightIntentActionBuildError.invalidRGBComponent(name: name, value: value)
        }
        return UInt8(value)
    }
}

@available(macOS 13.0, *)
enum BusyLightShortcutMode: String, AppEnum, CaseIterable {
    case solid
    case blink
    case pulse
    case off

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Mode")
    }

    static var caseDisplayRepresentations: [BusyLightShortcutMode: DisplayRepresentation] = [
        .solid: DisplayRepresentation(title: "Solid"),
        .blink: DisplayRepresentation(title: "Blink"),
        .pulse: DisplayRepresentation(title: "Pulse"),
        .off: DisplayRepresentation(title: "Off"),
    ]

    var busyLightMode: BusyLightMode {
        switch self {
        case .solid: .solid
        case .blink: .blink
        case .pulse: .pulse
        case .off: .off
        }
    }
}

@available(macOS 13.0, *)
enum BusyLightShortcutColor: String, AppEnum, CaseIterable {
    case red
    case green
    case yellow
    case blue
    case white
    case off

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Color")
    }

    static var caseDisplayRepresentations: [BusyLightShortcutColor: DisplayRepresentation] = [
        .red: DisplayRepresentation(title: "Red"),
        .green: DisplayRepresentation(title: "Green"),
        .yellow: DisplayRepresentation(title: "Yellow"),
        .blue: DisplayRepresentation(title: "Blue"),
        .white: DisplayRepresentation(title: "White"),
        .off: DisplayRepresentation(title: "Off"),
    ]

    var busyLightColor: BusyLightColor {
        switch self {
        case .red: .redColor
        case .green: .greenColor
        case .yellow: .yellowColor
        case .blue: BusyLightColor(red: 0, green: 122, blue: 255)
        case .white: BusyLightColor(red: 255, green: 255, blue: 255)
        case .off: .offColor
        }
    }
}

@available(macOS 13.0, *)
struct SetBusyLightAutoIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Busy Light Automatic"
    static let description = IntentDescription("Switches Busy Light to automatic rules mode.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await MainActor.run {
            try BusyLightIntegrationBridge.shared.setAuto(trigger: "Shortcuts/Auto")
        }
        return .result(dialog: "Busy Light is now in automatic mode.")
    }
}

@available(macOS 13.0, *)
struct SetBusyLightManualIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Busy Light Manual"
    static let description = IntentDescription("Sets Busy Light manual mode with color and effect.")

    @Parameter(title: "Color")
    var color: BusyLightShortcutColor

    @Parameter(title: "Mode")
    var mode: BusyLightShortcutMode

    @Parameter(title: "Period (ms)", default: 600)
    var periodMilliseconds: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Set Busy Light to \(\.$color) in \(\.$mode) mode")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let chosenMode = mode.busyLightMode
        let chosenColor = color.busyLightColor

        let action = BusyLightIntentActionBuilder.fromPreset(
            mode: color == .off ? .off : chosenMode,
            color: chosenColor,
            periodMilliseconds: periodMilliseconds
        )

        try await MainActor.run {
            try BusyLightIntegrationBridge.shared.setManual(action: action, trigger: "Shortcuts/Manual")
        }
        return .result(dialog: "Busy Light manual action applied.")
    }
}

@available(macOS 13.0, *)
struct SetBusyLightManualRGBIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Busy Light Manual RGB"
    static let description = IntentDescription("Sets Busy Light manual mode with custom RGB color and effect.")

    @Parameter(title: "Red (0-255)", default: 255)
    var red: Int

    @Parameter(title: "Green (0-255)", default: 0)
    var green: Int

    @Parameter(title: "Blue (0-255)", default: 0)
    var blue: Int

    @Parameter(title: "Mode")
    var mode: BusyLightShortcutMode

    @Parameter(title: "Period (ms)", default: 600)
    var periodMilliseconds: Int

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let action = try BusyLightIntentActionBuilder.fromRGB(
            mode: mode.busyLightMode,
            red: red,
            green: green,
            blue: blue,
            periodMilliseconds: periodMilliseconds
        )
        try await MainActor.run {
            try BusyLightIntegrationBridge.shared.setManual(action: action, trigger: "Shortcuts/Manual RGB")
        }
        return .result(dialog: "Busy Light custom RGB action applied.")
    }
}

@available(macOS 13.0, *)
struct BusyLightAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .orange

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetBusyLightAutoIntent(),
            phrases: [
                "Set Busy Light automatic in \(.applicationName)",
                "Enable Busy Light rules in \(.applicationName)",
            ],
            shortTitle: "Busy Light Auto",
            systemImageName: "lightbulb"
        )

        AppShortcut(
            intent: SetBusyLightManualIntent(),
            phrases: [
                "Set Busy Light manually in \(.applicationName)",
                "Control Busy Light in \(.applicationName)",
            ],
            shortTitle: "Busy Light Manual",
            systemImageName: "lightbulb.max"
        )

        AppShortcut(
            intent: SetBusyLightManualRGBIntent(),
            phrases: [
                "Set Busy Light custom color in \(.applicationName)",
                "Set Busy Light RGB in \(.applicationName)",
            ],
            shortTitle: "Busy Light RGB",
            systemImageName: "paintpalette"
        )
    }
}

@available(macOS 14.0, *)
public struct SentrioCoreAppIntentsPackage: AppIntentsPackage {}

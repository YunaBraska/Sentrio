import AppIntents
import Foundation

enum BusyLightIntegrationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Busy Light is currently unavailable."
        }
    }
}

@MainActor
final class BusyLightIntegrationBridge {
    static let shared = BusyLightIntegrationBridge()

    private weak var engine: BusyLightEngine?

    private init() {}

    func bind(engine: BusyLightEngine) {
        self.engine = engine
    }

    func setAuto(trigger: String) throws {
        guard let engine else { throw BusyLightIntegrationError.unavailable }
        engine.enableAutoControl(source: trigger)
    }

    func setManual(action: BusyLightAction, trigger: String) throws {
        guard let engine else { throw BusyLightIntegrationError.unavailable }
        engine.setManualControl(action: action, source: trigger)
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
        let normalizedPeriod = min(max(periodMilliseconds, 120), 3_000)
        let chosenMode = mode.busyLightMode
        let chosenColor = color.busyLightColor

        let action: BusyLightAction
        if chosenMode == .off || color == .off {
            action = BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: 600)
        } else {
            action = BusyLightAction(mode: chosenMode, color: chosenColor, periodMilliseconds: normalizedPeriod)
        }

        try await MainActor.run {
            try BusyLightIntegrationBridge.shared.setManual(action: action, trigger: "Shortcuts/Manual")
        }
        return .result(dialog: "Busy Light manual action applied.")
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
    }
}

import Combine
import Foundation

struct BusyLightEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var source: String
    var trigger: String
    var message: String
    var controlMode: BusyLightControlMode
    var signals: BusyLightSignals
    var action: BusyLightAction?
    var attemptedDevices: Int
    var failedDevices: Int
}

private struct BusyLightDecision {
    var action: BusyLightAction?
    var trigger: String
}

struct BusyLightHelloFrame: Equatable {
    var color: BusyLightColor
    var duration: TimeInterval
}

private struct BusyLightAPIStateResponse: Codable {
    var busyLightEnabled: Bool
    var rulesEnabled: Bool
    var controlMode: BusyLightControlMode
    var manualAction: BusyLightAction
    var currentAction: BusyLightAction?
    var signals: BusyLightSignals
    var connectedDevices: [BusyLightUSBDevice]
    var apiEnabled: Bool
    var apiPort: Int
    var apiRunning: Bool
    var rules: [BusyLightRule]
}

private struct BusyLightAPIErrorResponse: Codable {
    var error: String
}

enum BusyLightExternalCommandError: Error {
    case parse(String)
    case unsupported(String)

    var message: String {
        switch self {
        case let .parse(message), let .unsupported(message):
            message
        }
    }
}

final class BusyLightEngine: ObservableObject {
    @Published private(set) var connectedDevices: [BusyLightUSBDevice] = []
    @Published private(set) var signals = BusyLightSignals(
        microphoneInUse: false,
        cameraInUse: false,
        screenRecordingInUse: false,
        musicPlaying: false
    )
    @Published private(set) var currentAction: BusyLightAction?
    @Published private(set) var recentEvents: [BusyLightEvent] = []
    @Published private(set) var apiServerRunning = false
    @Published private(set) var apiServerError: String?

    private let settings: AppSettings
    private let usb: BusyLightUSBClient
    private let monitor: BusyLightSignalsMonitor

    private lazy var restServer: BusyLightRESTServer = {
        let server = BusyLightRESTServer { [weak self] request in
            guard let self else {
                return .json(statusCode: 503, object: BusyLightAPIErrorResponse(error: "BusyLight engine unavailable"))
            }
            return handleRESTRequest(request)
        }
        server.onStateChange = { [weak self] running, error in
            guard let self else { return }
            apiServerRunning = running
            apiServerError = error
            if let error {
                appendEvent(
                    source: "REST",
                    trigger: "server",
                    message: "server error: \(error)",
                    action: nil,
                    attemptedDevices: 0,
                    failedDevices: 0
                )
            }
        }
        return server
    }()

    private var cancellables = Set<AnyCancellable>()
    private var animationTimer: Timer?
    private var pulsePhase: Double = 0
    private var previewOverride: BusyLightAction?
    private var previewEndWorkItem: DispatchWorkItem?
    private var lastDeviceIDs = Set<String>()
    private var suppressSettingsApply = false
    private var connectHelloWorkItems: [DispatchWorkItem] = []
    private var isConnectHelloRunning = false
    private var pendingApplyAfterConnectHello: (force: Bool, source: String)?

    private static let previewDuration: TimeInterval = 2.5
    private static let solidKeepaliveInterval: TimeInterval = 20
    private static let maxRecentEvents = 20
    private static let defaultActionPeriodMilliseconds = 600
    private static let connectHelloFrames: [BusyLightHelloFrame] = [
        BusyLightHelloFrame(color: BusyLightColor(red: 0, green: 122, blue: 255), duration: 0.12),
        BusyLightHelloFrame(color: .yellowColor, duration: 0.12),
        BusyLightHelloFrame(color: .greenColor, duration: 0.12),
    ]

    init(audio: AudioManager, settings: AppSettings) {
        self.settings = settings
        usb = BusyLightUSBClient()
        monitor = BusyLightSignalsMonitor(audio: audio)

        usb.$devices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                guard let self else { return }

                let newIDs = Set(devices.map(\.id))
                let added = newIDs.subtracting(lastDeviceIDs)
                lastDeviceIDs = newIDs

                connectedDevices = devices
                handleDeviceUpdate(addedDeviceCount: added.count)
            }
            .store(in: &cancellables)

        monitor.$signals
            .receive(on: DispatchQueue.main)
            .sink { [weak self] signals in
                self?.signals = signals
                self?.applyIfNeeded(force: false, source: "Signals")
            }
            .store(in: &cancellables)

        settings.$busyLightEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFromSettings(source: "Settings") }
            .store(in: &cancellables)

        settings.$busyLightRules
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFromSettings(source: "Rules") }
            .store(in: &cancellables)

        settings.$busyLightControlMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFromSettings(source: "Control") }
            .store(in: &cancellables)

        settings.$busyLightManualAction
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyFromSettings(source: "Manual") }
            .store(in: &cancellables)

        settings.$busyLightAPIEnabled
            .combineLatest(settings.$busyLightAPIPort)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, port in
                self?.configureRESTServer(enabled: enabled, port: port)
            }
            .store(in: &cancellables)

        applyIfNeeded(force: true, source: "Startup")
    }

    deinit {
        shutdown()
    }

    var apiBaseURL: String {
        "http://127.0.0.1:\(settings.busyLightAPIPort)/v1/busylight"
    }

    func preview(_ action: BusyLightAction) {
        previewOverride = action
        schedulePreviewEnd()
        apply(action: action, force: true, source: "Preview", trigger: "preview")
    }

    func clearRecentEvents() {
        recentEvents.removeAll()
    }

    static func shouldRunConnectHello(busyLightEnabled: Bool, addedDeviceCount: Int) -> Bool {
        busyLightEnabled && addedDeviceCount > 0
    }

    static func connectHelloSequence() -> [BusyLightHelloFrame] {
        connectHelloFrames
    }

    func shutdown() {
        cancelConnectHelloSequence()
        previewEndWorkItem?.cancel()
        previewEndWorkItem = nil
        previewOverride = nil
        stopAnimation()
        _ = usb.turnOff()
        restServer.stop()
        apiServerRunning = false
        apiServerError = nil
    }

    // MARK: - External control (App Intents / future integrations)

    func enableAutoControl(source: String) {
        setAutoMode(source: source)
    }

    func setManualControl(action: BusyLightAction, source: String) {
        setManualAction(action, source: source)
    }

    @discardableResult
    func handleExternalURL(_ url: URL, source: String) -> Result<Void, BusyLightExternalCommandError> {
        let parseResult = BusyLightCommandParser.parse(
            url: url,
            manualDefaultPeriodMilliseconds: settings.busyLightManualAction.periodMilliseconds
        )
        switch parseResult {
        case let .failure(error):
            return .failure(.parse(error.message))
        case let .success(command):
            return executeExternalCommand(command, source: source)
        }
    }

    // MARK: - Rules / control mode

    private func applyFromSettings(source: String) {
        guard !suppressSettingsApply else { return }
        applyIfNeeded(force: false, source: source)
    }

    private func desiredDecision() -> BusyLightDecision {
        if let previewOverride {
            return BusyLightDecision(action: previewOverride, trigger: "preview")
        }
        guard settings.busyLightEnabled else {
            return BusyLightDecision(action: nil, trigger: "disabled")
        }

        switch settings.busyLightControlMode {
        case .manual:
            return BusyLightDecision(action: settings.busyLightManualAction, trigger: "manual")
        case .auto:
            for rule in settings.busyLightRules where rule.matches(using: signals) {
                return BusyLightDecision(action: rule.action, trigger: "rule '\(rule.name)'")
            }
            return BusyLightDecision(
                action: BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: Self.defaultActionPeriodMilliseconds),
                trigger: "no rule match"
            )
        }
    }

    private func applyIfNeeded(force: Bool, source: String) {
        if isConnectHelloRunning {
            if let pending = pendingApplyAfterConnectHello {
                pendingApplyAfterConnectHello = (force: pending.force || force, source: source)
            } else {
                pendingApplyAfterConnectHello = (force: force, source: source)
            }
            return
        }
        let decision = desiredDecision()
        apply(action: decision.action, force: force, source: source, trigger: decision.trigger)
    }

    private func apply(action: BusyLightAction?, force: Bool, source: String, trigger: String) {
        if !force, action == currentAction { return }
        currentAction = action

        stopAnimation()
        guard let action else {
            appendEvent(
                source: source,
                trigger: trigger,
                message: "busy light disabled",
                action: nil,
                attemptedDevices: 0,
                failedDevices: 0
            )
            return
        }

        guard !connectedDevices.isEmpty else {
            appendEvent(
                source: source,
                trigger: trigger,
                message: "\(describe(action: action)); no devices connected",
                action: action,
                attemptedDevices: 0,
                failedDevices: 0
            )
            return
        }

        let results: [BusyLightUSBSendResult] = switch action.mode {
        case .off:
            usb.turnOff()
        case .solid:
            startSolid(action)
        case .blink:
            startBlink(action)
        case .pulse:
            startPulse(action)
        }

        let failed = results.filter { !$0.isSuccess }.count
        appendEvent(
            source: source,
            trigger: trigger,
            message: describe(action: action),
            action: action,
            attemptedDevices: results.count,
            failedDevices: failed
        )
    }

    // MARK: - REST API

    private func configureRESTServer(enabled: Bool, port: Int) {
        if !enabled {
            restServer.stop()
            apiServerRunning = false
            apiServerError = nil
            return
        }
        restServer.start(port: port)
    }

    private func handleRESTRequest(_ request: BusyLightRESTRequest) -> BusyLightRESTResponse {
        let method = request.method.uppercased()
        guard method == "GET" || method == "POST" else {
            return .json(statusCode: 405, object: BusyLightAPIErrorResponse(error: "Method not allowed"))
        }

        let parseResult = BusyLightCommandParser.parse(
            path: request.path,
            manualDefaultPeriodMilliseconds: settings.busyLightManualAction.periodMilliseconds
        )
        switch parseResult {
        case let .failure(error):
            return .json(statusCode: error.statusCode, object: BusyLightAPIErrorResponse(error: error.message))
        case let .success(command):
            return executeRESTCommand(command, source: "REST \(request.path)")
        }
    }

    private func executeRESTCommand(_ command: BusyLightCommand, source: String) -> BusyLightRESTResponse {
        switch command {
        case .state:
            return .json(statusCode: 200, object: apiState())
        case .logs:
            return .json(statusCode: 200, object: recentEvents)
        case .auto:
            setAutoMode(source: source)
            return .json(statusCode: 200, object: apiState())
        case let .rules(enabled):
            setRulesEnabled(enabled, source: source)
            return .json(statusCode: 200, object: apiState())
        case let .manual(action):
            setManualAction(action, source: source)
            return .json(statusCode: 200, object: apiState())
        }
    }

    private func executeExternalCommand(
        _ command: BusyLightCommand,
        source: String
    ) -> Result<Void, BusyLightExternalCommandError> {
        switch command {
        case .state, .logs:
            return .failure(.unsupported("Read-only endpoint is not supported for URL/AppleScript control"))
        case .auto:
            setAutoMode(source: source)
            return .success(())
        case let .rules(enabled):
            setRulesEnabled(enabled, source: source)
            return .success(())
        case let .manual(action):
            setManualAction(action, source: source)
            return .success(())
        }
    }

    private func setAutoMode(source: String) {
        performWithoutSettingsApply {
            settings.busyLightControlMode = .auto
        }
        applyIfNeeded(force: true, source: source)
    }

    private func setRulesEnabled(_ enabled: Bool, source: String) {
        if enabled {
            setAutoMode(source: source)
        } else {
            setManualAction(settings.busyLightManualAction, source: source)
        }
    }

    private func setManualAction(_ action: BusyLightAction, source: String) {
        performWithoutSettingsApply {
            settings.busyLightControlMode = .manual
            settings.busyLightManualAction = action
        }
        applyIfNeeded(force: true, source: source)
    }

    private func apiState() -> BusyLightAPIStateResponse {
        BusyLightAPIStateResponse(
            busyLightEnabled: settings.busyLightEnabled,
            rulesEnabled: settings.busyLightControlMode == .auto,
            controlMode: settings.busyLightControlMode,
            manualAction: settings.busyLightManualAction,
            currentAction: currentAction,
            signals: signals,
            connectedDevices: connectedDevices,
            apiEnabled: settings.busyLightAPIEnabled,
            apiPort: settings.busyLightAPIPort,
            apiRunning: apiServerRunning,
            rules: settings.busyLightRules
        )
    }

    // MARK: - Animation

    private func schedulePreviewEnd() {
        previewEndWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            previewOverride = nil
            applyIfNeeded(force: false, source: "Preview")
        }
        previewEndWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewDuration, execute: item)
    }

    private func handleDeviceUpdate(addedDeviceCount: Int) {
        guard Self.shouldRunConnectHello(
            busyLightEnabled: settings.busyLightEnabled,
            addedDeviceCount: addedDeviceCount
        ), !connectedDevices.isEmpty else {
            applyIfNeeded(force: true, source: "Device")
            return
        }

        startConnectHelloSequence()
    }

    private func startConnectHelloSequence() {
        cancelConnectHelloSequence()
        isConnectHelloRunning = true
        stopAnimation()
        pendingApplyAfterConnectHello = nil

        var delay: TimeInterval = 0
        for frame in Self.connectHelloFrames {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = usb.setSolidColor(frame.color)
            }
            connectHelloWorkItems.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            delay += frame.duration
        }

        let completion = DispatchWorkItem { [weak self] in
            guard let self else { return }
            isConnectHelloRunning = false
            connectHelloWorkItems.removeAll()
            let pendingApply = pendingApplyAfterConnectHello
            pendingApplyAfterConnectHello = nil
            applyIfNeeded(
                force: pendingApply?.force ?? true,
                source: pendingApply?.source ?? "Device"
            )
        }
        connectHelloWorkItems.append(completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: completion)
    }

    private func cancelConnectHelloSequence() {
        for item in connectHelloWorkItems {
            item.cancel()
        }
        connectHelloWorkItems.removeAll()
        isConnectHelloRunning = false
        pendingApplyAfterConnectHello = nil
    }

    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        pulsePhase = 0
    }

    private func startSolid(_ action: BusyLightAction) -> [BusyLightUSBSendResult] {
        let results = usb.setSolidColor(action.color)
        animationTimer = Timer.scheduledTimer(withTimeInterval: Self.solidKeepaliveInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            _ = usb.setSolidColor(action.color)
        }
        animationTimer?.tolerance = 1.0
        return results
    }

    private func startBlink(_ action: BusyLightAction) -> [BusyLightUSBSendResult] {
        let halfPeriod = max(Double(action.periodMilliseconds), 120) / 1000.0 / 2.0
        var on = true
        let initial = usb.setSolidColor(action.color)
        animationTimer = Timer.scheduledTimer(withTimeInterval: halfPeriod, repeats: true) { [weak self] _ in
            guard let self else { return }
            on.toggle()
            if on { _ = usb.setSolidColor(action.color) } else { _ = usb.turnOff() }
        }
        animationTimer?.tolerance = min(halfPeriod * 0.2, 0.05)
        return initial
    }

    private func startPulse(_ action: BusyLightAction) -> [BusyLightUSBSendResult] {
        let period = max(Double(action.periodMilliseconds), 200) / 1000.0
        let tick = 1.0 / 15.0

        let initial = usb.setSolidColor(action.color)
        animationTimer = Timer.scheduledTimer(withTimeInterval: tick, repeats: true) { [weak self] _ in
            guard let self else { return }
            pulsePhase += tick / period
            if pulsePhase >= 1 { pulsePhase -= 1 }

            let x = pulsePhase
            let intensity = 0.5 - 0.5 * cos(2 * Double.pi * x)

            let c = BusyLightColor(
                red: UInt8(Double(action.color.red) * intensity),
                green: UInt8(Double(action.color.green) * intensity),
                blue: UInt8(Double(action.color.blue) * intensity)
            )
            _ = usb.setSolidColor(c)
        }
        animationTimer?.tolerance = 0.01
        return initial
    }

    // MARK: - Event log

    private func appendEvent(
        source: String,
        trigger: String,
        message: String,
        action: BusyLightAction?,
        attemptedDevices: Int,
        failedDevices: Int
    ) {
        let event = BusyLightEvent(
            timestamp: Date(),
            source: source,
            trigger: trigger,
            message: message,
            controlMode: settings.busyLightControlMode,
            signals: signals,
            action: action,
            attemptedDevices: attemptedDevices,
            failedDevices: failedDevices
        )

        recentEvents.insert(event, at: 0)
        if recentEvents.count > Self.maxRecentEvents {
            recentEvents = Array(recentEvents.prefix(Self.maxRecentEvents))
        }
    }

    private func describe(action: BusyLightAction) -> String {
        switch action.mode {
        case .off:
            "off"
        case .solid:
            "solid(\(action.color.red),\(action.color.green),\(action.color.blue))"
        case .blink:
            "blink(\(action.color.red),\(action.color.green),\(action.color.blue))/\(action.periodMilliseconds)ms"
        case .pulse:
            "pulse(\(action.color.red),\(action.color.green),\(action.color.blue))/\(action.periodMilliseconds)ms"
        }
    }

    private func performWithoutSettingsApply(_ work: () -> Void) {
        suppressSettingsApply = true
        work()
        DispatchQueue.main.async { [weak self] in
            self?.suppressSettingsApply = false
        }
    }
}

import AppKit
import SwiftUI

struct BusyLightTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var busyLight: BusyLightEngine
    @State private var apiPortText = ""
    @FocusState private var apiPortFocused: Bool

    var body: some View {
        Form {
            Section {
                Toggle(L10n.tr("prefs.busylight.enable"), isOn: $settings.busyLightEnabled)
                Toggle(L10n.tr("prefs.busylight.rules.enable"), isOn: rulesEnabledBinding)

                if !rulesEnabledBinding.wrappedValue {
                    manualActionEditor
                }

                Text(L10n.tr("prefs.busylight.enable.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("prefs.busylight.devices")) {
                if busyLight.connectedDevices.isEmpty {
                    Text(L10n.tr("prefs.busylight.devices.none"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(busyLight.connectedDevices) { device in
                        HStack {
                            Text(device.name)
                            Spacer()
                            Text(String(format: "0x%04X:0x%04X", device.vendorID, device.productID))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section(L10n.tr("prefs.busylight.signals")) {
                signalRow(L10n.tr("prefs.busylight.signal.microphone"), isOn: busyLight.signals.microphoneInUse)
                signalRow(L10n.tr("prefs.busylight.signal.camera"), isOn: busyLight.signals.cameraInUse)
                signalRow(L10n.tr("prefs.busylight.signal.screenRecording"), isOn: busyLight.signals.screenRecordingInUse)
                signalRow(L10n.tr("prefs.busylight.signal.music"), isOn: busyLight.signals.musicPlaying)

                Text(L10n.tr("prefs.busylight.signals.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("prefs.busylight.rules")) {
                if settings.busyLightRules.isEmpty {
                    Text(L10n.tr("prefs.busylight.rules.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(settings.busyLightRules.enumerated()), id: \.element.id) { index, _ in
                        BusyLightRuleEditor(
                            rule: $settings.busyLightRules[index],
                            index: index,
                            total: settings.busyLightRules.count,
                            moveUp: { moveRule(from: index, delta: -1) },
                            moveDown: { moveRule(from: index, delta: 1) },
                            delete: { deleteRule(at: index) }
                        )
                    }
                }

                Button(L10n.tr("action.addRule")) { addRule() }
            }

            Section(L10n.tr("prefs.busylight.api")) {
                Toggle(L10n.tr("prefs.busylight.api.enable"), isOn: $settings.busyLightAPIEnabled)

                HStack {
                    Text(L10n.tr("prefs.busylight.api.port"))
                    Spacer()
                    TextField("", text: apiPortBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                        .multilineTextAlignment(.leading)
                        .monospacedDigit()
                        .focused($apiPortFocused)
                        .onSubmit(commitAPIPortText)
                }

                HStack {
                    Text(L10n.tr("prefs.busylight.api.status"))
                    Spacer()
                    Text(busyLight.apiServerRunning
                        ? L10n.tr("prefs.busylight.api.status.running")
                        : L10n.tr("prefs.busylight.api.status.stopped"))
                        .foregroundStyle(busyLight.apiServerRunning ? .green : .secondary)
                }

                if let apiServerError = busyLight.apiServerError {
                    Text(L10n.format("prefs.busylight.api.lastErrorFormat", apiServerError))
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(L10n.format("prefs.busylight.api.baseURLFormat", busyLight.apiBaseURL))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Text(L10n.tr("prefs.busylight.api.examples"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section(L10n.tr("prefs.busylight.logs")) {
                if busyLight.recentEvents.isEmpty {
                    Text(L10n.tr("prefs.busylight.logs.empty"))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(busyLight.recentEvents) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(event.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Text(event.source)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(event.trigger)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if event.attemptedDevices > 0 {
                                    let ok = max(event.attemptedDevices - event.failedDevices, 0)
                                    Text("\(ok)/\(event.attemptedDevices)")
                                        .font(.caption2)
                                        .foregroundStyle(event.failedDevices == 0 ? .green : .orange)
                                        .monospacedDigit()
                                }
                            }
                            Text(event.message)
                                .font(.caption)
                        }
                    }
                }

                Button(L10n.tr("action.clearLog")) { busyLight.clearRecentEvents() }
                    .disabled(busyLight.recentEvents.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiPortText = String(settings.busyLightAPIPort)
        }
        .onChange(of: settings.busyLightAPIPort) { newValue in
            guard !apiPortFocused else { return }
            apiPortText = String(newValue)
        }
        .onChange(of: apiPortFocused) { focused in
            if !focused { commitAPIPortText() }
        }
    }

    private var manualActionEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker(L10n.tr("prefs.busylight.manualAction"), selection: manualModeBinding) {
                    Text(L10n.tr("prefs.busylight.mode.off")).tag(BusyLightMode.off)
                    Text(L10n.tr("prefs.busylight.mode.solid")).tag(BusyLightMode.solid)
                    Text(L10n.tr("prefs.busylight.mode.blink")).tag(BusyLightMode.blink)
                    Text(L10n.tr("prefs.busylight.mode.pulse")).tag(BusyLightMode.pulse)
                }
                .labelsHidden()
                .frame(width: 160)

                if settings.busyLightManualAction.mode != .off {
                    ColorPicker("", selection: manualColorBinding)
                        .labelsHidden()
                        .frame(width: 44)
                }

                Spacer()

                Button(L10n.tr("action.preview")) {
                    busyLight.preview(settings.busyLightManualAction)
                }
                .disabled(busyLight.connectedDevices.isEmpty)
            }

            if settings.busyLightManualAction.mode == .blink || settings.busyLightManualAction.mode == .pulse {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr("prefs.busylight.speed"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(L10n.format("prefs.busylight.speedValueFormat", settings.busyLightManualAction.periodMilliseconds))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: manualPeriodBinding,
                        in: 120 ... 3_000
                    )
                }
            }
        }
    }

    private func signalRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isOn ? L10n.tr("status.on") : L10n.tr("status.off"))
                .font(.caption)
                .foregroundStyle(isOn ? .green : .secondary)
                .monospacedDigit()
        }
    }

    private func addRule() {
        settings.busyLightRules.append(BusyLightRule(
            name: L10n.tr("prefs.busylight.rule.new"),
            expression: BusyLightExpression(
                conditions: [BusyLightCondition(signal: .microphone, expectedValue: true)],
                operators: []
            ),
            action: .defaultBusy
        ))
    }

    private func deleteRule(at index: Int) {
        guard settings.busyLightRules.indices.contains(index) else { return }
        guard settings.busyLightRules.count > 1 else { return }
        settings.busyLightRules.remove(at: index)
    }

    private func moveRule(from index: Int, delta: Int) {
        let newIndex = index + delta
        guard settings.busyLightRules.indices.contains(index),
              settings.busyLightRules.indices.contains(newIndex)
        else { return }
        settings.busyLightRules.move(
            fromOffsets: IndexSet(integer: index),
            toOffset: newIndex > index ? newIndex + 1 : newIndex
        )
    }

    private var manualModeBinding: Binding<BusyLightMode> {
        Binding(
            get: { settings.busyLightManualAction.mode },
            set: { mode in
                settings.busyLightManualAction.mode = mode
            }
        )
    }

    private var manualPeriodBinding: Binding<Double> {
        Binding(
            get: { Double(settings.busyLightManualAction.periodMilliseconds) },
            set: { settings.busyLightManualAction.periodMilliseconds = Int($0) }
        )
    }

    private var manualColorBinding: Binding<Color> {
        Binding(
            get: { settings.busyLightManualAction.color.swiftUIColor },
            set: { settings.busyLightManualAction.color = BusyLightColor.fromSwiftUIColor($0) }
        )
    }

    private var rulesEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.busyLightControlMode == .auto },
            set: { settings.busyLightControlMode = $0 ? .auto : .manual }
        )
    }

    private var apiPortBinding: Binding<String> {
        Binding(
            get: { apiPortText },
            set: { newValue in
                apiPortText = String(newValue.filter(\.isNumber).prefix(5))
            }
        )
    }

    private func commitAPIPortText() {
        guard !apiPortText.isEmpty else {
            apiPortText = String(settings.busyLightAPIPort)
            return
        }

        guard let parsed = Int(apiPortText) else {
            apiPortText = String(settings.busyLightAPIPort)
            return
        }

        settings.busyLightAPIPort = parsed
        apiPortText = String(settings.busyLightAPIPort)
    }
}

// MARK: - Rule editor

private struct BusyLightRuleEditor: View {
    @EnvironmentObject var busyLight: BusyLightEngine

    @Binding var rule: BusyLightRule
    let index: Int
    let total: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                conditions
                Divider()
                action
            }
            .padding(.vertical, 2)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .help(L10n.tr("prefs.busylight.rule.enableHelp"))

            TextField(L10n.tr("prefs.busylight.rule.namePlaceholder"), text: $rule.name)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
                .environment(\.layoutDirection, .leftToRight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

            Button { moveUp() } label: { Image(systemName: "arrow.up") }
                .buttonStyle(.plain)
                .disabled(index == 0)
                .help(L10n.tr("action.moveUp"))

            Button { moveDown() } label: { Image(systemName: "arrow.down") }
                .buttonStyle(.plain)
                .disabled(index >= total - 1)
                .help(L10n.tr("action.moveDown"))

            Button(role: .destructive) { delete() } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .disabled(total <= 1)
                .help(L10n.tr("action.deleteRule"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("prefs.busylight.conditions"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(rule.expression.conditions.enumerated()), id: \.element.id) { condIndex, _ in
                HStack(spacing: 8) {
                    if condIndex > 0 {
                        Picker("", selection: bindingOperator(at: condIndex - 1)) {
                            Text(L10n.tr("logic.and")).tag(BusyLightLogicalOperator.and)
                            Text(L10n.tr("logic.or")).tag(BusyLightLogicalOperator.or)
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    } else {
                        Text(L10n.tr("logic.when"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)
                    }

                    Picker("", selection: bindingSignal(at: condIndex)) {
                        Text(L10n.tr("prefs.busylight.signal.microphone")).tag(BusyLightSignal.microphone)
                        Text(L10n.tr("prefs.busylight.signal.camera")).tag(BusyLightSignal.camera)
                        Text(L10n.tr("prefs.busylight.signal.screenRecording")).tag(BusyLightSignal.screenRecording)
                        Text(L10n.tr("prefs.busylight.signal.music")).tag(BusyLightSignal.music)
                    }
                    .labelsHidden()
                    .frame(width: 160)

                    Picker("", selection: bindingExpected(at: condIndex)) {
                        Text(L10n.tr("status.on")).tag(true)
                        Text(L10n.tr("status.off")).tag(false)
                    }
                    .labelsHidden()
                    .frame(width: 90)

                    Spacer()

                    Button(role: .destructive) { removeCondition(at: condIndex) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(rule.expression.conditions.count <= 1)
                    .help(L10n.tr("action.removeCondition"))
                }
            }

            Button(L10n.tr("action.addCondition")) { addCondition() }
        }
    }

    private var action: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("prefs.busylight.action"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("", selection: $rule.action.mode) {
                        Text(L10n.tr("prefs.busylight.mode.off")).tag(BusyLightMode.off)
                        Text(L10n.tr("prefs.busylight.mode.solid")).tag(BusyLightMode.solid)
                        Text(L10n.tr("prefs.busylight.mode.blink")).tag(BusyLightMode.blink)
                        Text(L10n.tr("prefs.busylight.mode.pulse")).tag(BusyLightMode.pulse)
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    if rule.action.mode != .off {
                        ColorPicker(
                            L10n.tr("prefs.busylight.color"),
                            selection: bindingColor()
                        )
                        .labelsHidden()
                        .frame(width: 48)
                    }

                    Spacer()

                    Button(L10n.tr("action.preview")) {
                        busyLight.preview(rule.action)
                    }
                    .disabled(busyLight.connectedDevices.isEmpty)
                }

                if rule.action.mode == .blink || rule.action.mode == .pulse {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.tr("prefs.busylight.speed"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(L10n.format("prefs.busylight.speedValueFormat", Int(rule.action.periodMilliseconds)))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(rule.action.periodMilliseconds) },
                                set: { rule.action.periodMilliseconds = Int($0) }
                            ),
                            in: 200 ... 2400
                        )
                    }
                }
            }
        }
    }

    private func addCondition() {
        rule.expression.conditions.append(BusyLightCondition(signal: .camera, expectedValue: true))
        rule.expression.operators.append(.and)
    }

    private func removeCondition(at index: Int) {
        guard rule.expression.conditions.indices.contains(index) else { return }
        guard rule.expression.conditions.count > 1 else { return }
        rule.expression.conditions.remove(at: index)

        if index == 0 {
            if !rule.expression.operators.isEmpty { rule.expression.operators.removeFirst() }
        } else if rule.expression.operators.indices.contains(index - 1) {
            rule.expression.operators.remove(at: index - 1)
        }
    }

    private func bindingOperator(at index: Int) -> Binding<BusyLightLogicalOperator> {
        Binding(
            get: {
                if rule.expression.operators.indices.contains(index) {
                    return rule.expression.operators[index]
                }
                return .and
            },
            set: { newValue in
                let required = max(rule.expression.conditions.count - 1, 0)
                if rule.expression.operators.count < required {
                    while rule.expression.operators.count < required {
                        rule.expression.operators.append(.and)
                    }
                }
                if rule.expression.operators.indices.contains(index) {
                    rule.expression.operators[index] = newValue
                }
            }
        )
    }

    private func bindingSignal(at index: Int) -> Binding<BusyLightSignal> {
        Binding(
            get: {
                rule.expression.conditions.indices.contains(index)
                    ? rule.expression.conditions[index].signal
                    : .microphone
            },
            set: { newValue in
                guard rule.expression.conditions.indices.contains(index) else { return }
                rule.expression.conditions[index].signal = newValue
            }
        )
    }

    private func bindingExpected(at index: Int) -> Binding<Bool> {
        Binding(
            get: {
                rule.expression.conditions.indices.contains(index)
                    ? rule.expression.conditions[index].expectedValue
                    : true
            },
            set: { newValue in
                guard rule.expression.conditions.indices.contains(index) else { return }
                rule.expression.conditions[index].expectedValue = newValue
            }
        )
    }

    private func bindingColor() -> Binding<Color> {
        Binding(
            get: { rule.action.color.swiftUIColor },
            set: { rule.action.color = BusyLightColor.fromSwiftUIColor($0) }
        )
    }
}

private extension BusyLightColor {
    var swiftUIColor: Color {
        Color(
            .sRGB,
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: 1.0
        )
    }

    static func fromSwiftUIColor(_ color: Color) -> BusyLightColor {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.systemGreen
        return BusyLightColor(
            red: UInt8((ns.redComponent * 255).rounded()),
            green: UInt8((ns.greenComponent * 255).rounded()),
            blue: UInt8((ns.blueComponent * 255).rounded())
        )
    }
}

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
                if settings.busyLightManualAction.mode != .off {
                    ColorPicker("", selection: manualColorBinding, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44)
                }

                Picker(L10n.tr("prefs.busylight.manualAction"), selection: manualModeBinding) {
                    Text(L10n.tr("prefs.busylight.mode.off")).tag(BusyLightMode.off)
                    Text(L10n.tr("prefs.busylight.mode.solid")).tag(BusyLightMode.solid)
                    Text(L10n.tr("prefs.busylight.mode.blink")).tag(BusyLightMode.blink)
                    Text(L10n.tr("prefs.busylight.mode.pulse")).tag(BusyLightMode.pulse)
                }
                .labelsHidden()
                .frame(width: 160)

                Spacer()
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
                        in: 120 ... 3000
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
    @Binding var rule: BusyLightRule
    let index: Int
    let total: Int
    let moveUp: () -> Void
    let moveDown: () -> Void
    let delete: () -> Void
    @EnvironmentObject var busyLight: BusyLightEngine

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()
                conditions
                Divider()
                action
                Divider()
                metricsFooter
            }
            .padding(.vertical, 2)
        }
        .onAppear(perform: canonicalizeRuleExpression)
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

            ForEach(BusyLightRuleConditionEditor.signalOrder, id: \.self) { signal in
                HStack(spacing: 10) {
                    Toggle("", isOn: signalEnabledBinding(signal))
                        .labelsHidden()

                    Text(signalLabel(signal))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("", selection: signalExpectedBinding(signal)) {
                        Text(L10n.tr("status.on")).tag(true)
                        Text(L10n.tr("status.off")).tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .disabled(!BusyLightRuleConditionEditor.isSignalEnabled(signal, in: rule.expression))
                }
            }

            HStack(spacing: 10) {
                Text(L10n.tr("logic.when"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: logicalOperatorBinding) {
                    Text(L10n.tr("logic.and")).tag(BusyLightLogicalOperator.and)
                    Text(L10n.tr("logic.or")).tag(BusyLightLogicalOperator.or)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
                .disabled(BusyLightRuleConditionEditor.selectedSignalCount(in: rule.expression) < 2)

                Spacer()
            }
        }
    }

    private var action: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("prefs.busylight.action"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if rule.action.mode != .off {
                        ColorPicker(
                            L10n.tr("prefs.busylight.color"),
                            selection: bindingColor(),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 48)
                    }

                    Picker("", selection: $rule.action.mode) {
                        Text(L10n.tr("prefs.busylight.mode.off")).tag(BusyLightMode.off)
                        Text(L10n.tr("prefs.busylight.mode.solid")).tag(BusyLightMode.solid)
                        Text(L10n.tr("prefs.busylight.mode.blink")).tag(BusyLightMode.blink)
                        Text(L10n.tr("prefs.busylight.mode.pulse")).tag(BusyLightMode.pulse)
                    }
                    .labelsHidden()
                    .frame(width: 140)

                    Spacer()
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

    private var metricsFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let summary = busyLight.ruleMetricsSummary(for: rule.id, now: context.date)
                HStack(spacing: 12) {
                    metricValue(
                        label: L10n.tr("prefs.busylight.rule.metrics.total"),
                        value: BusyLightDurationFormatter.string(milliseconds: Double(summary.totalActiveMilliseconds))
                    )
                    metricValue(
                        label: L10n.tr("prefs.busylight.rule.metrics.avgDay"),
                        value: BusyLightDurationFormatter.string(milliseconds: summary.averagePerDayMilliseconds)
                    )
                    metricValue(
                        label: L10n.tr("prefs.busylight.rule.metrics.avgMonth"),
                        value: BusyLightDurationFormatter.string(milliseconds: summary.averagePerMonthMilliseconds)
                    )
                    metricValue(
                        label: L10n.tr("prefs.busylight.rule.metrics.avgYear"),
                        value: BusyLightDurationFormatter.string(milliseconds: summary.averagePerYearMilliseconds)
                    )
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
    }

    private func metricValue(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value)
                .foregroundStyle(.tertiary)
        }
    }

    private var logicalOperatorBinding: Binding<BusyLightLogicalOperator> {
        Binding(
            get: {
                BusyLightRuleConditionEditor.logicalOperator(in: rule.expression)
            },
            set: { newValue in
                BusyLightRuleConditionEditor.setLogicalOperator(newValue, in: &rule.expression)
            }
        )
    }

    private func signalEnabledBinding(_ signal: BusyLightSignal) -> Binding<Bool> {
        Binding(
            get: {
                BusyLightRuleConditionEditor.isSignalEnabled(signal, in: rule.expression)
            },
            set: { enabled in
                BusyLightRuleConditionEditor.setSignal(
                    signal,
                    enabled: enabled,
                    in: &rule.expression
                )
            }
        )
    }

    private func signalExpectedBinding(_ signal: BusyLightSignal) -> Binding<Bool> {
        Binding(
            get: {
                BusyLightRuleConditionEditor.expectedValue(for: signal, in: rule.expression)
            },
            set: { newValue in
                BusyLightRuleConditionEditor.setExpectedValue(
                    newValue,
                    for: signal,
                    in: &rule.expression
                )
            }
        )
    }

    private func signalLabel(_ signal: BusyLightSignal) -> String {
        switch signal {
        case .microphone:
            L10n.tr("prefs.busylight.signal.microphone")
        case .camera:
            L10n.tr("prefs.busylight.signal.camera")
        case .screenRecording:
            L10n.tr("prefs.busylight.signal.screenRecording")
        case .music:
            L10n.tr("prefs.busylight.signal.music")
        }
    }

    private func canonicalizeRuleExpression() {
        rule.expression = BusyLightRuleConditionEditor.canonicalized(rule.expression)
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

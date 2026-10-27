import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum PreferencesPane: String, Hashable {
    case output
    case input
    case busyLight
    case general
}

// MARK: – Root

struct PreferencesView: View {
    enum RenderMode {
        case native
        case screenshot
    }

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var busyLight: BusyLightEngine
    @EnvironmentObject var appState: AppState
    private let renderMode: RenderMode
    @State private var isWindowActive = false
    @State private var screenshotSelectedPane: PreferencesPane

    init(
        renderMode: RenderMode = .native,
        initialTab: PreferencesPane = .output
    ) {
        self.renderMode = renderMode
        _screenshotSelectedPane = State(initialValue: initialTab)
    }

    var body: some View {
        settingsContainer
            .frame(width: 540, height: 680)
            .background(SentrioChromeBackground().ignoresSafeArea())
            .tint(SentrioVisualStyle.accent)
            .background(
                WindowActivityObserver(
                    onWindowAttached: { window in
                        window.title = selectedPaneTitle
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.styleMask.insert(.fullSizeContentView)
                        window.isMovableByWindowBackground = true
                    },
                    onChange: { active in
                        isWindowActive = active
                        updateInputLevelMonitoringDemand()
                    }
                )
            )
            .onChange(of: settings.showInputLevelMeter) { _ in updateInputLevelMonitoringDemand() }
            .onChange(of: busyLight.connectedDevices.isEmpty) { isEmpty in
                if renderMode == .native, isEmpty, selectedPane.wrappedValue == .busyLight {
                    selectedPane.wrappedValue = .output
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in updateInputLevelMonitoringDemand() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in updateInputLevelMonitoringDemand() }
    }

    private var hasBusyLightTab: Bool {
        !busyLight.connectedDevices.isEmpty
    }

    private var selectedPane: Binding<PreferencesPane> {
        switch renderMode {
        case .native:
            $appState.preferencesPane
        case .screenshot:
            $screenshotSelectedPane
        }
    }

    private var selectedPaneTitle: String {
        switch selectedPane.wrappedValue {
        case .output:
            L10n.tr("label.output")
        case .input:
            L10n.tr("label.input")
        case .busyLight:
            L10n.tr("label.busyLight")
        case .general:
            L10n.tr("label.general")
        }
    }

    private var settingsContainer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(SentrioVisualStyle.brandGradient)
                    .accessibilityHidden(true)
                Text(L10n.tr("prefs.window.title"))
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 4) {
                settingsPaneButton(
                    .output,
                    title: L10n.tr("label.output"),
                    systemImage: "speaker.wave.2"
                )
                settingsPaneButton(
                    .input,
                    title: L10n.tr("label.input"),
                    systemImage: "mic"
                )
                if hasBusyLightTab || renderMode == .screenshot {
                    settingsPaneButton(
                        .busyLight,
                        title: L10n.tr("label.busyLight"),
                        systemImage: "lightbulb"
                    )
                }
                settingsPaneButton(
                    .general,
                    title: L10n.tr("label.general"),
                    systemImage: "gearshape"
                )
            }
            .padding(4)
            .background(SentrioCardBackground(cornerRadius: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            activeTabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .groupBoxStyle(SentrioGroupBoxStyle())
    }

    private func settingsPaneButton(
        _ pane: PreferencesPane,
        title: String,
        systemImage: String
    ) -> some View {
        let isSelected = selectedPane.wrappedValue == pane

        return Button {
            selectedPane.wrappedValue = pane
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? SentrioVisualStyle.accent : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? SentrioVisualStyle.accent.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isSelected ? SentrioVisualStyle.accent.opacity(0.22) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch selectedPane.wrappedValue {
        case .output:
            PriorityTab(isOutput: true)
        case .input:
            PriorityTab(isOutput: false)
        case .busyLight:
            if hasBusyLightTab || renderMode == .screenshot {
                BusyLightTab()
            } else {
                PriorityTab(isOutput: true)
            }
        case .general:
            GeneralTab()
        }
    }

    private func updateInputLevelMonitoringDemand() {
        audio.setInputLevelMonitoringDemand(
            isWindowActive && settings.showInputLevelMeter,
            token: "prefs"
        )
    }
}

// MARK: – Activity summary

private struct ActivitySummaryView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if EasterEggs.audioDaemonStirs() {
                Text(L10n.tr("easter.audioDaemonStirs"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            metricRow(L10n.tr("prefs.footer.autoSwitches"), value: settings.autoSwitchCount)
            metricRow(L10n.tr("prefs.footer.millisecondsSaved"), value: settings.millisecondsSaved)
            metricRow(L10n.tr("prefs.footer.signalIntegrityScore"), value: settings.signalIntegrityScore)

            if let milestone = milestoneMessage {
                Text(milestone)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func metricRow(_ label: String, value: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value, format: .number)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
    }

    private var milestoneMessage: String? {
        let ms = settings.millisecondsSaved
        if ms >= 86_400_000 {
            return L10n.tr("prefs.footer.milestone.defeatedInefficiency")
        }
        if ms >= 3_600_000 {
            return L10n.tr("prefs.footer.milestone.coffeeBreak")
        }
        if ms >= 10000 {
            return L10n.tr("prefs.footer.milestone.tenSeconds")
        }
        return nil
    }
}

// MARK: – Priority Tab

private struct PriorityTab: View {
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager

    /// UID currently being dragged — shared down to each row's drag handle.
    @State private var draggedUID: String?

    private var priority: Binding<[String]> {
        isOutput ? $settings.outputPriority : $settings.inputPriority
    }

    private var disabled: Set<String> {
        isOutput ? settings.disabledOutputDevices : settings.disabledInputDevices
    }

    private var connectedUIDsForRole: Set<String> {
        Set((isOutput ? audio.outputDevices : audio.inputDevices).map(\.uid))
    }

    private var allKnownUIDs: [String] {
        let enabled = priority.wrappedValue
        let extra = (isOutput ? audio.outputDevices : audio.inputDevices)
            .map(\.uid).filter { !enabled.contains($0) && !disabled.contains($0) }
        return collapseGroupedRowsIfNeeded(deduped(enabled + extra))
    }

    private var disabledUIDs: [String] {
        let sorted = disabled.filter { settings.knownDevices[$0] != nil }
            .sorted {
                settings.displayName(for: $0, isOutput: isOutput) <
                    settings.displayName(for: $1, isOutput: isOutput)
            }
        return collapseGroupedRowsIfNeeded(sorted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isOutput
                ? L10n.tr("prefs.priority.output.description")
                : L10n.tr("prefs.priority.input.description"))
                .foregroundStyle(.secondary).font(.callout)

            // ── Volume for this role ───────────────────────────────────────
            volumeSection

            // ── Priority list (custom drag-and-drop — more reliable than List.onMove) ────
            GroupBox {
                VStack(spacing: 0) {
                    sectionHeader(L10n.tr("prefs.priority.section.title"), hint: L10n.tr("prefs.priority.section.hint"))
                    Divider()

                    ScrollView {
                        VStack(spacing: 0) {
                            if allKnownUIDs.isEmpty, disabledUIDs.isEmpty {
                                Text(L10n.tr("menu.noDevices"))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 96)
                            }
                            ForEach(allKnownUIDs, id: \.self) { uid in
                                PriorityRow(
                                    uid: uid,
                                    isOutput: isOutput,
                                    orderedUIDs: allKnownUIDs,
                                    draggedUID: $draggedUID
                                )
                                .background(uid == draggedUID
                                    ? SentrioVisualStyle.accent.opacity(0.08)
                                    : Color.clear)
                                .onDrop(of: [.plainText],
                                        delegate: PriorityDropDelegate(
                                            targetUID: uid,
                                            draggedUID: $draggedUID,
                                            onMove: { sourceUID, targetUID in
                                                settings.reorderPriorityForDrag(uid: sourceUID, over: targetUID, isOutput: isOutput)
                                            }
                                        ))
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .frame(minHeight: 80)

                    // ── Disabled section ─────────────────────────────────
                    if !disabledUIDs.isEmpty {
                        Divider()
                        sectionHeader(L10n.tr("prefs.disabled.section.title"), titleColor: .orange)
                        Divider()
                        VStack(spacing: 0) {
                            ForEach(disabledUIDs, id: \.self) { uid in
                                DisabledRow(uid: uid, isOutput: isOutput)
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 200)
        }
        .padding()
    }

    // MARK: Volume section

    private var volumeSection: some View {
        GroupBox {
            VStack(spacing: 6) {
                // Output volume
                sliderRow(
                    icon: isOutput ? "speaker" : "mic",
                    label: isOutput ? L10n.tr("label.output") : L10n.tr("label.input"),
                    volume: isOutput
                        ? Binding(
                            get: { audio.outputVolume },
                            set: { v in
                                audio.outputVolume = v
                                if let d = audio.defaultOutput {
                                    audio.setVolume(v, for: d, isOutput: true)
                                }
                            }
                        )
                        : Binding(
                            get: { audio.inputVolume },
                            set: { v in
                                audio.inputVolume = v
                                if let d = audio.defaultInput {
                                    audio.setVolume(v, for: d, isOutput: false)
                                }
                            }
                        ),
                    playAction: isOutput ? { SoundLibrary.play(settings.testSound) } : nil,
                    onEditingEnded: isOutput ? { SoundLibrary.play(settings.testSound) } : nil
                )
                if isOutput {
                    if AudioManager.supportsSystemAlertVolumeControl {
                        sliderRow(
                            icon: "bell",
                            label: L10n.tr("label.alert"),
                            volume: Binding(
                                get: { audio.alertVolume },
                                set: { v in
                                    audio.setAlertVolume(v)
                                }
                            ),
                            playAction: { SoundLibrary.play(settings.alertSound) },
                            onEditingEnded: { SoundLibrary.play(settings.alertSound) }
                        )
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "bell")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                                .accessibilityHidden(true)
                            Text(L10n.tr("label.alert"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L10n.tr("action.soundSettings")) {
                                NSWorkspace.shared.open(SystemSettingsLinks.sound)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        } label: {
            Label(isOutput ? L10n.tr("label.volume") : L10n.tr("label.inputGain"),
                  systemImage: isOutput ? "speaker.wave.2" : "mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func sliderRow(
        icon: String,
        label: String,
        volume: Binding<Float>,
        playAction: (() -> Void)? = nil,
        onEditingEnded: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Slider(
                value: volume,
                in: 0 ... 1,
                onEditingChanged: { editing in
                    if !editing {
                        onEditingEnded?()
                    }
                }
            )
            .accessibilityLabel(label)
            .accessibilityValue(Text("\(Int((volume.wrappedValue * 100).rounded()))%"))
            Image(systemName: "\(icon).fill")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
                .accessibilityHidden(true)

            if let playAction {
                Button(action: playAction) {
                    Image(systemName: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("action.playSound"))
                .accessibilityLabel(L10n.tr("action.playSound"))
            }
        }
    }

    // MARK: Helpers

    private func sectionHeader(
        _ title: String,
        hint: String? = nil,
        titleColor: Color = .secondary
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(titleColor)
            Spacer()
            if let hint {
                Text(hint).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func collapseGroupedRowsIfNeeded(_ orderedUIDs: [String]) -> [String] {
        var groupMembersByKey: [String: [String]] = [:]
        for uid in orderedUIDs {
            guard settings.isGroupByModelEnabled(for: uid),
                  let key = settings.modelGroupKey(for: uid)
            else { continue }
            groupMembersByKey[key, default: []].append(uid)
        }

        var collapsedKeys = Set<String>()
        var result: [String] = []

        for uid in orderedUIDs {
            guard settings.isGroupByModelEnabled(for: uid),
                  let key = settings.modelGroupKey(for: uid),
                  let members = groupMembersByKey[key],
                  members.count > 1
            else {
                result.append(uid)
                continue
            }

            let activeMembers = members.filter { connectedUIDsForRole.contains($0) }
            if activeMembers.count == members.count {
                // If every known row in this group is currently active, grouping has no visual effect.
                result.append(uid)
                continue
            }

            guard !collapsedKeys.contains(key) else { continue }
            let representative = activeMembers.first ?? members.first ?? uid
            guard uid == representative else { continue }
            result.append(uid)
            collapsedKeys.insert(key)
        }

        return result
    }

    private func deduped(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}

// MARK: – Priority Row (enabled)

private struct PriorityRow: View {
    let uid: String
    let isOutput: Bool
    let orderedUIDs: [String]
    @Binding var draggedUID: String?

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var appState: AppState

    @State private var showIconPicker = false
    @State private var showRenamePopover = false
    @State private var pendingName = ""
    @State private var isShowingForgetConfirmation = false

    private var name: String {
        settings.displayName(for: uid, isOutput: isOutput, fallbackName: device?.name)
    }

    private var device: AudioDevice? {
        (isOutput ? audio.outputDevices : audio.inputDevices).first { $0.uid == uid }
    }

    private var isConnected: Bool {
        device != nil
    }

    private var connectedUIDs: Set<String> {
        Set(audio.outputDevices.map(\.uid) + audio.inputDevices.map(\.uid))
    }

    private var canForget: Bool {
        settings.canForgetDevice(uid: uid, connectedUIDs: connectedUIDs)
    }

    private var isGroupByModelAvailable: Bool {
        settings.modelGroupKey(for: uid) != nil
    }

    private var isGroupByModelEnabled: Bool {
        settings.isGroupByModelEnabled(for: uid)
    }

    private var groupByModelActionTitle: String {
        let base = L10n.tr("action.groupByModel")
        let count = settings.groupByModelDeviceCount(for: uid)
        return count > 1 ? "\(base) (\(count))" : base
    }

    private var requiresManualConnect: Bool {
        guard let device else { return false }
        return audio.requiresManualConnection(device)
    }

    var body: some View {
        HStack(spacing: 8) {
            // ── Drag handle ──────────────────────────────────────────
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 20, height: 36)
                .contentShape(Rectangle())
                .onDrag {
                    draggedUID = uid
                    return NSItemProvider(object: uid as NSString)
                }
                .help(L10n.tr("prefs.dragToReorder"))
                .accessibilityHidden(true)

            // Connection dot
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            // Icon button — volume-reactive for active output speaker icons
            let displayedIcon = (isOutput && device?.uid == audio.defaultOutput?.uid)
                ? AudioDevice.volumeAdaptedIcon(
                    effectiveIcon,
                    volume: audio.outputVolume,
                    isMuted: audio.isOutputMuted
                )
                : effectiveIcon
            Button { showIconPicker = true } label: {
                Image(systemName: displayedIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isConnected ? SentrioVisualStyle.accent : .secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(device.flatMap(\.iconBaseName).map { L10n.format("prefs.iconHelp.withCoreAudioFormat", $0) }
                ?? L10n.tr("prefs.iconHelp.noCoreAudio"))
            .accessibilityLabel(L10n.tr("action.chooseIcon"))
            .popover(isPresented: $showIconPicker, arrowEdge: .trailing) {
                IconPickerPopover(uid: uid, isOutput: isOutput)
                    .environmentObject(settings)
                    .padding(12)
            }

            // Name + rename button
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(isConnected ? .primary : .secondary)
                    .lineLimit(1)
                    .popover(isPresented: $showRenamePopover, arrowEdge: .trailing) {
                        RenamePopover(
                            uid: uid, isOutput: isOutput,
                            originalName: settings.knownDevices[uid] ?? device?.name ?? uid,
                            name: $pendingName,
                            isPresented: $showRenamePopover
                        )
                        .environmentObject(settings)
                        .padding(14)
                    }

                HStack(spacing: 6) {
                    if let dev = device {
                        if dev.uid == (isOutput ? audio.defaultOutput?.uid : audio.defaultInput?.uid) {
                            Text(L10n.tr("status.active"))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(SentrioVisualStyle.accent)
                        } else {
                            Text(L10n.tr("status.connected"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(dev.transportType.label)
                            .font(.caption2).foregroundStyle(.tertiary)
                        if requiresManualConnect {
                            Label(L10n.tr("label.manualConnect"), systemImage: "hand.tap")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if !dev.batteryStates.isEmpty {
                            BatteryStatesInlineView(states: dev.batteryStates)
                        }
                    } else {
                        Text(L10n.tr("status.disconnected"))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let vol = settings.savedVolume(for: uid, isOutput: isOutput) {
                        Text(L10n.format("prefs.savedVolumeFormat", Int(vol * 100)))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Mini level bar — only for the active device
            if !isOutput,
               device?.uid == audio.defaultInput?.uid,
               settings.showInputLevelMeter
            {
                MiniLevelBar(
                    level: audio.inputLevel,
                    isOutput: false
                )
                .frame(width: 36, height: 8)
            }

            Menu {
                if requiresManualConnect, let dev = device {
                    Button(L10n.tr("action.connectNow")) {
                        appState.rules.switchTo(dev, isInput: !isOutput)
                    }
                    Divider()
                }
                Button(L10n.tr("action.moveUp")) { move(by: -1) }
                    .disabled(moveTarget(direction: -1) == nil)
                Button(L10n.tr("action.moveDown")) { move(by: 1) }
                    .disabled(moveTarget(direction: 1) == nil)
                Divider()
                Button(L10n.tr("action.rename")) {
                    pendingName = settings.displayName(for: uid, isOutput: isOutput, fallbackName: device?.name)
                    showRenamePopover = true
                }
                iconPickerMenu
                Divider()
                Button(L10n.tr("action.hideDevice")) {
                    settings.hideDevice(uid: uid, isOutput: isOutput)
                }
                Button(L10n.tr("action.forgetDevice")) {
                    isShowingForgetConfirmation = true
                }
                .disabled(!canForget)
                Button {
                    settings.setGroupByModelEnabled(!isGroupByModelEnabled, for: uid)
                } label: {
                    if isGroupByModelEnabled {
                        Label(groupByModelActionTitle, systemImage: "checkmark")
                    } else {
                        Text(groupByModelActionTitle)
                    }
                }
                .disabled(!isGroupByModelAvailable)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.tr("action.deviceActions"))
            .accessibilityLabel(L10n.tr("action.deviceActions"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(isConnected ? 1 : 0.6)
        .alert(L10n.tr("action.forgetDevice"), isPresented: $isShowingForgetConfirmation) {
            Button(L10n.tr("action.forgetDevice"), role: .destructive) {
                settings.forgetDevice(uid: uid, connectedUIDs: connectedUIDs)
            }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        }
    }

    private func moveTarget(direction: Int) -> String? {
        MenuPriorityReorderPath.targetUID(
            for: uid,
            direction: direction,
            orderedUIDs: orderedUIDs
        )
    }

    private func move(by direction: Int) {
        guard let targetUID = moveTarget(direction: direction) else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            settings.reorderPriorityForDrag(uid: uid, over: targetUID, isOutput: isOutput)
        }
    }

    private var effectiveIcon: String {
        guard let dev = device else {
            return settings.deviceIcons[uid]?[isOutput ? "output" : "input"]
                ?? settings.defaultIconName(for: uid, isOutput: isOutput)
        }
        return settings.iconName(for: dev, isOutput: isOutput)
    }

    private var iconPickerMenu: some View {
        Menu(L10n.tr("action.setIcon")) {
            Button(L10n.tr("action.resetToDefault")) { settings.clearIcon(for: uid, isOutput: isOutput) }
            Divider()
            ForEach(AppSettings.iconOptions, id: \.symbol) { opt in
                Button {
                    settings.setIcon(opt.symbol, for: uid, isOutput: isOutput)
                } label: {
                    Label(L10n.tr(opt.labelKey), systemImage: opt.symbol)
                }
            }
        }
    }
}

// MARK: – Rename Popover

private struct RenamePopover: View {
    let uid: String
    let isOutput: Bool
    let originalName: String
    @Binding var name: String
    @Binding var isPresented: Bool

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("action.rename")).font(.headline)
            Text(isOutput ? L10n.tr("prefs.rename.subtitle.output") : L10n.tr("prefs.rename.subtitle.input"))
                .font(.caption).foregroundStyle(.secondary)

            TextField(L10n.tr("prefs.rename.deviceNamePlaceholder"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { save() }

            HStack {
                Button(L10n.tr("action.reset")) {
                    settings.clearCustomName(for: uid, isOutput: isOutput)
                    name = originalName
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()

                Button(L10n.tr("action.cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button(L10n.tr("action.save"), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        settings.setCustomName(name, for: uid, isOutput: isOutput)
        isPresented = false
    }
}

// MARK: – Disabled Row

//
// Column layout mirrors PriorityRow exactly so both sections feel like one list:
//   [drag placeholder 20] [dot 7] [icon 24] [name VStack] [Spacer] [gear actions]

private struct DisabledRow: View {
    let uid: String
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager

    @State private var showRenamePopover = false
    @State private var pendingName = ""
    @State private var isShowingForgetConfirmation = false

    private var device: AudioDevice? {
        (isOutput ? audio.outputDevices : audio.inputDevices).first { $0.uid == uid }
    }

    private var isConnected: Bool {
        device != nil
    }

    private var connectedUIDs: Set<String> {
        Set(audio.outputDevices.map(\.uid) + audio.inputDevices.map(\.uid))
    }

    private var canForget: Bool {
        settings.canForgetDevice(uid: uid, connectedUIDs: connectedUIDs)
    }

    private var isGroupByModelAvailable: Bool {
        settings.modelGroupKey(for: uid) != nil
    }

    private var isGroupByModelEnabled: Bool {
        settings.isGroupByModelEnabled(for: uid)
    }

    private var groupByModelActionTitle: String {
        let base = L10n.tr("action.groupByModel")
        let count = settings.groupByModelDeviceCount(for: uid)
        return count > 1 ? "\(base) (\(count))" : base
    }

    /// Best-effort icon: live device → custom stored → generic fallback.
    private var iconName: String {
        if let dev = device {
            return settings.iconName(for: dev, isOutput: isOutput)
        }
        return settings.deviceIcons[uid]?[isOutput ? "output" : "input"]
            ?? settings.defaultIconName(for: uid, isOutput: isOutput)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle placeholder — keeps columns aligned with PriorityRow
            Color.clear.frame(width: 20, height: 36)

            // Status dot: orange = disabled (mirrors green/grey dot in PriorityRow)
            Circle()
                .fill(Color.orange.opacity(0.75))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            // Device icon in the same column as PriorityRow's icon button
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayName(for: uid, isOutput: isOutput, fallbackName: device?.name))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .popover(isPresented: $showRenamePopover, arrowEdge: .trailing) {
                        RenamePopover(
                            uid: uid, isOutput: isOutput,
                            originalName: settings.knownDevices[uid] ?? device?.name ?? uid,
                            name: $pendingName,
                            isPresented: $showRenamePopover
                        )
                        .environmentObject(settings)
                        .padding(14)
                    }
                HStack(spacing: 6) {
                    Text(isConnected ? L10n.tr("status.connected") : L10n.tr("status.disconnected"))
                        .font(.caption2)
                        .foregroundStyle(isConnected
                            ? AnyShapeStyle(.green.opacity(0.8))
                            : AnyShapeStyle(.tertiary))
                    if let dev = device, !dev.batteryStates.isEmpty {
                        BatteryStatesInlineView(states: dev.batteryStates)
                    }
                }
            }

            Spacer()

            Menu {
                Button(L10n.tr("action.rename")) {
                    pendingName = settings.displayName(for: uid, isOutput: isOutput, fallbackName: device?.name)
                    showRenamePopover = true
                }
                iconPickerMenu
                Divider()
                Button(L10n.tr("action.enable")) {
                    settings.enableDevice(uid: uid, isOutput: isOutput)
                }
                Button(L10n.tr("action.forgetDevice")) {
                    isShowingForgetConfirmation = true
                }
                .disabled(!canForget)
                Button {
                    settings.setGroupByModelEnabled(!isGroupByModelEnabled, for: uid)
                } label: {
                    if isGroupByModelEnabled {
                        Label(groupByModelActionTitle, systemImage: "checkmark")
                    } else {
                        Text(groupByModelActionTitle)
                    }
                }
                .disabled(!isGroupByModelAvailable)
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.tr("action.deviceActions"))
            .accessibilityLabel(L10n.tr("action.deviceActions"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(0.82)
        .alert(L10n.tr("action.forgetDevice"), isPresented: $isShowingForgetConfirmation) {
            Button(L10n.tr("action.forgetDevice"), role: .destructive) {
                settings.forgetDevice(uid: uid, connectedUIDs: connectedUIDs)
            }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        }
    }

    private var iconPickerMenu: some View {
        Menu(L10n.tr("action.setIcon")) {
            Button(L10n.tr("action.resetToDefault")) { settings.clearIcon(for: uid, isOutput: isOutput) }
            Divider()
            ForEach(AppSettings.iconOptions, id: \.symbol) { opt in
                Button {
                    settings.setIcon(opt.symbol, for: uid, isOutput: isOutput)
                } label: {
                    Label(L10n.tr(opt.labelKey), systemImage: opt.symbol)
                }
            }
        }
    }
}

// MARK: – Icon Picker Popover

struct IconPickerPopover: View {
    let uid: String
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.tr("action.chooseIcon")).font(.headline)
                Spacer()
                Button(L10n.tr("action.reset")) {
                    settings.clearIcon(for: uid, isOutput: isOutput)
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AppSettings.iconOptions, id: \.symbol) { opt in
                    let isCurrent = settings.deviceIcons[uid]?[isOutput ? "output" : "input"] == opt.symbol
                    Button {
                        settings.setIcon(opt.symbol, for: uid, isOutput: isOutput)
                        dismiss()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: opt.symbol)
                                .font(.title2)
                                .frame(height: 26)
                            Text(L10n.tr(opt.labelKey))
                                .font(.system(size: 7))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(width: 52, height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isCurrent
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.secondary.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isCurrent ? Color.accentColor : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr(opt.labelKey))
                }
            }
        }
        .frame(width: 290)
    }
}

// MARK: – General Tab

private struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?
    @State private var importExportStatus: String?
    @State private var importExportStatusIsError = false
    @State private var lastExportURL: URL?
    @State private var isShowingClearVolumeMemoryConfirmation = false

    var body: some View {
        Form {
            // ── Auto-switching ──────────────────────────────────────
            Section {
                Toggle(L10n.tr("prefs.general.enableAutoSwitching"), isOn: $settings.isAutoMode)
                Text(L10n.tr("prefs.general.enableAutoSwitching.description"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // ── Visibility ──────────────────────────────────────────
            Section(L10n.tr("prefs.general.visibility")) {
                Toggle(L10n.tr("prefs.general.hideMenuBarIcon"), isOn: $settings.hideMenuBarIcon)
                Text(L10n.tr("prefs.general.hideMenuBarIcon.description"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            // ── Language ────────────────────────────────────────────
            Section(L10n.tr("prefs.language.title")) {
                Picker(L10n.tr("prefs.language.title"), selection: $settings.appLanguage) {
                    Text(L10n.tr("prefs.language.system")).tag("system")
                    Divider()
                    ForEach(L10n.supportedLocalizations, id: \.self) { loc in
                        Text(L10n.languageDisplayName(loc)).tag(loc)
                    }
                }
                .pickerStyle(.menu)

                Text(L10n.tr("prefs.language.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── System ──────────────────────────────────────────────
            Section(L10n.tr("prefs.general.system")) {
                Toggle(
                    L10n.tr("prefs.general.launchAtLogin"),
                    isOn: Binding(
                        get: { launchAtLogin },
                        set: { enabled in
                            switch settings.setLaunchAtLogin(enabled) {
                            case let .success(actualValue):
                                launchAtLogin = actualValue
                                launchAtLoginError = nil
                            case let .failure(error):
                                launchAtLogin = settings.isLaunchAtLoginEnabled
                                launchAtLoginError = error.localizedDescription
                            }
                        }
                    )
                )
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button(L10n.tr("action.openSoundSettings")) {
                    NSWorkspace.shared.open(SystemSettingsLinks.sound)
                }
            }

            // ── Privacy ─────────────────────────────────────────────
            Section(L10n.tr("prefs.general.privacy")) {
                Toggle(L10n.tr("prefs.general.showInputLevelMeter"), isOn: $settings.showInputLevelMeter)
                Text(L10n.tr("prefs.general.showInputLevelMeter.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if settings.showInputLevelMeter, audio.inputLevelMonitoringProblem {
                    Text(L10n.tr("prefs.general.inputLevelUnavailable"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button(L10n.tr("action.openMicrophoneSettings")) {
                        NSWorkspace.shared.open(SystemSettingsLinks.microphonePrivacy)
                    }
                }
                Button(L10n.tr("action.privacyPolicy")) {
                    openSite("https://yunabraska.github.io/Sentrio/privacy/")
                }
            }

            // ── Import / export ─────────────────────────────────────
            Section(L10n.tr("prefs.general.settings")) {
                Button(L10n.tr("action.exportSettings")) { exportSettings() }
                Button(L10n.tr("action.importSettings")) { importSettings() }
                if let importExportStatus {
                    Text(importExportStatus)
                        .font(.caption)
                        .foregroundStyle(importExportStatusIsError ? .red : .secondary)
                }
                if let lastExportURL {
                    Button(L10n.tr("action.showInFinder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([lastExportURL])
                    }
                }
                Text(L10n.tr("prefs.general.settings.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Volume memory ────────────────────────────────────────
            Section(L10n.tr("prefs.general.volumeMemory")) {
                Text(L10n.tr("prefs.general.volumeMemory.description"))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.tr("action.clearVolumeMemory")) {
                    isShowingClearVolumeMemoryConfirmation = true
                }
                .foregroundStyle(.red)
            }

            // ── Activity ────────────────────────────────────────────
            Section(L10n.tr("prefs.general.activity")) {
                ActivitySummaryView()
                    .environmentObject(settings)
                Button(L10n.tr("action.resetFooterStats")) { settings.resetFooterStats() }
                    .foregroundStyle(.red)
                    .disabled(!canResetFooterStats)
            }

            // ── About ────────────────────────────────────────────────
            Section(L10n.tr("prefs.general.about")) {
                Text(L10n.tr("prefs.general.about.description"))
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Text(L10n.tr("prefs.general.about.version"))
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                    let display = (build == "—" || build.isEmpty || build == version)
                        ? version
                        : "\(version) (\(build))"
                    Text(display).foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.tr("prefs.general.about.author"))
                    Spacer()
                    Text("Yuna Morgenstern").foregroundStyle(.secondary)
                }
                HStack {
                    Text(L10n.tr("prefs.general.about.license"))
                    Spacer()
                    Text(L10n.tr("prefs.general.about.licenseValue")).foregroundStyle(.secondary)
                }

                Button(L10n.tr("action.viewSourceOnGitHub")) {
                    openSite("https://github.com/YunaBraska/Sentrio")
                }
                #if !SENTRIO_APP_STORE
                    Button(L10n.tr("action.buyMeCoffee")) {
                        openSite("https://github.com/sponsors/YunaBraska?frequency=one-time")
                    }
                #endif
                Button(L10n.tr("action.reportIssue")) {
                    openSite("https://github.com/YunaBraska/Sentrio/issues/new")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear {
            launchAtLogin = settings.isLaunchAtLoginEnabled
        }
        .alert(
            L10n.tr("action.clearVolumeMemory"),
            isPresented: $isShowingClearVolumeMemoryConfirmation
        ) {
            Button(L10n.tr("action.clearVolumeMemory"), role: .destructive) {
                settings.volumeMemory = [:]
            }
            Button(L10n.tr("action.cancel"), role: .cancel) {}
        }
    }

    private func openSite(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "sentrio-settings.json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.exportSettings(to: url)
            lastExportURL = url
            setImportExportStatus(L10n.tr("status.exportedSettings"), isError: false)
        } catch {
            lastExportURL = nil
            setImportExportStatus(L10n.format("error.exportFailedFormat", error.localizedDescription), isError: true)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.importSettings(from: url)
            setImportExportStatus(L10n.tr("status.importedSettings"), isError: false)
        } catch {
            setImportExportStatus(L10n.format("error.importFailedFormat", error.localizedDescription), isError: true)
        }
    }

    private func setImportExportStatus(_ message: String, isError: Bool) {
        importExportStatus = message
        importExportStatusIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [message] in
            if importExportStatus == message {
                importExportStatus = nil
            }
        }
    }

    private var canResetFooterStats: Bool {
        settings.autoSwitchCount != 0 ||
            settings.millisecondsSaved != 0 ||
            settings.signalIntegrityScore != 0
    }
}

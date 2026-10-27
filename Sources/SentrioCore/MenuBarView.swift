import AppKit
import SwiftUI

private enum MenuSurface: Hashable {
    case sound
    case busyLight
}

enum MenuPriorityReorderPath {
    static func targetUID(for sourceUID: String, direction: Int, orderedUIDs: [String]) -> String? {
        guard direction == -1 || direction == 1 else { return nil }
        guard let sourceIndex = orderedUIDs.firstIndex(of: sourceUID) else { return nil }
        let targetIndex = sourceIndex + direction
        guard orderedUIDs.indices.contains(targetIndex) else { return nil }
        return orderedUIDs[targetIndex]
    }
}

enum MenuPriorityRanker {
    static func rankMap(for visibleUIDs: [String]) -> [String: Int] {
        var ranks: [String: Int] = [:]
        var nextRank = 1
        for uid in visibleUIDs where ranks[uid] == nil {
            ranks[uid] = nextRank
            nextRank += 1
        }
        return ranks
    }
}

// MARK: – Root

struct MenuBarView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var busyLight: BusyLightEngine
    @EnvironmentObject var appState: AppState
    @State private var draggedOutputUID: String?
    @State private var draggedInputUID: String?
    @State private var selectedSurface: MenuSurface = .sound

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if !busyLight.connectedDevices.isEmpty {
                Divider()
                surfacePicker
            }
            Divider()
            if selectedSurface == .busyLight, !busyLight.connectedDevices.isEmpty {
                busyLightSurface
            } else {
                soundSurface
            }
            Divider()
            footerRow
        }
        .frame(width: 370)
        .background(SentrioBackdrop().ignoresSafeArea())
        .tint(SentrioVisualStyle.accent)
        .onChange(of: busyLight.connectedDevices.isEmpty) { isEmpty in
            if isEmpty {
                selectedSurface = .sound
            }
        }
    }

    // MARK: – Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(SentrioVisualStyle.brandGradient)
                .accessibilityHidden(true)
            Text("Sentrio")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            Toggle(L10n.tr("label.auto"), isOn: $settings.isAutoMode)
                .toggleStyle(.switch).controlSize(.mini)
                .help(L10n.tr("menu.autoHelp"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(SentrioChromeBackground())
    }

    private var surfacePicker: some View {
        Picker("", selection: $selectedSurface) {
            Label(L10n.tr("menu.sound"), systemImage: "speaker.wave.2")
                .tag(MenuSurface.sound)
            Label(L10n.tr("label.busyLight"), systemImage: "lightbulb")
                .tag(MenuSurface.busyLight)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var soundSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            masterVolumeSection
            Divider()
            deviceSection(title: L10n.tr("label.output"), systemImage: "speaker.wave.2",
                          devices: sorted(
                              audio.outputDevices.filter { !settings.disabledOutputDevices.contains($0.uid) },
                              by: settings.outputPriority
                          ),
                          defaultUID: audio.defaultOutput?.uid,
                          isInput: false,
                          draggedUID: $draggedOutputUID)
            Divider()
            deviceSection(title: L10n.tr("label.input"), systemImage: "mic",
                          devices: sorted(
                              audio.inputDevices.filter { !settings.disabledInputDevices.contains($0.uid) },
                              by: settings.inputPriority
                          ),
                          defaultUID: audio.defaultInput?.uid,
                          isInput: true,
                          draggedUID: $draggedInputUID)
        }
    }

    // MARK: – Master volume controls

    private var masterVolumeSection: some View {
        VStack(spacing: 6) {
            VolumeRow(
                icon: "speaker.wave.2",
                label: L10n.tr("label.output"),
                volume: Binding(
                    get: { audio.outputVolume },
                    set: { v in
                        audio.outputVolume = v
                        if let d = audio.defaultOutput {
                            audio.setVolume(v, for: d, isOutput: true)
                        }
                    }
                ),
                playAction: { SoundLibrary.play(settings.testSound) },
                onEditingEnded: { SoundLibrary.play(settings.testSound) }
            )
            VolumeRow(
                icon: "mic",
                label: L10n.tr("label.input"),
                volume: Binding(
                    get: { audio.inputVolume },
                    set: { v in
                        audio.inputVolume = v
                        if let d = audio.defaultInput {
                            audio.setVolume(v, for: d, isOutput: false)
                        }
                    }
                )
            )
            VolumeRow(
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
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(SentrioCardBackground(cornerRadius: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: – Device section

    private func deviceSection(
        title: String, systemImage: String,
        devices: [AudioDevice], defaultUID: String?, isInput: Bool,
        draggedUID: Binding<String?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SentrioVisualStyle.accent)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)

            if devices.isEmpty {
                Text(L10n.tr("menu.noDevices"))
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            } else {
                let rankByUID = MenuPriorityRanker.rankMap(for: devices.map(\.uid))
                ForEach(devices) { device in
                    let orderedUIDs = devices.map(\.uid)
                    MenuDeviceRow(
                        device: device,
                        isDefault: device.uid == defaultUID,
                        isInput: isInput,
                        priorityRank: rankByUID[device.uid],
                        draggedUID: draggedUID,
                        moveUp: {
                            guard let targetUID = MenuPriorityReorderPath.targetUID(
                                for: device.uid,
                                direction: -1,
                                orderedUIDs: orderedUIDs
                            ) else { return }
                            settings.reorderPriorityForDrag(
                                uid: device.uid,
                                over: targetUID,
                                isOutput: !isInput
                            )
                        },
                        moveDown: {
                            guard let targetUID = MenuPriorityReorderPath.targetUID(
                                for: device.uid,
                                direction: 1,
                                orderedUIDs: orderedUIDs
                            ) else { return }
                            settings.reorderPriorityForDrag(
                                uid: device.uid,
                                over: targetUID,
                                isOutput: !isInput
                            )
                        }
                    )
                    .background(draggedUID.wrappedValue == device.uid
                        ? Color.accentColor.opacity(0.06)
                        : Color.clear)
                    .onDrop(of: [.plainText],
                            delegate: PriorityDropDelegate(
                                targetUID: device.uid,
                                draggedUID: draggedUID,
                                onMove: { sourceUID, targetUID in
                                    settings.reorderPriorityForDrag(
                                        uid: sourceUID,
                                        over: targetUID,
                                        isOutput: !isInput
                                    )
                                }
                            ))
                }
            }
        }
    }

    // MARK: – BusyLight quick controls

    private var busyLightSurface: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(busyLightStatusColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(busyLight.connectedDevices.first?.name ?? L10n.tr("label.busyLight"))
                    Text(busyLightStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.busyLightEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .accessibilityLabel(L10n.tr("prefs.busylight.enable"))
            }

            Toggle(L10n.tr("prefs.busylight.rules.enable"), isOn: busyLightRulesEnabled)
                .disabled(!settings.busyLightEnabled)

            if settings.busyLightControlMode == .manual {
                HStack(spacing: 8) {
                    busyLightPresetButton(
                        L10n.tr("menu.busylight.available"),
                        color: .green,
                        action: .defaultIdle
                    )
                    busyLightPresetButton(
                        L10n.tr("menu.busylight.busy"),
                        color: .red,
                        action: .defaultBusy
                    )
                    busyLightPresetButton(
                        L10n.tr("status.off"),
                        color: .secondary,
                        action: BusyLightAction(mode: .off, color: .offColor, periodMilliseconds: 600)
                    )
                }
            }

            VStack(spacing: 6) {
                busyLightSignalRow(
                    L10n.tr("prefs.busylight.signal.microphone"),
                    isOn: busyLight.signals.microphoneInUse
                )
                busyLightSignalRow(
                    L10n.tr("prefs.busylight.signal.camera"),
                    isOn: busyLight.signals.cameraInUse
                )
                busyLightSignalRow(
                    L10n.tr("prefs.busylight.signal.screenRecording"),
                    isOn: busyLight.signals.screenRecordingInUse
                )
                busyLightSignalRow(
                    L10n.tr("prefs.busylight.signal.music"),
                    isOn: busyLight.signals.musicPlaying
                )
            }

            Button(L10n.tr("action.preferences")) {
                appState.openPreferences(.busyLight)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(16)
    }

    private var busyLightRulesEnabled: Binding<Bool> {
        Binding(
            get: { settings.busyLightControlMode == .auto },
            set: { settings.busyLightControlMode = $0 ? .auto : .manual }
        )
    }

    private var busyLightStatusText: String {
        guard settings.busyLightEnabled else { return L10n.tr("status.off") }
        return settings.busyLightControlMode == .auto
            ? L10n.tr("label.auto")
            : L10n.tr("prefs.busylight.manualAction")
    }

    private var busyLightStatusColor: Color {
        guard settings.busyLightEnabled, let action = busyLight.currentAction, action.mode != .off else {
            return .secondary.opacity(0.5)
        }
        return action.color.swiftUIColor
    }

    private func busyLightPresetButton(
        _ title: String,
        color: Color,
        action: BusyLightAction
    ) -> some View {
        Button {
            settings.busyLightManualAction = action
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!settings.busyLightEnabled)
    }

    private func busyLightSignalRow(_ title: String, isOn: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(isOn ? L10n.tr("status.on") : L10n.tr("status.off"))
                .foregroundStyle(isOn ? .green : .secondary)
        }
        .font(.caption)
    }

    // MARK: – Footer

    private var footerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if EasterEggs.audioDaemonStirs() {
                Text(L10n.tr("easter.audioDaemonStirs"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 0) {
                Button(L10n.tr("action.preferences")) { appState.openPreferences() }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("action.soundSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("action.quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(SentrioChromeBackground())
    }

    // MARK: – Sort helpers

    private func sorted(_ devices: [AudioDevice], by priority: [String]) -> [AudioDevice] {
        let ranked = priority.compactMap { uid in devices.first { $0.uid == uid } }
        let unranked = devices.filter { !priority.contains($0.uid) }
        return ranked + unranked
    }
}

// MARK: – Volume row

struct VolumeRow: View {
    let icon: String
    let label: String
    @Binding var volume: Float
    var playAction: (() -> Void)?
    var onEditingEnded: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(
                value: $volume,
                in: 0 ... 1,
                onEditingChanged: { editing in
                    if !editing {
                        onEditingEnded?()
                    }
                }
            )
            Image(systemName: "\(icon).fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            if let playAction {
                Button(action: playAction) {
                    Image(systemName: "play.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                .buttonStyle(.plain)
                .help(L10n.tr("action.playSound"))
            }
        }
    }
}

// MARK: – Device row

private struct MenuDeviceRow: View {
    let device: AudioDevice
    let isDefault: Bool
    let isInput: Bool
    let priorityRank: Int?
    @Binding var draggedUID: String?
    let moveUp: () -> Void
    let moveDown: () -> Void

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio: AudioManager
    @EnvironmentObject var appState: AppState

    private var connectedUIDs: Set<String> {
        Set(audio.outputDevices.map(\.uid) + audio.inputDevices.map(\.uid))
    }

    private var canForget: Bool {
        settings.canForgetDevice(uid: device.uid, connectedUIDs: connectedUIDs)
    }

    private var isGroupByModelAvailable: Bool {
        settings.modelGroupKey(for: device.uid) != nil
    }

    private var isGroupByModelEnabled: Bool {
        settings.isGroupByModelEnabled(for: device.uid)
    }

    private var groupByModelActionTitle: String {
        let base = L10n.tr("action.groupByModel")
        let count = settings.groupByModelDeviceCount(for: device.uid)
        return count > 1 ? "\(base) (\(count))" : base
    }

    private var requiresManualConnect: Bool {
        audio.requiresManualConnection(device)
    }

    private var orderedUIDs: [String] {
        let devices = isInput ? audio.inputDevices : audio.outputDevices
        let disabled = isInput ? settings.disabledInputDevices : settings.disabledOutputDevices
        let visible = devices.filter { !disabled.contains($0.uid) }
        let priority = isInput ? settings.inputPriority : settings.outputPriority
        let ranked = priority.compactMap { uid in visible.first { $0.uid == uid } }
        return (ranked + visible.filter { !priority.contains($0.uid) }).map(\.uid)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 28, height: 36)
                .help(L10n.tr("prefs.dragToReorder"))
                .accessibilityHidden(true)
                .contentShape(Rectangle())
                .onDrag {
                    draggedUID = device.uid
                    return NSItemProvider(object: device.uid as NSString)
                }

            selectionControl

            Menu {
                deviceActions
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 28)
            .help(L10n.tr("action.deviceActions"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(rowBackground)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .contextMenu {
            deviceActions
        }
    }

    @ViewBuilder
    private var selectionControl: some View {
        if settings.isAutoMode, !requiresManualConnect {
            rowContent
                .contentShape(Rectangle())
                .help(L10n.tr("menu.deviceRow.autoModeHelp"))
        } else {
            Button {
                appState.rules.switchTo(device, isInput: isInput)
            } label: {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var deviceActions: some View {
        if requiresManualConnect {
            Button(L10n.tr("action.connectNow")) { appState.rules.switchTo(device, isInput: isInput) }
            Divider()
        }
        Button(L10n.tr("action.moveUp"), action: moveUp)
            .disabled(MenuPriorityReorderPath.targetUID(
                for: device.uid,
                direction: -1,
                orderedUIDs: orderedUIDs
            ) == nil)
        Button(L10n.tr("action.moveDown"), action: moveDown)
            .disabled(MenuPriorityReorderPath.targetUID(
                for: device.uid,
                direction: 1,
                orderedUIDs: orderedUIDs
            ) == nil)
        Divider()
        Button(L10n.tr("action.rename")) { renameDevice() }
        iconPickerMenu
        Divider()
        Button(L10n.tr("action.hideDevice")) {
            settings.hideDevice(uid: device.uid, isOutput: !isInput)
        }
        Button(L10n.tr("action.forgetDevice")) {
            settings.forgetDevice(uid: device.uid, connectedUIDs: connectedUIDs)
        }
        .disabled(!canForget)
        Button {
            settings.setGroupByModelEnabled(!isGroupByModelEnabled, for: device.uid)
        } label: {
            if isGroupByModelEnabled {
                Label(groupByModelActionTitle, systemImage: "checkmark")
            } else {
                Text(groupByModelActionTitle)
            }
        }
        .disabled(!isGroupByModelAvailable)
        if isAirPodsFamily {
            Divider()
            Button(L10n.tr("action.bluetoothSettings")) { openBluetoothSettings() }
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isDefault ? SentrioVisualStyle.accent.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isDefault ? SentrioVisualStyle.accent.opacity(0.22) : Color.clear,
                        lineWidth: 1
                    )
            )
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            // Device icon — volume-reactive for active output speaker icons
            let baseIcon = settings.iconName(for: device, isOutput: !isInput)
            let icon = (!isInput && isDefault)
                ? AudioDevice.volumeAdaptedIcon(
                    baseIcon,
                    volume: audio.outputVolume,
                    isMuted: audio.isOutputMuted
                )
                : baseIcon
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(isDefault ? SentrioVisualStyle.accent : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(settings.displayName(
                    for: device.uid,
                    isOutput: !isInput,
                    fallbackName: device.name
                ))
                .lineLimit(1)
                .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(device.transportType.label)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if requiresManualConnect {
                        Label(L10n.tr("label.manualConnect"), systemImage: "hand.tap")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if !device.batteryStates.isEmpty {
                        BatteryIconsInlineView(states: device.batteryStates)
                    }
                }
            }

            Spacer()

            if let rank = priorityRank {
                Text("#\(rank)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 22)
            }
        }
        .contentShape(Rectangle())
    }

    private var isAirPodsFamily: Bool {
        switch device.deviceTypeSystemImage {
        case "airpods", "airpodspro", "airpodsmax":
            true
        default:
            false
        }
    }

    private func openBluetoothSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    private func renameDevice() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("action.rename")
        alert.informativeText = isInput ? L10n.tr("prefs.rename.subtitle.input") : L10n.tr("prefs.rename.subtitle.output")

        let field = NSTextField(string: settings.displayName(
            for: device.uid,
            isOutput: !isInput,
            fallbackName: device.name
        ))
        field.placeholderString = L10n.tr("prefs.rename.deviceNamePlaceholder")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        alert.addButton(withTitle: L10n.tr("action.save"))
        alert.addButton(withTitle: L10n.tr("action.reset"))
        alert.addButton(withTitle: L10n.tr("action.cancel"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            settings.setCustomName(field.stringValue, for: device.uid, isOutput: !isInput)
        case .alertSecondButtonReturn:
            settings.clearCustomName(for: device.uid, isOutput: !isInput)
        default:
            break
        }
    }

    /// Context menu: icon picker
    private var iconPickerMenu: some View {
        Menu(L10n.tr("action.setIcon")) {
            Button(L10n.tr("action.resetToDefault")) { settings.clearIcon(for: device.uid, isOutput: !isInput) }
            Divider()
            ForEach(AppSettings.iconOptions, id: \.symbol) { opt in
                Button {
                    settings.setIcon(opt.symbol, for: device.uid, isOutput: !isInput)
                } label: {
                    Label(L10n.tr(opt.labelKey), systemImage: opt.symbol)
                }
            }
        }
    }
}

// MARK: – Mini level bar

struct MiniLevelBar: View {
    let level: Float // 0…1 — outputVolume for output, RMS for input
    let isOutput: Bool // true → accent colour (volume); false → traffic-light (RMS)

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(isOutput ? Color.accentColor.opacity(0.55) : inputColor)
                    .frame(width: geo.size.width * CGFloat(level))
                    .animation(isOutput ? nil : .linear(duration: 0.05), value: level)
            }
        }
    }

    private var inputColor: Color {
        level > 0.85 ? .red : level > 0.6 ? .yellow : .green
    }
}

import AppKit
import SwiftUI

private struct MenuReorderGestureState {
    let sourceUID: String
    var lastTranslation: CGFloat
    var carryTranslation: CGFloat
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
    @EnvironmentObject var appState: AppState
    @State private var outputDragState: MenuReorderGestureState?
    @State private var inputDragState: MenuReorderGestureState?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            masterVolumeSection
            Divider()
            deviceSection(title: L10n.tr("label.output"), systemImage: "speaker.wave.2",
                          devices: sorted(
                              audio.outputDevices.filter { !settings.disabledOutputDevices.contains($0.uid) },
                              by: settings.outputPriority
                          ),
                          defaultUID: audio.defaultOutput?.uid,
                          isInput: false,
                          gestureDragState: $outputDragState)
            Divider()
            deviceSection(title: L10n.tr("label.input"), systemImage: "mic",
                          devices: sorted(
                              audio.inputDevices.filter { !settings.disabledInputDevices.contains($0.uid) },
                              by: settings.inputPriority
                          ),
                          defaultUID: audio.defaultInput?.uid,
                          isInput: true,
                          gestureDragState: $inputDragState)
            Divider()
            footerRow
        }
        .frame(width: 340)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: – Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            Text("Sentrio").font(.headline)
            Spacer()
            Toggle(L10n.tr("label.auto"), isOn: $settings.isAutoMode)
                .toggleStyle(.switch).controlSize(.mini)
                .help(L10n.tr("menu.autoHelp"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                        if let d = audio.defaultOutput { audio.setVolume(v, for: d, isOutput: true) }
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
                        if let d = audio.defaultInput { audio.setVolume(v, for: d, isOutput: false) }
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
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: – Device section

    private func deviceSection(
        title: String, systemImage: String,
        devices: [AudioDevice], defaultUID: String?, isInput: Bool,
        gestureDragState: Binding<MenuReorderGestureState?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
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
                    MenuDeviceRow(
                        device: device,
                        isDefault: device.uid == defaultUID,
                        isInput: isInput,
                        priorityRank: rankByUID[device.uid],
                        isGestureDragging: gestureDragState.wrappedValue?.sourceUID == device.uid,
                        onGestureDragChanged: { sourceUID, translationHeight in
                            if gestureDragState.wrappedValue?.sourceUID != sourceUID {
                                gestureDragState.wrappedValue = MenuReorderGestureState(
                                    sourceUID: sourceUID,
                                    lastTranslation: 0,
                                    carryTranslation: 0
                                )
                            }
                            guard var state = gestureDragState.wrappedValue else { return }

                            let delta = translationHeight - state.lastTranslation
                            state.lastTranslation = translationHeight
                            state.carryTranslation += delta

                            let stepHeight: CGFloat = 28
                            if abs(state.carryTranslation) >= stepHeight {
                                let direction = state.carryTranslation > 0 ? 1 : -1
                                if let targetUID = MenuPriorityReorderPath.targetUID(
                                    for: sourceUID,
                                    direction: direction,
                                    orderedUIDs: devices.map(\.uid)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.16)) {
                                        settings.reorderPriorityForDrag(
                                            uid: sourceUID,
                                            over: targetUID,
                                            isOutput: !isInput
                                        )
                                    }
                                    state.carryTranslation -= CGFloat(direction) * stepHeight
                                } else {
                                    state.carryTranslation = 0
                                }
                            }
                            gestureDragState.wrappedValue = state
                        },
                        onGestureDragEnded: {
                            gestureDragState.wrappedValue = nil
                        }
                    )
                }
            }
        }
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
                    if !editing { onEditingEnded?() }
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
    let isGestureDragging: Bool
    let onGestureDragChanged: (String, CGFloat) -> Void
    let onGestureDragEnded: () -> Void

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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 16, height: 22)
                .help(L10n.tr("prefs.dragToReorder"))

            rowContent
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !settings.isAutoMode || requiresManualConnect else { return }
                    appState.rules.switchTo(device, isInput: isInput)
                }
                .help(settings.isAutoMode && !requiresManualConnect ? L10n.tr("menu.deviceRow.autoModeHelp") : "")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .highPriorityGesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    onGestureDragChanged(device.uid, value.translation.height)
                }
                .onEnded { _ in
                    onGestureDragEnded()
                }
        )
        .background(rowBackground)
        .contextMenu {
            if requiresManualConnect {
                Button(L10n.tr("action.connectNow")) { appState.rules.switchTo(device, isInput: isInput) }
                Divider()
            }
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
    }

    private var rowBackground: Color {
        if isGestureDragging {
            return Color.accentColor.opacity(0.06)
        }
        if isDefault {
            return Color.accentColor.opacity(0.08)
        }
        return Color.clear
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
                .foregroundStyle(isDefault ? Color.accentColor : .secondary)
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

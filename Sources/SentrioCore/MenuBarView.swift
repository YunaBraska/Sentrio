import SwiftUI

// MARK: – Root

struct MenuBarView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            masterVolumeSection
            Divider()
            deviceSection(title: "Output", systemImage: "speaker.wave.2",
                          devices: sorted(
                              audio.outputDevices.filter { !settings.disabledOutputDevices.contains($0.uid) },
                              by: settings.outputPriority),
                          defaultUID: audio.defaultOutput?.uid, isInput: false)
            Divider()
            deviceSection(title: "Input", systemImage: "mic",
                          devices: sorted(
                              audio.inputDevices.filter { !settings.disabledInputDevices.contains($0.uid) },
                              by: settings.inputPriority),
                          defaultUID: audio.defaultInput?.uid, isInput: true)
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
            Toggle("Auto", isOn: $settings.isAutoMode)
                .toggleStyle(.switch).controlSize(.mini)
                .help("Automatically switch devices based on priority rules")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: – Master volume controls

    private var masterVolumeSection: some View {
        VStack(spacing: 6) {
            VolumeRow(
                icon: "speaker.wave.2",
                label: "Output",
                volume: Binding(
                    get: { audio.outputVolume },
                    set: { v in
                        audio.outputVolume = v
                        if let d = audio.defaultOutput { audio.setVolume(v, for: d, isOutput: true) }
                    }
                )
            )
            VolumeRow(
                icon: "mic",
                label: "Input",
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
                label: "Alert",
                volume: Binding(
                    get: { audio.alertVolume },
                    set: { v in audio.setAlertVolume(v) }
                )
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: – Device section

    private func deviceSection(
        title: String, systemImage: String,
        devices: [AudioDevice], defaultUID: String?, isInput: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 2)

            if devices.isEmpty {
                Text("No devices found")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 16).padding(.bottom, 8)
            } else {
                ForEach(devices) { device in
                    MenuDeviceRow(
                        device: device,
                        isDefault: device.uid == defaultUID,
                        isInput: isInput
                    )
                }
            }
        }
    }

    // MARK: – Footer

    private var footerRow: some View {
        HStack(spacing: 0) {
            Button("Preferences…") { appState.openPreferences() }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Button("Sound Settings…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: – Sort helpers

    private func sorted(_ devices: [AudioDevice], by priority: [String]) -> [AudioDevice] {
        let ranked   = priority.compactMap { uid in devices.first { $0.uid == uid } }
        let unranked = devices.filter { !priority.contains($0.uid) }
        return ranked + unranked
    }
}

// MARK: – Volume row

struct VolumeRow: View {
    let icon: String
    let label: String
    @Binding var volume: Float

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Slider(value: $volume, in: 0...1)
            Image(systemName: "\(icon).fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
        }
    }
}

// MARK: – Device row

private struct MenuDeviceRow: View {
    let device: AudioDevice
    let isDefault: Bool
    let isInput: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        // ── Name row ────────────────────────────────────────────
        Button {
            guard !settings.isAutoMode else { return }
            appState.rules.switchTo(device, isInput: isInput)
        } label: {
            HStack(spacing: 10) {
                // Device icon — volume-reactive for active output speaker icons
                let baseIcon = settings.iconName(for: device, isOutput: !isInput)
                let icon = (!isInput && isDefault)
                    ? AudioDevice.volumeAdaptedIcon(baseIcon, volume: audio.outputVolume)
                    : baseIcon
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isDefault ? Color.accentColor : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(settings.displayName(for: device.uid, isOutput: !isInput))
                            .lineLimit(1).truncationMode(.tail)
                    HStack(spacing: 4) {
                        Text(device.transportType.label)
                            .font(.caption2).foregroundStyle(.tertiary)
                        if let bat = device.batterySystemImage {
                            Image(systemName: bat)
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // Mini level bar — only for the active device
                // Output: shows configured volume. Input: shows live RMS level.
                if isDefault {
                    MiniLevelBar(
                        level: isInput ? audio.inputLevel : audio.outputVolume,
                        isOutput: !isInput
                    )
                    .frame(width: 32, height: 8)
                }

                // Priority rank
                if let rank = priorityRank {
                    Text("#\(rank)").font(.caption2).foregroundStyle(.tertiary).frame(width: 22)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .background(isDefault ? Color.accentColor.opacity(0.08) : Color.clear)
        .help(settings.isAutoMode ? "Auto-switch is on — turn it off to select manually" : "")
        .contextMenu {
            iconPickerMenu
            Divider()
            Button("Disable Device") { settings.disableDevice(uid: device.uid, isOutput: !isInput) }
        }
    }

    private var priorityRank: Int? {
        let list = isInput ? settings.inputPriority : settings.outputPriority
        guard let idx = list.firstIndex(of: device.uid) else { return nil }
        return idx + 1
    }

    // Context menu: icon picker
    private var iconPickerMenu: some View {
        Menu("Set Icon…") {
            Button("Reset to default") { settings.clearIcon(for: device.uid, isOutput: !isInput) }
            Divider()
            ForEach(AppSettings.iconOptions, id: \.symbol) { opt in
                Button {
                    settings.setIcon(opt.symbol, for: device.uid, isOutput: !isInput)
                } label: {
                    Label(opt.label, systemImage: opt.symbol)
                }
            }
        }
    }
}

// MARK: – Mini level bar

struct MiniLevelBar: View {
    let level: Float    // 0…1 — outputVolume for output, RMS for input
    let isOutput: Bool  // true → accent colour (volume); false → traffic-light (RMS)

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

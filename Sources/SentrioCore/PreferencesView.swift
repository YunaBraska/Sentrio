import SwiftUI
import AppKit
import AudioToolbox
import UniformTypeIdentifiers

// MARK: – Root

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            PriorityTab(isOutput: true)
                .tabItem { Label("Output", systemImage: "speaker.wave.2") }
            PriorityTab(isOutput: false)
                .tabItem { Label("Input", systemImage: "mic") }
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 540, height: 680)
        .padding()
    }
}

// MARK: – Priority Tab

private struct PriorityTab: View {
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager

    /// UID currently being dragged — shared down to each row's drag handle.
    @State private var draggedUID: String?

    private var priority: Binding<[String]> {
        isOutput ? $settings.outputPriority : $settings.inputPriority
    }
    private var disabled: Set<String> {
        isOutput ? settings.disabledOutputDevices : settings.disabledInputDevices
    }
    private var allKnownUIDs: [String] {
        let enabled = priority.wrappedValue
        let extra   = (isOutput ? audio.outputDevices : audio.inputDevices)
            .map(\.uid).filter { !enabled.contains($0) && !disabled.contains($0) }
        return enabled + extra
    }
    private var disabledUIDs: [String] {
        disabled.filter { settings.knownDevices[$0] != nil }
            .sorted { (settings.knownDevices[$0] ?? $0) < (settings.knownDevices[$1] ?? $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isOutput
                 ? "Drag rows to order preferred output devices. Sentrio activates the top-ranked connected device."
                 : "Drag rows to order preferred input devices. Sentrio activates the top-ranked connected device.")
                .foregroundStyle(.secondary).font(.callout)

            // ── Volume for this role ───────────────────────────────────────
            volumeSection

            // ── Priority list (custom drag-and-drop — more reliable than List.onMove) ────
            GroupBox {
                VStack(spacing: 0) {
                    sectionHeader("Priority order", hint: "Grab ≡ to reorder")
                    Divider()

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(allKnownUIDs, id: \.self) { uid in
                                PriorityRow(uid: uid, isOutput: isOutput, draggedUID: $draggedUID)
                                    .background(uid == draggedUID
                                                ? Color.accentColor.opacity(0.06)
                                                : Color.clear)
                                    .onDrop(of: [.plainText],
                                            delegate: PriorityDropDelegate(
                                                targetUID: uid,
                                                items: priority,
                                                draggedUID: $draggedUID))
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .frame(minHeight: 80)

                    // ── Disabled section ─────────────────────────────────
                    if !disabledUIDs.isEmpty {
                        Divider()
                        sectionHeader("Disabled (not used as fallback)", titleColor: .orange)
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

    @ViewBuilder
    private var volumeSection: some View {
        GroupBox {
            VStack(spacing: 6) {
                // Output volume
                sliderRow(
                    icon: isOutput ? "speaker" : "mic",
                    label: isOutput ? "Output" : "Input",
                    volume: isOutput
                        ? Binding(
                            get: { audio.outputVolume },
                            set: { v in
                                audio.outputVolume = v
                                if let d = audio.defaultOutput { audio.setVolume(v, for: d, isOutput: true) }
                            })
                        : Binding(
                            get: { audio.inputVolume },
                            set: { v in
                                audio.inputVolume = v
                                if let d = audio.defaultInput { audio.setVolume(v, for: d, isOutput: false) }
                            }),
                    onRelease: { NSSound(named: NSSound.Name("Tink"))?.play() }
                )
                if isOutput {
                    sliderRow(
                        icon: "bell",
                        label: "Alert",
                        volume: Binding(
                            get: { audio.alertVolume },
                            set: { v in audio.setAlertVolume(v) }),
                        onRelease: { AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert) }
                    )
                }
            }
        } label: {
            Label(isOutput ? "Volume" : "Input Gain",
                  systemImage: isOutput ? "speaker.wave.2" : "mic")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func sliderRow(
        icon: String,
        label: String,
        volume: Binding<Float>,
        onRelease: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
            Text(label)
                .font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Slider(value: volume, in: 0...1) { editing in
                if !editing { onRelease() }
            }
            Image(systemName: "\(icon).fill")
                .font(.caption).foregroundStyle(.secondary).frame(width: 16)
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
}

// MARK: – Drag-and-drop delegate
//
// Items reorder in real time as the drag crosses row boundaries (dropEntered),
// so the user sees immediate visual feedback and doesn't need to release at
// a precise location — this is far more reliable than List.onMove on macOS.

private struct PriorityDropDelegate: DropDelegate {
    let targetUID:          String
    @Binding var items:     [String]
    @Binding var draggedUID: String?

    func dropEntered(info: DropInfo) {
        guard
            let source = draggedUID, source != targetUID,
            let from   = items.firstIndex(of: source),
            let to     = items.firstIndex(of: targetUID)
        else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            items.move(fromOffsets: IndexSet(integer: from),
                       toOffset:   to > from ? to + 1 : to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedUID = nil
        return true
    }
}

// MARK: – Priority Row (enabled)

private struct PriorityRow: View {
    let uid:     String
    let isOutput: Bool
    @Binding var draggedUID: String?

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager

    @State private var showIconPicker   = false
    @State private var showRenamePopover = false
    @State private var pendingName      = ""

    private var name: String { settings.displayName(for: uid, isOutput: isOutput) }
    private var device: AudioDevice? {
        (isOutput ? audio.outputDevices : audio.inputDevices).first { $0.uid == uid }
    }
    private var isConnected: Bool { device != nil }
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
                .help("Drag to reorder")

            // Connection dot
            Circle()
                .fill(isConnected ? Color.green : Color.secondary.opacity(0.3))
                .frame(width: 7, height: 7)

            // Icon button — volume-reactive for active output speaker icons
            let displayedIcon = (isOutput && device?.uid == audio.defaultOutput?.uid)
                ? AudioDevice.volumeAdaptedIcon(effectiveIcon, volume: audio.outputVolume)
                : effectiveIcon
            Button { showIconPicker = true } label: {
                Image(systemName: displayedIcon)
                    .font(.system(size: 16))
                    .foregroundStyle(isConnected ? Color.accentColor : .secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(device.flatMap(\.iconBaseName).map { "CoreAudio icon file: \($0)\nClick to override" }
                  ?? "Click to change icon")
            .popover(isPresented: $showIconPicker, arrowEdge: .trailing) {
                IconPickerPopover(uid: uid, isOutput: isOutput)
                    .environmentObject(settings)
                    .padding(12)
            }

            // Name + rename button
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .foregroundStyle(isConnected ? .primary : .secondary)
                        .lineLimit(1)
                    Button {
                        pendingName = name
                        showRenamePopover = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Rename for this \(isOutput ? "output" : "input") role")
                    .popover(isPresented: $showRenamePopover, arrowEdge: .trailing) {
                        RenamePopover(
                            uid: uid, isOutput: isOutput,
                            originalName: settings.knownDevices[uid] ?? uid,
                            name: $pendingName,
                            isPresented: $showRenamePopover)
                        .environmentObject(settings)
                        .padding(14)
                    }
                }

                HStack(spacing: 6) {
                    if let dev = device {
                        Text(dev.transportType.label)
                            .font(.caption2).foregroundStyle(.tertiary)
                        if let bat = dev.batterySystemImage {
                            Image(systemName: bat)
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    } else {
                        Text("Disconnected")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    if let vol = settings.savedVolume(for: uid, isOutput: isOutput) {
                        Text("· Vol \(Int(vol * 100))%")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Mini level bar — only for the active device
            if isOutput
                ? device?.uid == audio.defaultOutput?.uid
                : device?.uid == audio.defaultInput?.uid {
                MiniLevelBar(
                    level: isOutput ? audio.outputVolume : audio.inputLevel,
                    isOutput: isOutput)
                .frame(width: 36, height: 8)
            }

            // Disable button (always available)
            Button {
                settings.disableDevice(uid: uid, isOutput: isOutput)
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Disable — remove from auto-switching. Can be re-enabled below.")

            // Delete button — only for disconnected devices
            if !isConnected {
                Button {
                    settings.deleteDevice(uid: uid)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove permanently — reappears automatically if device reconnects")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(isConnected ? 1 : 0.6)
    }

    private var effectiveIcon: String {
        guard let dev = device else {
            return settings.deviceIcons[uid]?[isOutput ? "output" : "input"] ?? "questionmark.circle"
        }
        return settings.iconName(for: dev, isOutput: isOutput)
    }
}

// MARK: – Rename Popover

private struct RenamePopover: View {
    let uid:          String
    let isOutput:     Bool
    let originalName: String
    @Binding var name: String
    @Binding var isPresented: Bool

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rename").font(.headline)
            Text("Custom label for this \(isOutput ? "output" : "input") role only.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Device name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .onSubmit { save() }

            HStack {
                Button("Reset") {
                    settings.clearCustomName(for: uid, isOutput: isOutput)
                    name = originalName
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)

                Spacer()

                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)

                Button("Save", action: save)
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
//   [drag placeholder 20] [dot 7] [icon 24] [name VStack] [Spacer] [Enable] [Trash?]

private struct DisabledRow: View {
    let uid:      String
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager

    private var device: AudioDevice? {
        (isOutput ? audio.outputDevices : audio.inputDevices).first { $0.uid == uid }
    }
    private var isConnected: Bool { device != nil }

    /// Best-effort icon: live device → custom stored → generic fallback.
    private var iconName: String {
        if let dev = device { return settings.iconName(for: dev, isOutput: isOutput) }
        return settings.deviceIcons[uid]?[isOutput ? "output" : "input"]
            ?? (isOutput ? "speaker.wave.2" : "mic")
    }

    var body: some View {
        HStack(spacing: 8) {
            // Drag handle placeholder — keeps columns aligned with PriorityRow
            Color.clear.frame(width: 20, height: 36)

            // Status dot: orange = disabled (mirrors green/grey dot in PriorityRow)
            Circle()
                .fill(Color.orange.opacity(0.75))
                .frame(width: 7, height: 7)

            // Device icon in the same column as PriorityRow's icon button
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(settings.displayName(for: uid, isOutput: isOutput))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(isConnected ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundStyle(isConnected
                                     ? AnyShapeStyle(.green.opacity(0.8))
                                     : AnyShapeStyle(.tertiary))
            }

            Spacer()

            Button("Enable") { settings.enableDevice(uid: uid, isOutput: isOutput) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            // Trash only when disconnected — connected devices must be enabled first
            if !isConnected {
                Button {
                    settings.deleteDevice(uid: uid)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove permanently")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .opacity(0.82)
    }
}

// MARK: – Icon Picker Popover

struct IconPickerPopover: View {
    let uid:      String
    let isOutput: Bool

    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) var dismiss

    private let columns = [GridItem(.adaptive(minimum: 48), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Choose Icon").font(.headline)
                Spacer()
                Button("Reset") {
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
                            Text(opt.label)
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
                    .help(opt.label)
                }
            }
        }
        .frame(width: 290)
    }
}

// MARK: – General Tab

private struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var audio:    AudioManager
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            // ── Auto-switching ──────────────────────────────────────
            Section {
                Toggle("Enable auto-switching", isOn: $settings.isAutoMode)
                Text("Automatically activates the top-ranked connected device whenever devices connect or disconnect, or when you reorder the priority list.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // ── Visibility ──────────────────────────────────────────
            Section("Visibility") {
                Toggle("Hide menu bar icon", isOn: $settings.hideMenuBarIcon)
                Text("When hidden, open Preferences by launching Sentrio again from Launchpad.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // ── System ──────────────────────────────────────────────
            Section("System") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { settings.setLaunchAtLogin($0) }
                Button("Open Sound Settings…") {
                    openSite("x-apple.systempreferences:com.apple.preference.sound")
                }
            }

            // ── Volume memory ────────────────────────────────────────
            Section("Volume Memory") {
                Text("Volume levels are saved per device and restored automatically when that device becomes active.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear Volume Memory") { settings.volumeMemory = [:] }
                    .foregroundStyle(.red)
            }

            // ── About ────────────────────────────────────────────────
            Section("About") {
                Text("Sentrio is a lightweight macOS menu bar app for managing audio input and output devices — with automatic switching based on priority rules, per-device volume memory, and live battery display.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack {
                    Text("Version")
                    Spacer()
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                    let build   = Bundle.main.infoDictionary?["CFBundleVersion"]            as? String ?? "—"
                    let display = (build == "—" || build.isEmpty || build == version)
                        ? version
                        : "\(version) (\(build))"
                    Text(display).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Author")
                    Spacer()
                    Text("Yuna Morgenstern").foregroundStyle(.secondary)
                }
                HStack {
                    Text("License")
                    Spacer()
                    Text("MIT Open Source").foregroundStyle(.secondary)
                }

                Button("View Source on GitHub") {
                    openSite("https://github.com/YunaBraska/Sentrio")
                }
                Button("☕  Buy Me a Coffee") {
                    openSite("https://github.com/sponsors/YunaBraska?frequency=one-time")
                }
                Button("Report an Issue") {
                    openSite("https://github.com/YunaBraska/Sentrio/issues/new")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = settings.isLaunchAtLoginEnabled }
    }

    private func openSite(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

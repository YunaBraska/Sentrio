import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings
    let audio: AudioManager
    let rules: RulesEngine
    let busyLight: BusyLightEngine

    @Published var preferencesPane: PreferencesPane

    private var fallbackSettingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: AppSettings = AppSettings(),
        audio: AudioManager = AudioManager(),
        rules: RulesEngine? = nil,
        busyLight: BusyLightEngine? = nil,
        bindIntegrationBridge: Bool = true
    ) {
        preferencesPane = UserDefaults.standard.string(forKey: "preferencesPane")
            .flatMap(PreferencesPane.init(rawValue:)) ?? .output
        self.settings = settings
        self.audio = audio
        let resolvedRules = rules ?? RulesEngine(audio: audio, settings: settings)
        self.rules = resolvedRules
        let resolvedBusyLight = busyLight ?? BusyLightEngine(audio: audio, settings: settings)
        self.busyLight = resolvedBusyLight
        if bindIntegrationBridge {
            BusyLightIntegrationBridge.shared.bind(engine: resolvedBusyLight)
        }

        // Forward changes from nested ObservableObjects to the app presentation.
        // This keeps the menu bar icon and its visibility in sync with the current state.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        audio.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        $preferencesPane
            .dropFirst()
            .sink { pane in UserDefaults.standard.set(pane.rawValue, forKey: "preferencesPane") }
            .store(in: &cancellables)

        // Open Preferences when the app is reopened from macOS.
        NotificationCenter.default.addObserver(
            self, selector: #selector(reopenApp),
            name: .reopenApp, object: nil
        )
    }

    // MARK: – Dynamic menu bar icon

    private var activeLowestNonCaseBatteryLevel: Float? {
        [audio.defaultOutput?.lowestNonCaseBatteryLevel, audio.defaultInput?.lowestNonCaseBatteryLevel]
            .compactMap { $0 }
            .min()
    }

    var isMenuBarLowBatteryWarning: Bool {
        guard let level = activeLowestNonCaseBatteryLevel else { return false }
        return level < 0.15
    }

    /// The SF Symbol name shown as the menu bar icon.
    /// Tracks the current default output device's icon; falls back to input, then waveform.
    /// If the icon is a standard speaker symbol it adapts to the current volume level,
    /// mirroring the macOS System Settings sound icon behaviour.
    var currentMenuBarIconName: String {
        if let level = activeLowestNonCaseBatteryLevel, level < 0.15 {
            return AudioDevice.batterySystemImage(for: level)
        }
        if let out = audio.defaultOutput {
            let base = settings.iconName(for: out, isOutput: true)
            return AudioDevice.volumeAdaptedIcon(
                base,
                volume: audio.outputVolume,
                isMuted: audio.isOutputMuted
            )
        }
        if let inp = audio.defaultInput {
            return settings.iconName(for: inp, isOutput: false)
        }
        return "waveform"
    }

    // MARK: – Preferences window

    func openPreferences(_ pane: PreferencesPane? = nil) {
        if let pane {
            preferencesPane = pane
        }

        NSApp.activate(ignoringOtherApps: true)
        let didOpenSettings = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        guard !didOpenSettings else { return }

        if fallbackSettingsWindow == nil {
            let view = PreferencesView()
                .environmentObject(settings)
                .environmentObject(audio)
                .environmentObject(busyLight)
                .environmentObject(self)
            let controller = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: controller)
            win.title = L10n.tr("prefs.window.title")
            win.setContentSize(NSSize(width: 540, height: 680))
            win.styleMask = [.titled, .closable]
            win.center()
            win.isReleasedWhenClosed = false
            fallbackSettingsWindow = win
        }
        fallbackSettingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func reopenApp() {
        openPreferences()
    }
}

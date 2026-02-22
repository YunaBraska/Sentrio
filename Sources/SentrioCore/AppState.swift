import AppKit
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    let settings = AppSettings()
    let audio = AudioManager()
    lazy var rules = RulesEngine(audio: audio, settings: settings)

    private var preferencesWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init() {
        _ = rules

        // ── Forward changes from nested ObservableObjects so App.body re-evaluates ──
        // This is what makes the dynamic menu bar icon and hideMenuBarIcon work.
        settings.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        audio.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // Listen for reopen (Launchpad click) to open Preferences
        NotificationCenter.default.addObserver(
            self, selector: #selector(reopenApp),
            name: .reopenApp, object: nil
        )
    }

    // MARK: – Dynamic menu bar icon

    /// The SF Symbol name shown as the menu bar icon.
    /// Tracks the current default output device's icon; falls back to input, then waveform.
    /// If the icon is a standard speaker symbol it adapts to the current volume level,
    /// mirroring the macOS System Settings sound icon behaviour.
    var currentMenuBarIconName: String {
        if let out = audio.defaultOutput {
            let base = settings.iconName(for: out, isOutput: true)
            return AudioDevice.volumeAdaptedIcon(base, volume: audio.outputVolume)
        }
        if let inp = audio.defaultInput { return settings.iconName(for: inp, isOutput: false) }
        return "waveform"
    }

    // MARK: – Preferences window

    func openPreferences() {
        if preferencesWindow == nil {
            let view = PreferencesView()
                .environmentObject(settings)
                .environmentObject(audio)
                .environmentObject(self)
            let controller = NSHostingController(rootView: view)
            let win = NSWindow(contentViewController: controller)
            win.title = "Sentrio Preferences"
            win.setContentSize(NSSize(width: 520, height: 620))
            win.styleMask = [.titled, .closable, .miniaturizable]
            win.center()
            win.isReleasedWhenClosed = false
            preferencesWindow = win
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func reopenApp() {
        openPreferences()
    }
}

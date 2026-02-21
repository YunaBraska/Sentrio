import SwiftUI
import AppKit

public struct SentrioApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
        MenuBarExtra(
            isInserted: Binding(
                get: { !appState.settings.hideMenuBarIcon },
                set: { _ in }
            )
        ) {
            MenuBarView()
                .environmentObject(appState.settings)
                .environmentObject(appState.audio)
                .environmentObject(appState)
        } label: {
            // Icon dynamically reflects the current active output device (or input)
            Image(systemName: appState.currentMenuBarIconName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NotificationCenter.default.post(name: .reopenApp, object: nil)
        return true
    }
}

extension Notification.Name {
    public static let reopenApp = Notification.Name("Sentrio.reopenApp")
}

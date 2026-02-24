import AppKit
import SwiftUI

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
            Image(systemName: appState.currentMenuBarIconName)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(appState.isMenuBarLowBatteryWarning ? Color.red : Color.primary)
        }
        .menuBarExtraStyle(.window)
    }
}

public class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if #available(macOS 13.0, *) {
            BusyLightAppShortcuts.updateAppShortcutParameters()
        }
    }

    public func application(_: NSApplication, open urls: [URL]) {
        for url in urls {
            do {
                try BusyLightIntegrationBridge.shared.handleIncomingURL(url)
            } catch {
                NSLog("Sentrio BusyLight URL error: %@", error.localizedDescription)
            }
        }
    }

    public func applicationWillTerminate(_: Notification) {
        BusyLightIntegrationBridge.shared.shutdownIfAvailable()
    }

    public func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        NotificationCenter.default.post(name: .reopenApp, object: nil)
        return true
    }
}

public extension Notification.Name {
    static let reopenApp = Notification.Name("Sentrio.reopenApp")
}

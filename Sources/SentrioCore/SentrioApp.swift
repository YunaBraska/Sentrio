import AppKit
import Combine
import SwiftUI

#if !SENTRIO_APP_STORE
    import Sparkle
#endif

public struct SentrioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {}

    public var body: some Scene {
        Settings { EmptyView() }
    }
}

enum MenuBarPresentation {
    static func statusItemIsVisible(hidingMenuBarIcon: Bool) -> Bool {
        !hidingMenuBarIcon
    }

    static func activationPolicy(hidingMenuBarIcon: Bool) -> NSApplication.ActivationPolicy {
        hidingMenuBarIcon ? .regular : .accessory
    }
}

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()

    private var statusItem: NSStatusItem?
    private let menuPopover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    #if !SENTRIO_APP_STORE
        private lazy var updater: SPUStandardUpdaterController? = {
            guard let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  !publicKey.isEmpty else { return nil }
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            controller.updater.automaticallyChecksForUpdates = true
            controller.updater.automaticallyDownloadsUpdates = false
            controller.startUpdater()
            return controller
        }()
    #endif

    public func applicationDidFinishLaunching(_: Notification) {
        configureMenuBar()
        observeMenuBarState()
        #if !SENTRIO_APP_STORE
            _ = updater
        #endif
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

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggleMenu)
        item.button?.sendAction(on: [.leftMouseUp])
        item.button?.toolTip = "Sentrio"
        statusItem = item

        menuPopover.behavior = .transient
        menuPopover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState.settings)
                .environmentObject(appState.audio)
                .environmentObject(appState)
        )
        updateStatusItem()
    }

    private func observeMenuBarState() {
        appState.settings.$hideMenuBarIcon
            .sink { [weak self] isHidden in self?.updateMenuBarPresentation(hidingMenuBarIcon: isHidden) }
            .store(in: &cancellables)

        appState.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateStatusItem() }
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarPresentation(hidingMenuBarIcon: Bool) {
        statusItem?.isVisible = MenuBarPresentation.statusItemIsVisible(hidingMenuBarIcon: hidingMenuBarIcon)
        NSApp.setActivationPolicy(MenuBarPresentation.activationPolicy(hidingMenuBarIcon: hidingMenuBarIcon))
        if hidingMenuBarIcon {
            menuPopover.performClose(nil)
            appState.openPreferences()
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(
            systemSymbolName: appState.currentMenuBarIconName,
            accessibilityDescription: "Sentrio"
        )
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = appState.isMenuBarLowBatteryWarning ? .systemRed : nil
    }

    @objc private func toggleMenu() {
        guard let button = statusItem?.button else { return }
        if menuPopover.isShown {
            menuPopover.performClose(nil)
        } else {
            menuPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

public extension Notification.Name {
    static let reopenApp = Notification.Name("Sentrio.reopenApp")
}

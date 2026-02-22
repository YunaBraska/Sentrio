import AppKit
import SwiftUI

/// Reports whether the hosting NSWindow is currently visible to the user.
///
/// Uses occlusion state so it turns off when the window is not visible (closed, hidden,
/// or fully covered), which is ideal for privacy-sensitive features like mic monitoring.
struct WindowActivityObserver: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onWindowChanged = { [weak coordinator = context.coordinator] window in
            coordinator?.updateWindow(window)
            coordinator?.evaluate()
        }
        context.coordinator.updateWindow(view.window)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onChange = onChange
        if let view = nsView as? ObserverView {
            view.onWindowChanged = { [weak coordinator = context.coordinator] window in
                coordinator?.updateWindow(window)
                coordinator?.evaluate()
            }
        }
        context.coordinator.updateWindow(nsView.window)
        context.coordinator.evaluate()
    }

    private final class ObserverView: NSView {
        var onWindowChanged: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChanged?(window)
        }
    }

    final class Coordinator: NSObject {
        var onChange: (Bool) -> Void
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var isActive = false

        init(onChange: @escaping (Bool) -> Void) {
            self.onChange = onChange
        }

        func updateWindow(_ newWindow: NSWindow?) {
            guard window !== newWindow else { return }
            detach()
            window = newWindow
            guard let newWindow else {
                setActive(false)
                return
            }

            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.didResignKeyNotification,
                NSWindow.didBecomeMainNotification,
                NSWindow.didResignMainNotification,
                NSWindow.didMiniaturizeNotification,
                NSWindow.didDeminiaturizeNotification,
                NSWindow.willCloseNotification,
            ]
            for name in names {
                observers.append(center.addObserver(
                    forName: name,
                    object: newWindow,
                    queue: .main
                ) { [weak self] _ in
                    self?.evaluate()
                })
            }
        }

        func evaluate() {
            guard let window else {
                setActive(false)
                return
            }
            let visible = window.isVisible && (
                window.occlusionState.contains(.visible) || window.isKeyWindow || window.isMainWindow
            )
            setActive(visible)
        }

        private func setActive(_ active: Bool) {
            guard active != isActive else { return }
            isActive = active
            onChange(active)
        }

        private func detach() {
            for obs in observers {
                NotificationCenter.default.removeObserver(obs)
            }
            observers.removeAll()
        }

        deinit {
            detach()
        }
    }
}

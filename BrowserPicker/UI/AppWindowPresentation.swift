import AppKit
import Combine

/// Track app windows explicitly so the menu bar popover does not toggle the Dock icon.
@MainActor
final class AppWindowPresentation {
    static let shared = AppWindowPresentation()
    private var openWindows: [ObjectIdentifier: NSWindow] = [:]
    private var closeObservation: AnyCancellable?
    private let setPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void

    init(setPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }) {
        self.setPolicy = setPolicy
        closeObservation = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)
            .sink { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let window = notification.object as? NSWindow else { return }
                    self?.unregister(window)
                }
            }
    }

    func show(_ window: NSWindow?) {
        guard let window else { return }
        register(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide(_ window: NSWindow?) {
        guard let window else { return }
        window.orderOut(nil)
        unregister(window)
    }

    func register(_ window: NSWindow) {
        openWindows[ObjectIdentifier(window)] = window
        setPolicy(.regular)
    }

    func unregister(_ window: NSWindow) {
        guard openWindows.removeValue(forKey: ObjectIdentifier(window)) != nil else { return }
        setPolicy(openWindows.isEmpty ? .accessory : .regular)
    }

    @discardableResult
    func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        register(alert.window)
        defer { unregister(alert.window) }
        return alert.runModal()
    }
}

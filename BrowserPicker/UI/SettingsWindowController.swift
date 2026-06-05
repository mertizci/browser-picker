import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(settingsStore: SettingsStore, appState: AppState) {
        if PermissionMonitor.shared.isOnboardingActive {
            PermissionsOnboardingWindowController.shared.showIfNeeded()
            return
        }

        if window == nil {
            let content = SettingsView()
                .environmentObject(settingsStore)
                .environmentObject(appState)
                .environmentObject(PermissionMonitor.shared)

            let hosting = NSHostingController(rootView: content)
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Browser Picker Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 860, height: 600))
            newWindow.minSize = NSSize(width: 820, height: 560)
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        } else {
            window?.contentViewController = NSHostingController(
                rootView: SettingsView()
                    .environmentObject(settingsStore)
                    .environmentObject(appState)
                    .environmentObject(PermissionMonitor.shared)
            )
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        window?.orderOut(nil)
    }
}

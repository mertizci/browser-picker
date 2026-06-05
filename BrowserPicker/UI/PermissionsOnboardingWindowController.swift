import AppKit
import SwiftUI

@MainActor
final class PermissionsOnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionsOnboardingWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func showIfNeeded() {
        PermissionMonitor.shared.refresh()

        guard !PermissionMonitor.shared.allRequiredPermissionsGranted else {
            dismiss()
            return
        }

        if window == nil {
            let permissions = PermissionMonitor.shared
            let content = PermissionsOnboardingView(permissions: permissions) { [weak self] in
                self?.completeOnboarding()
            }

            let hosting = NSHostingController(rootView: content)
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Browser Picker Setup"
            newWindow.styleMask = [.titled, .fullSizeContentView]
            newWindow.isMovableByWindowBackground = true
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            newWindow.level = .floating
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        PermissionMonitor.shared.setOnboardingActive(true)
        PermissionMonitor.shared.startPolling()
    }

    func completeOnboarding() {
        guard PermissionMonitor.shared.allRequiredPermissionsGranted else { return }

        PermissionMonitor.shared.stopPolling()
        PermissionMonitor.shared.setOnboardingActive(false)
        PermissionMonitor.shared.refresh()
        SettingsStore.shared.reloadProfiles()
        dismiss()
    }

    func dismiss() {
        PermissionMonitor.shared.stopPolling()
        PermissionMonitor.shared.setOnboardingActive(false)
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        PermissionMonitor.shared.allRequiredPermissionsGranted
    }
}

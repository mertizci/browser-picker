import AppKit
import SwiftUI

@MainActor
final class PermissionsOnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = PermissionsOnboardingWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func showIfNeeded(forProfileSetup: Bool = false) {
        if SettingsStore.shared.settings.basicMode && !forProfileSetup {
            dismiss()
            return
        }
        PermissionMonitor.shared.setOnboardingActive(true)
        PermissionMonitor.shared.refresh()

        guard !PermissionMonitor.shared.allRequiredPermissionsGranted else {
            completeOnboarding()
            return
        }

        if window == nil {
            let permissions = PermissionMonitor.shared
            let content = PermissionsOnboardingView(permissions: permissions, onContinue: { [weak self] in
                self?.completeOnboarding()
            }, onContinueBasic: { [weak self] in self?.continueInBasicMode() })

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

        AppWindowPresentation.shared.show(window)
        PermissionMonitor.shared.setOnboardingActive(true)
        PermissionMonitor.shared.startPolling()
    }

    func completeOnboarding() {
        guard PermissionMonitor.shared.allRequiredPermissionsGranted else { return }

        finish(basicMode: false)
    }

    func continueInBasicMode() {
        finish(basicMode: true)
    }

    private func finish(basicMode: Bool) {
        do {
            try SettingsStore.shared.setBasicMode(basicMode)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Save Browser Mode"
            alert.informativeText = error.localizedDescription
            AppWindowPresentation.shared.runModal(alert)
            return
        }
        dismiss()
        URLRouter.shared.resumeAfterSetup()
    }

    func dismiss() {
        PermissionMonitor.shared.stopPolling()
        PermissionMonitor.shared.setOnboardingActive(false)
        AppWindowPresentation.shared.hide(window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        SettingsStore.shared.settings.basicMode || PermissionMonitor.shared.allRequiredPermissionsGranted
    }
}

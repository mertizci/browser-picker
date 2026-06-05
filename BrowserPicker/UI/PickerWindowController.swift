import AppKit
import SwiftUI

@MainActor
final class PickerWindowController: NSObject, NSWindowDelegate {
    static let shared = PickerWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show(settingsStore: SettingsStore, urlRouter: URLRouter) {
        if window == nil {
            let content = PickerPromptView()
                .environmentObject(settingsStore)
                .environmentObject(urlRouter)

            let hosting = NSHostingController(rootView: content)
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Choose Browser"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.setContentSize(NSSize(width: 420, height: 360))
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        } else {
            window?.contentViewController = NSHostingController(
                rootView: PickerPromptView()
                    .environmentObject(settingsStore)
                    .environmentObject(urlRouter)
            )
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        URLRouter.shared.cancelPicker()
    }
}

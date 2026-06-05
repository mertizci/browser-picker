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
        let hosting = NSHostingController(
            rootView: PickerPromptView()
                .environmentObject(settingsStore)
                .environmentObject(urlRouter)
        )
        // Let the window track the SwiftUI content's intrinsic size so it never
        // leaves empty space below the profile list.
        hosting.sizingOptions = [.preferredContentSize]

        if window == nil {
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Choose Browser"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        } else {
            window?.contentViewController = hosting
        }

        window?.makeKeyAndOrderFront(nil)
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        URLRouter.shared.cancelPicker()
    }
}

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

        if window == nil {
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Choose Browser"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        } else {
            window?.contentViewController = hosting
        }

        // Size the window once to fit the SwiftUI content (the view has a fixed
        // width and an intrinsic, bounded height). Doing this explicitly — rather
        // than via NSHostingController.preferredContentSize — avoids a crash where
        // AppKit reframes the window from constraints during the display cycle.
        hosting.view.layoutSubtreeIfNeeded()
        let fitting = hosting.view.fittingSize
        if fitting.width > 0, fitting.height > 0 {
            window?.setContentSize(fitting)
        }

        window?.center()
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

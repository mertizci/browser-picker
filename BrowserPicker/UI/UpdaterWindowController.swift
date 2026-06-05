import AppKit
import SwiftUI

@MainActor
final class UpdaterWindowController: NSObject, NSWindowDelegate {
    static let shared = UpdaterWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: UpdaterView(controller: .shared))
            let newWindow = NSWindow(contentViewController: hosting)
            newWindow.title = "Browser Picker Update"
            newWindow.styleMask = [.titled, .closable, .fullSizeContentView]
            newWindow.titlebarAppearsTransparent = true
            newWindow.isMovableByWindowBackground = true
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.orderOut(nil)
    }
}

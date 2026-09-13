import AppKit
import Combine
import SwiftUI

/// A normal window gives the editor a draggable title bar and native resizing.
@MainActor
final class RuleEditorWindowController: NSObject, NSWindowDelegate {
    static let shared = RuleEditorWindowController()
    private var window: NSWindow?
    private var settingsObservation: AnyCancellable?
    private let windowSize = RuleEditorWindowSize()

    func show(rule: RoutingRule?, settingsStore: SettingsStore) {
        // Keep an open draft intact if Add/Edit is clicked again.
        if let window {
            AppWindowPresentation.shared.show(window)
            return
        }
        guard !settingsStore.settings.basicMode else { return }

        let content = RuleEditorView(rule: rule, onClose: { [weak self] in self?.close() }) { saved in
            if rule == nil {
                settingsStore.addRule(saved)
            } else if let current = settingsStore.settings.rules.first(where: { $0.id == saved.id }) {
                // Reordering in the settings window must not be undone by Save.
                var updated = saved
                updated.priority = current.priority
                settingsStore.updateRule(updated)
            }
        }
        .environmentObject(settingsStore)
        let visibleFrame = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let size = windowSize.restoredSize(in: visibleFrame)
        let newWindow = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                 backing: .buffered, defer: false)
        newWindow.title = rule.map { "Edit Rule — \($0.name)" } ?? "Add Rule"
        newWindow.contentViewController = NSHostingController(rootView: content)
        newWindow.contentMinSize = RuleEditorWindowSize.minimum
        newWindow.setContentSize(size)
        newWindow.setFrameOrigin(NSPoint(x: visibleFrame.midX - newWindow.frame.width / 2,
                                        y: visibleFrame.midY - newWindow.frame.height / 2))
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        window = newWindow

        // The settings window remains usable. Close a draft whose rule was
        // deleted there, or when profile features are turned off.
        settingsObservation = settingsStore.$settings.sink { [weak self] settings in
            if settings.basicMode || (rule.map { edited in !settings.rules.contains { $0.id == edited.id } } ?? false) {
                self?.close()
            }
        }
        AppWindowPresentation.shared.show(newWindow)
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        saveWindowSize(notification)
        settingsObservation = nil
        window = nil
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowSize(notification)
    }

    private func saveWindowSize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !window.styleMask.contains(.fullScreen) else { return }
        windowSize.save(window.contentRect(forFrameRect: window.frame).size)
    }
}

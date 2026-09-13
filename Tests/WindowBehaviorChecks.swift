import AppKit
@testable import BrowserPicker

@main
struct WindowBehaviorChecks {
    @MainActor
    static func main() {
        let suite = "BrowserPicker.WindowChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = RuleEditorWindowSize(defaults: defaults)
        let largeScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        assert(storage.restoredSize(in: largeScreen) == NSSize(width: 620, height: 680))
        storage.save(NSSize(width: 850, height: 740))
        let reopened = RuleEditorWindowSize(defaults: UserDefaults(suiteName: suite)!)
        assert(reopened.restoredSize(in: largeScreen) == NSSize(width: 850, height: 740))
        assert(reopened.restoredSize(in: NSRect(x: 0, y: 0, width: 640, height: 480)) == NSSize(width: 592, height: 400))
        // Adapting to another screen does not replace the saved preference.
        assert(reopened.restoredSize(in: largeScreen) == NSSize(width: 850, height: 740))
        storage.save(NSSize(width: 300, height: 200))
        storage.save(NSSize(width: CGFloat.infinity, height: 700))
        assert(storage.restoredSize(in: largeScreen) == NSSize(width: 850, height: 740))
        storage.save(RuleEditorWindowSize.minimum)
        assert(reopened.restoredSize(in: largeScreen) == RuleEditorWindowSize.minimum)
        print("PASS: editor sizes persist across storage instances, fit smaller screens, and reject invalid dimensions")

        _ = NSApplication.shared
        var policies: [NSApplication.ActivationPolicy] = []
        let presentation = AppWindowPresentation(setPolicy: { policies.append($0) })
        // Offscreen windows and an injected policy setter leave the actual Dock untouched.
        let first = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let second = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let untracked = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: true)
        presentation.register(first)
        assert(policies.last == .regular)
        presentation.register(second)
        presentation.register(second)
        presentation.unregister(first)
        assert(policies.last == .regular)
        let count = policies.count
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: untracked)
        assert(policies.count == count)
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: second)
        assert(policies.last == .accessory)
        presentation.unregister(second)
        assert(policies.last == .accessory)
        presentation.register(first)
        assert(policies.last == .regular)
        presentation.unregister(first)
        assert(policies.last == .accessory)
        print("PASS: Dock policy handles multiple windows, repeated shows, close/hide, reopening, and unrelated popovers")
    }
}

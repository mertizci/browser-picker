import AppKit

struct RuleEditorWindowSize {
    static let minimum = NSSize(width: 480, height: 380)
    private let defaults: UserDefaults
    private let key = "RuleEditorWindow.contentSize"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func restoredSize(in visibleFrame: NSRect) -> NSSize {
        let saved = defaults.dictionary(forKey: key)
        let width = saved?["width"] as? Double ?? 620
        let height = saved?["height"] as? Double ?? 680
        // A smaller monitor must not strand the editor outside the usable screen.
        let maximumWidth = max(Self.minimum.width, visibleFrame.width - 48)
        let maximumHeight = max(Self.minimum.height, visibleFrame.height - 80)
        return NSSize(width: min(maximumWidth, max(Self.minimum.width, width.isFinite ? width : 620)),
                      height: min(maximumHeight, max(Self.minimum.height, height.isFinite ? height : 680)))
    }

    func save(_ size: NSSize) {
        guard size.width.isFinite, size.height.isFinite,
              size.width >= Self.minimum.width, size.height >= Self.minimum.height else { return }
        defaults.set(["width": size.width, "height": size.height], forKey: key)
    }
}

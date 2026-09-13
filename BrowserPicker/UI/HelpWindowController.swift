import AppKit
import WebKit

@MainActor
final class HelpWindowController: NSObject, NSWindowDelegate {
    static let faq = HelpWindowController(resourceName: "faq", title: "Browser Picker — FAQ")
    static let ruleMatching = HelpWindowController(resourceName: "rule-matching-help", title: "Browser Picker — Matching Help")

    private var window: NSWindow?
    private let resourceName: String
    private let title: String

    private init(resourceName: String, title: String) {
        self.resourceName = resourceName
        self.title = title
        super.init()
    }

    func show() {
        if window == nil {
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 660, height: 640))
            webView.setValue(false, forKey: "drawsBackground")
            loadHelp(into: webView)

            let newWindow = NSPanel(contentRect: webView.frame,
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered,
                                     defer: false)
            newWindow.title = title
            newWindow.worksWhenModal = true
            newWindow.hidesOnDeactivate = false
            newWindow.contentView = webView
            newWindow.minSize = NSSize(width: 460, height: 480)
            newWindow.center()
            newWindow.delegate = self
            newWindow.isReleasedWhenClosed = false
            window = newWindow
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadHelp(into webView: WKWebView) {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(
                "<h2 style='font-family:-apple-system'>Help not found.</h2><p style='font-family:-apple-system'>Please contact <a href='mailto:mertizci@gmail.com'>mertizci@gmail.com</a>.</p>",
                baseURL: nil
            )
        }
    }
}

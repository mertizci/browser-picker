import AppKit
import WebKit

@MainActor
final class FAQWindowController: NSObject, NSWindowDelegate {
    static let shared = FAQWindowController()

    private var window: NSWindow?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 560, height: 640))
            webView.setValue(false, forKey: "drawsBackground")
            loadFAQ(into: webView)

            let newWindow = NSWindow(contentRect: webView.frame,
                                     styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                     backing: .buffered,
                                     defer: false)
            newWindow.title = "Browser Picker — FAQ"
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

    private func loadFAQ(into webView: WKWebView) {
        if let url = Bundle.main.url(forResource: "faq", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(
                "<h2 style='font-family:-apple-system'>FAQ not found.</h2><p style='font-family:-apple-system'>Please contact <a href='mailto:mertizci@gmail.com'>mertizci@gmail.com</a>.</p>",
                baseURL: nil
            )
        }
    }
}

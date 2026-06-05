import AppKit
import SwiftUI

enum BrowserIconProvider {
    static func icon(for browser: BrowserKind, size: CGFloat = 20) -> NSImage {
        if let appURL = browser.installedAppURL {
            let image = NSWorkspace.shared.icon(forFile: appURL.path)
            image.size = NSSize(width: size, height: size)
            return image
        }
        return fallbackIcon(for: browser, size: size)
    }

    static func icon(for profile: BrowserProfile, size: CGFloat = 20) -> NSImage {
        icon(for: profile.browser, size: size)
    }

    private static func fallbackIcon(for browser: BrowserKind, size: CGFloat) -> NSImage {
        if let bundled = bundledSVGIcon(for: browser, size: size) {
            return bundled
        }

        let symbolName: String
        switch browser {
        case .chrome, .edge, .brave, .vivaldi: symbolName = "globe"
        case .firefox: symbolName = "flame"
        case .safari: symbolName = "safari"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: browser.displayName) {
            image.size = NSSize(width: size, height: size)
            return image
        }

        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: size, height: size)).fill()
        image.unlockFocus()
        return image
    }

    private static func bundledSVGIcon(for browser: BrowserKind, size: CGFloat) -> NSImage? {
        guard let url = Bundle.main.url(
            forResource: browser.rawValue,
            withExtension: "svg",
            subdirectory: "Resources/Icons/browsers"
        ) else { return nil }

        guard let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: size, height: size)
        return image
    }
}

struct BrowserIconView: View {
    let browser: BrowserKind
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: BrowserIconProvider.icon(for: browser, size: size))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

struct ProfileIconView: View {
    let profile: BrowserProfile
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: BrowserIconProvider.icon(for: profile, size: size))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

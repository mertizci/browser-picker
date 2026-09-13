import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum BrowserIconProvider {
    static func icon(for browser: BrowserKind, size: CGFloat = 20) -> NSImage {
        if let appURL = browser.installedAppURL {
            let image = NSWorkspace.shared.icon(forFile: appURL.path)
            image.size = NSSize(width: size, height: size)
            return image
        }
        return fallbackIcon(for: browser, size: size)
    }

    static func icon(for profile: BrowserProfile, customIconData: Data? = nil, size: CGFloat = 20) -> NSImage {
        if let customIconData, let image = NSImage(data: customIconData), image.isValid {
            return image
        }
        return icon(for: profile.browser, size: size)
    }

    private static func fallbackIcon(for browser: BrowserKind, size: CGFloat) -> NSImage {
        if let bundled = bundledSVGIcon(for: browser, size: size) {
            return bundled
        }

        let symbolName: String
        switch browser {
        case .chrome, .edge, .brave, .vivaldi, .dia: symbolName = "globe"
        case .firefox, .zen: symbolName = "flame"
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
    @EnvironmentObject private var settingsStore: SettingsStore
    let profile: BrowserProfile
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: BrowserIconProvider.icon(
            for: profile,
            customIconData: settingsStore.customIconData(for: profile),
            size: size
        ))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}

enum ProfileIconImporter {
    static let supportedTypes: [UTType] = [.png, .jpeg, .heic, .tiff, .gif, .bmp]

    /// Store a small, self-contained image so moving the original file is harmless.
    static func pngData(from url: URL) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 256
              ] as CFDictionary) else {
            throw ImportError.invalidImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ImportError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportError.invalidImage }
        return data as Data
    }

    private enum ImportError: LocalizedError {
        case invalidImage

        var errorDescription: String? {
            "This image could not be read. Choose a PNG, JPEG, HEIC, TIFF, GIF, or BMP image."
        }
    }
}

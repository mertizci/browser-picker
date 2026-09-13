import Foundation

protocol ProfileDiscovery {
    var browser: BrowserKind { get }
    func discoverProfiles() -> [BrowserProfile]
}

enum ProfileDiscoveryService {
    static let discoverers: [ProfileDiscovery] =
        BrowserKind.allCases
            .filter { $0.engine == .chromium }
            .map { ChromiumProfileDiscovery(browser: $0) }
        + BrowserKind.allCases
            .filter { $0.engine == .gecko }
            .map { GeckoProfileDiscovery(browser: $0) }
        + [SafariProfileDiscovery()]

    static func discoverAll() -> [BrowserProfile] {
        discoverers.flatMap { $0.discoverProfiles() }
    }

    static func discoverBrowsers() -> [BrowserProfile] {
        BrowserKind.allCases.filter(\.isInstalled).map { .browserOnly(for: $0) }
    }
}

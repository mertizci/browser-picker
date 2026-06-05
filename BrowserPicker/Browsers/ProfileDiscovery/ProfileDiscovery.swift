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
        + [FirefoxProfileDiscovery(), SafariProfileDiscovery()]

    static func discoverAll() -> [BrowserProfile] {
        discoverers.flatMap { $0.discoverProfiles() }
    }
}

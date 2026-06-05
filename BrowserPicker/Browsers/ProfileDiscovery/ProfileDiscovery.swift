import Foundation

protocol ProfileDiscovery {
    var browser: BrowserKind { get }
    func discoverProfiles() -> [BrowserProfile]
}

enum ProfileDiscoveryService {
    static let discoverers: [ProfileDiscovery] = [
        ChromeProfileDiscovery(),
        FirefoxProfileDiscovery(),
        SafariProfileDiscovery()
    ]

    static func discoverAll() -> [BrowserProfile] {
        discoverers.flatMap { $0.discoverProfiles() }
    }
}

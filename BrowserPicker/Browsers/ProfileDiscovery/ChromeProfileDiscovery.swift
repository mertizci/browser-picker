import Foundation

/// Discovers profiles for any Chromium-based browser (Chrome, Edge, Brave, Vivaldi)
/// by reading the browser's `Local State` JSON.
struct ChromiumProfileDiscovery: ProfileDiscovery {
    let browser: BrowserKind

    private var localStateURL: URL? {
        guard let relativePath = browser.chromiumLocalStateRelativePath else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(relativePath)")
    }

    func discoverProfiles() -> [BrowserProfile] {
        guard browser.isInstalled else { return [] }

        guard let localStateURL,
              let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return [BrowserProfile.defaultProfile(for: browser)]
        }

        return infoCache.keys.sorted().map { key in
            let entry = infoCache[key] as? [String: Any]
            let name = entry?["name"] as? String ?? key
            return BrowserProfile(
                id: key,
                displayName: name,
                browser: browser,
                profilePath: key,
                internalName: nil
            )
        }
    }
}

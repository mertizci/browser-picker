import Foundation

struct ChromeProfileDiscovery: ProfileDiscovery {
    let browser: BrowserKind = .chrome

    private var localStateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
    }

    func discoverProfiles() -> [BrowserProfile] {
        guard FileManager.default.fileExists(atPath: browser.appPath),
              let data = try? Data(contentsOf: localStateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            if FileManager.default.fileExists(atPath: browser.appPath) {
                return [BrowserProfile.defaultProfile(for: .chrome)]
            }
            return []
        }

        return infoCache.keys.sorted().map { key in
            let entry = infoCache[key] as? [String: Any]
            let name = entry?["name"] as? String ?? key
            return BrowserProfile(
                id: key,
                displayName: name,
                browser: .chrome,
                profilePath: key,
                internalName: nil
            )
        }
    }
}

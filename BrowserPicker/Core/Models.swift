import Foundation

enum BrowserKind: String, Codable, CaseIterable, Identifiable {
    case chrome
    case firefox
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .safari: return "Safari"
        }
    }

    var appPath: String {
        switch self {
        case .chrome: return "/Applications/Google Chrome.app"
        case .firefox: return "/Applications/Firefox.app"
        case .safari: return "/Applications/Safari.app"
        }
    }

    var executablePath: String {
        switch self {
        case .chrome:
            return "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        case .firefox:
            return "/Applications/Firefox.app/Contents/MacOS/firefox"
        case .safari:
            return "/Applications/Safari.app/Contents/MacOS/Safari"
        }
    }
}

struct BrowserProfile: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var browser: BrowserKind
    var profilePath: String?
    /// Firefox `profiles.ini` Name field — used for `-P` launch fallback.
    var internalName: String?

    static func defaultProfile(for browser: BrowserKind) -> BrowserProfile {
        BrowserProfile(
            id: "\(browser.rawValue)-default",
            displayName: "Default",
            browser: browser,
            profilePath: nil,
            internalName: nil
        )
    }
}

struct RouteTarget: Codable, Hashable {
    var browser: BrowserKind
    var profileId: String

    var label: String {
        "\(browser.displayName) · \(profileId)"
    }
}

enum FallbackMode: String, Codable, CaseIterable, Identifiable {
    case silent
    case picker

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .silent: return "Use menu bar selection"
        case .picker: return "Show picker"
        }
    }
}

enum RuleMatcherKind: String, Codable, CaseIterable, Identifiable {
    case urlContains
    case hostEquals
    case hostSuffix

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .urlContains: return "URL contains"
        case .hostEquals: return "Host equals"
        case .hostSuffix: return "Host suffix"
        }
    }
}

struct RuleMatcher: Codable, Hashable {
    var kind: RuleMatcherKind
    var value: String

    func matches(url: URL, sourceApp: String?) -> Bool {
        let urlString = url.absoluteString.lowercased()
        let host = (url.host ?? "").lowercased()
        let valueLower = value.lowercased()

        switch kind {
        case .urlContains:
            return urlString.contains(valueLower)
        case .hostEquals:
            return host == valueLower
        case .hostSuffix:
            return host.hasSuffix(valueLower.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                || host == valueLower.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }
    }
}

struct RoutingRule: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var enabled: Bool
    var priority: Int
    var matcher: RuleMatcher
    var target: RouteTarget

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        priority: Int,
        matcher: RuleMatcher,
        target: RouteTarget
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.matcher = matcher
        self.target = target
    }
}

struct AppSettings: Codable {
    var fallbackMode: FallbackMode
    var defaultTarget: RouteTarget
    var rules: [RoutingRule]

    static var `default`: AppSettings {
        AppSettings(
            fallbackMode: .silent,
            defaultTarget: RouteTarget(browser: .safari, profileId: SafariProfileRecord.defaultID),
            rules: []
        )
    }
}

struct RoutingContext {
    let url: URL
    let sourceApp: String?
}

enum BrowserPickerError: LocalizedError {
    case browserNotInstalled(BrowserKind)
    case profileNotFound
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserNotInstalled(let browser):
            return "\(browser.displayName) is not installed."
        case .profileNotFound:
            return "The selected browser profile could not be found."
        case .launchFailed(let message):
            return "Failed to open link: \(message)"
        }
    }
}

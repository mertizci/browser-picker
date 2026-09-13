import AppKit
import Foundation

enum BrowserEngine {
    case chromium
    case gecko
    case webkit
}

/// How a browser is told to open a link in one of its profiles. This is not
/// implied by the rendering engine: Dia renders with Chromium but is a native
/// app that never sees Chromium's command line, and Zen adds spaces on top of
/// Gecko's profiles.
enum ProfileLaunchStyle {
    /// Chromium's `--profile-directory` switch.
    case chromiumArguments
    /// Firefox's `--profile` and `-P` switches.
    case geckoArguments
    /// Safari exposes no profile switch, so its windows are driven by AppleScript.
    case safariAutomation
    /// Dia drops every command-line argument — including the URL — so it is
    /// driven by AppleScript as well.
    case diaAutomation
    /// Zen takes Gecko's profile switches, but its spaces only exist in the UI.
    case zenAutomation
}

enum BrowserKind: String, Codable, CaseIterable, Identifiable {
    case chrome
    case edge
    case brave
    case vivaldi
    case dia
    case firefox
    case zen
    case safari

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Chrome"
        case .edge: return "Edge"
        case .brave: return "Brave"
        case .vivaldi: return "Vivaldi"
        case .dia: return "Dia"
        case .firefox: return "Firefox"
        case .zen: return "Zen"
        case .safari: return "Safari"
        }
    }

    var engine: BrowserEngine {
        switch self {
        case .chrome, .edge, .brave, .vivaldi, .dia: return .chromium
        case .firefox, .zen: return .gecko
        case .safari: return .webkit
        }
    }

    var profileLaunchStyle: ProfileLaunchStyle {
        switch self {
        case .chrome, .edge, .brave, .vivaldi: return .chromiumArguments
        case .dia: return .diaAutomation
        case .firefox: return .geckoArguments
        case .zen: return .zenAutomation
        case .safari: return .safariAutomation
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .edge: return "com.microsoft.edgemac"
        case .brave: return "com.brave.Browser"
        case .vivaldi: return "com.vivaldi.Vivaldi"
        case .dia: return "company.thebrowser.dia"
        case .firefox: return "org.mozilla.firefox"
        case .zen: return "app.zen-browser.zen"
        case .safari: return "com.apple.Safari"
        }
    }

    /// Default install location, used as a fallback when bundle-ID lookup fails.
    private var defaultAppPath: String {
        switch self {
        case .chrome: return "/Applications/Google Chrome.app"
        case .edge: return "/Applications/Microsoft Edge.app"
        case .brave: return "/Applications/Brave Browser.app"
        case .vivaldi: return "/Applications/Vivaldi.app"
        case .dia: return "/Applications/Dia.app"
        case .firefox: return "/Applications/Firefox.app"
        case .zen: return "/Applications/Zen.app"
        case .safari: return "/Applications/Safari.app"
        }
    }

    /// Resolves the installed app URL by bundle identifier (any location), else the default path.
    var installedAppURL: URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return url
        }
        if FileManager.default.fileExists(atPath: defaultAppPath) {
            return URL(fileURLWithPath: defaultAppPath)
        }
        return nil
    }

    var isInstalled: Bool { installedAppURL != nil }

    var appPath: String {
        installedAppURL?.path ?? defaultAppPath
    }

    /// Absolute path to the launchable executable inside the resolved app bundle.
    var executablePath: String {
        if let appURL = installedAppURL,
           let executableURL = Bundle(url: appURL)?.executableURL {
            return executableURL.path
        }
        return "\(defaultAppPath)/Contents/MacOS/\(defaultExecutableName)"
    }

    private var defaultExecutableName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .edge: return "Microsoft Edge"
        case .brave: return "Brave Browser"
        case .vivaldi: return "Vivaldi"
        case .dia: return "Dia"
        case .firefox: return "firefox"
        case .zen: return "zen"
        case .safari: return "Safari"
        }
    }

    /// Path (relative to `~/Library/Application Support`) of the Chromium "Local State" file.
    var chromiumLocalStateRelativePath: String? {
        switch self {
        case .chrome: return "Google/Chrome/Local State"
        case .edge: return "Microsoft Edge/Local State"
        case .brave: return "BraveSoftware/Brave-Browser/Local State"
        case .vivaldi: return "Vivaldi/Local State"
        case .dia: return "Dia/User Data/Local State"
        case .firefox, .zen, .safari: return nil
        }
    }

    /// Directory (inside `~/Library/Application Support`) where a Gecko browser
    /// keeps `profiles.ini`, its `Profiles` folder and its profile groups.
    var geckoSupportDirectoryName: String? {
        switch self {
        case .firefox: return "Firefox"
        case .zen: return "zen"
        default: return nil
        }
    }
}

/// A Zen space: a workspace living inside one profile, with its own tabs.
struct BrowserSpace: Codable, Identifiable, Hashable {
    var id: String
    /// The name Zen shows in its Spaces menu, which is how the space is picked.
    var name: String
    /// The container (Gecko's contextual identity) the space opens its tabs in,
    /// when the user bound one.
    var containerName: String? = nil

    /// The container this space belongs to, named the way Zen names it: Zen's
    /// space settings call this field "Profile" and offer "Default" for a space
    /// bound to no container. Spaces are grouped under this, so every space has
    /// a container to sit in.
    var containerLabel: String { containerName ?? "Default" }

    /// Reads as "Work · work": this space under the container holding it, for
    /// the places that name a space without grouping it.
    var nestedLabel: String { "\(containerLabel) · \(name)" }
}

struct BrowserProfile: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var browser: BrowserKind
    var profilePath: String?
    /// Firefox `profiles.ini` Name field — used for `-P` launch fallback.
    var internalName: String?
    /// Spaces inside this profile, in the browser's own order. Only Zen has them.
    var spaces: [BrowserSpace] = []

    static func defaultProfile(for browser: BrowserKind) -> BrowserProfile {
        BrowserProfile(
            id: "\(browser.rawValue)-default",
            displayName: "Default",
            browser: browser,
            profilePath: nil,
            internalName: nil
        )
    }

    func space(id spaceId: String?) -> BrowserSpace? {
        guard let spaceId else { return nil }
        return spaces.first { $0.id == spaceId }
    }

    /// The profile's spaces under the containers holding them, keeping the
    /// browser's own order of the containers as much as of the spaces inside
    /// them, so lists read like the browser's own menus.
    var spacesByContainer: [(container: String, spaces: [BrowserSpace])] {
        var containerOrder: [String] = []
        var grouped: [String: [BrowserSpace]] = [:]

        for space in spaces {
            if grouped[space.containerLabel] == nil {
                containerOrder.append(space.containerLabel)
            }
            grouped[space.containerLabel, default: []].append(space)
        }

        return containerOrder.map { ($0, grouped[$0] ?? []) }
    }
}

struct RouteTarget: Codable, Hashable {
    var browser: BrowserKind
    var profileId: String
    /// A space inside the profile, or `nil` to use whichever space is open.
    var spaceId: String? = nil

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
    /// Imported PNGs, keyed by browser and stable profile ID, independent of discovery.
    var profileIcons: [String: [String: Data]]

    init(
        fallbackMode: FallbackMode,
        defaultTarget: RouteTarget,
        rules: [RoutingRule],
        profileIcons: [String: [String: Data]] = [:]
    ) {
        self.fallbackMode = fallbackMode
        self.defaultTarget = defaultTarget
        self.rules = rules
        self.profileIcons = profileIcons
    }

    private enum CodingKeys: String, CodingKey {
        case fallbackMode, defaultTarget, rules, profileIcons
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fallbackMode = try container.decode(FallbackMode.self, forKey: .fallbackMode)
        defaultTarget = try container.decode(RouteTarget.self, forKey: .defaultTarget)
        rules = try container.decode([RoutingRule].self, forKey: .rules)
        profileIcons = try container.decodeIfPresent([String: [String: Data]].self, forKey: .profileIcons) ?? [:]
    }

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

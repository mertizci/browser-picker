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
    static func browserOnly(for browser: BrowserKind) -> BrowserProfile {
        BrowserProfile(id: "browser-only", displayName: browser.displayName, browser: browser)
    }

    var isBrowserOnly: Bool { id == "browser-only" }

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
    case pathEquals
    case pathPrefix
    case pathContains
    case urlRegex
    case sourceApplication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .urlContains: return "URL contains"
        case .hostEquals: return "Host equals"
        case .hostSuffix: return "Host suffix"
        case .pathEquals: return "Path equals"
        case .pathPrefix: return "Path starts with"
        case .pathContains: return "Path contains"
        case .urlRegex: return "URL regex"
        case .sourceApplication: return "Source application"
        }
    }
}

struct RuleMatcher: Codable, Hashable {
    var kind: RuleMatcherKind
    var value: String
    var isNegated: Bool
    var applicationName: String?

    init(kind: RuleMatcherKind, value: String, isNegated: Bool = false, applicationName: String? = nil) {
        self.kind = kind
        self.value = value
        self.isNegated = isNegated
        self.applicationName = applicationName
    }

    private enum CodingKeys: String, CodingKey {
        case kind, value, isNegated, applicationName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(RuleMatcherKind.self, forKey: .kind)
        value = try container.decode(String.self, forKey: .value)
        isNegated = try container.decodeIfPresent(Bool.self, forKey: .isNegated) ?? false
        applicationName = try container.decodeIfPresent(String.self, forKey: .applicationName)
    }

    var normalizedValue: String {
        kind == .urlRegex ? value : value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var summary: String {
        "\(isNegated ? "NOT " : "")\(kind.displayName): \(kind == .sourceApplication ? (applicationName ?? normalizedValue) : normalizedValue)"
    }

    var isValid: Bool {
        validationMessage == nil
    }

    var validationMessage: String? {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "Enter a value." }
        switch kind {
        case .sourceApplication:
            if normalizedValue.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
                return "Choose an application from the list."
            }
        case .hostSuffix:
            if normalizedValue.trimmingCharacters(in: CharacterSet(charactersIn: ".")).isEmpty {
                return "Enter a domain, such as company.com."
            }
        case .pathEquals, .pathPrefix:
            if !normalizedValue.hasPrefix("/") { return "Start the path with /, for example /work/." }
        case .urlRegex:
            if (try? NSRegularExpression(pattern: value)) == nil { return "Invalid regular expression. See Matching help for examples." }
        default: break
        }
        return nil
    }

    func matches(url: URL, sourceApp: String?) -> Bool {
        guard isValid else { return false }
        let urlString = url.absoluteString.lowercased()
        let host = (url.host ?? "").lowercased()
        let valueLower = normalizedValue.lowercased()
        let decodedPath = url.path(percentEncoded: false)
        let path = decodedPath.isEmpty ? "/" : decodedPath
        let matched: Bool

        switch kind {
        case .sourceApplication:
            // Unknown is not the same as a different app, including under NOT.
            guard let sourceApp, !sourceApp.isEmpty else { return false }
            matched = sourceApp.caseInsensitiveCompare(normalizedValue) == .orderedSame
        case .urlContains:
            matched = urlString.contains(valueLower)
        case .hostEquals:
            matched = host == valueLower
        case .hostSuffix:
            matched = host.hasSuffix(valueLower.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                || host == valueLower.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        case .pathEquals:
            matched = path == normalizedValue
        case .pathPrefix:
            matched = path.hasPrefix(normalizedValue)
        case .pathContains:
            matched = path.contains(normalizedValue)
        case .urlRegex:
            // An invalid or interrupted expression must not become a match under NOT.
            guard let result = regexMatches(url.absoluteString) else { return false }
            matched = result
        }
        return isNegated ? !matched : matched
    }

    private func regexMatches(_ string: String) -> Bool? {
        guard let regex = try? NSRegularExpression(pattern: value) else { return nil }
        let deadline = Date.timeIntervalSinceReferenceDate + 0.05
        var matched = false
        var interrupted = false
        regex.enumerateMatches(in: string, options: .reportProgress, range: NSRange(string.startIndex..., in: string)) { result, flags, stop in
            if flags.contains(.internalError) || Date.timeIntervalSinceReferenceDate > deadline {
                interrupted = true
                stop.pointee = true
            } else if result != nil {
                matched = true
                stop.pointee = true
            }
        }
        return interrupted ? nil : matched
    }
}

enum RuleMatchMode: String, Codable, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }
    var displayName: String { self == .any ? "Any (OR)" : "All (AND)" }
    var conjunction: String { self == .any ? "OR" : "AND" }
    var explanation: String {
        self == .any
            ? "The rule applies when any one of these conditions matches."
            : "The rule applies only when all of these conditions match the same link."
    }
}

struct RoutingRule: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var enabled: Bool
    var priority: Int
    var matchers: [RuleMatcher]
    var matchMode: RuleMatchMode
    var target: RouteTarget

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        priority: Int,
        matchers: [RuleMatcher],
        matchMode: RuleMatchMode = .any,
        target: RouteTarget
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.matchers = matchers
        self.matchMode = matchMode
        self.target = target
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, priority, matchers, matcher, matchMode, target
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        priority = try container.decode(Int.self, forKey: .priority)
        target = try container.decode(RouteTarget.self, forKey: .target)
        matchMode = try container.decodeIfPresent(RuleMatchMode.self, forKey: .matchMode) ?? .any
        // Existing installations store one condition under "matcher".
        matchers = try container.decodeIfPresent([RuleMatcher].self, forKey: .matchers)
            ?? [container.decode(RuleMatcher.self, forKey: .matcher)]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(priority, forKey: .priority)
        try container.encode(matchers, forKey: .matchers)
        try container.encode(matchMode, forKey: .matchMode)
        try container.encode(target, forKey: .target)
    }

    func matches(url: URL, sourceApp: String?) -> Bool {
        guard !matchers.isEmpty else { return false }
        switch matchMode {
        case .any:
            return matchers.contains { $0.matches(url: url, sourceApp: sourceApp) }
        case .all:
            return matchers.allSatisfy { $0.matches(url: url, sourceApp: sourceApp) }
        }
    }
}

struct AppSettings: Codable {
    var basicMode: Bool
    var fallbackMode: FallbackMode
    var defaultTarget: RouteTarget
    var rules: [RoutingRule]
    /// Imported PNGs, keyed by browser and stable profile ID, independent of discovery.
    var profileIcons: [String: [String: Data]]
    /// Disabled IDs remain saved even when a browser is temporarily unavailable.
    var disabledProfileIDs: [String: Set<String>]

    init(
        fallbackMode: FallbackMode,
        defaultTarget: RouteTarget,
        rules: [RoutingRule],
        profileIcons: [String: [String: Data]] = [:],
        disabledProfileIDs: [String: Set<String>] = [:],
        basicMode: Bool = false
    ) {
        self.basicMode = basicMode
        self.fallbackMode = fallbackMode
        self.defaultTarget = defaultTarget
        self.rules = rules
        self.profileIcons = profileIcons
        self.disabledProfileIDs = disabledProfileIDs
    }

    private enum CodingKeys: String, CodingKey {
        case fallbackMode, defaultTarget, rules, profileIcons, disabledProfileIDs, basicMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        basicMode = try container.decodeIfPresent(Bool.self, forKey: .basicMode) ?? false
        fallbackMode = try container.decode(FallbackMode.self, forKey: .fallbackMode)
        defaultTarget = try container.decode(RouteTarget.self, forKey: .defaultTarget)
        rules = try container.decode([RoutingRule].self, forKey: .rules)
        profileIcons = try container.decodeIfPresent([String: [String: Data]].self, forKey: .profileIcons) ?? [:]
        disabledProfileIDs = try container.decodeIfPresent([String: Set<String>].self, forKey: .disabledProfileIDs) ?? [:]
    }

    func isProfileEnabled(browser: BrowserKind, profileID: String) -> Bool {
        let id = browser == .safari && profileID == "safari-default" ? SafariProfileRecord.defaultID : profileID
        return disabledProfileIDs[browser.rawValue]?.contains(id) != true
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
    case profileDisabled
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .browserNotInstalled(let browser):
            return "\(browser.displayName) is not installed."
        case .profileNotFound:
            return "The selected browser profile could not be found."
        case .profileDisabled:
            return "This browser profile is disabled. Enable it in Settings → Browsers to open links in it."
        case .launchFailed(let message):
            return "Failed to open link: \(message)"
        }
    }
}

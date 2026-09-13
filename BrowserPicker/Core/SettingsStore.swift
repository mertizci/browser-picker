import Foundation
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published private(set) var settings: AppSettings
    @Published private(set) var profiles: [BrowserProfile] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private let configURL: URL
    private let discoverProfiles: () -> [BrowserProfile]

    init(configURL: URL? = nil, discoverProfiles: @escaping () -> [BrowserProfile] = ProfileDiscoveryService.discoverAll) {
        self.discoverProfiles = discoverProfiles
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        self.configURL = configURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BrowserPicker", isDirectory: true)
            .appendingPathComponent("config.json")

        settings = Self.loadSettings(from: self.configURL, decoder: decoder) ?? .default
    }

    func reloadProfiles() {
        profiles = discoverProfiles()
        migrateLegacySafariTargets()
        ensureDefaultTargetIsValid()
        PermissionMonitor.shared.refresh()
    }

    /// Re-read Safari profiles from the menu while Safari is open.
    func rescanSafariProfilesFromMenu() {
        guard SafariRuntime.isRunning else { return }

        var safariProfiles = profiles.filter { $0.browser != .safari }
        var recordsByID: [String: SafariProfileRecord] = [:]

        for record in SafariProfileStore.discoverProfiles() {
            recordsByID[record.id] = record
        }
        for record in SafariMenuProfileScanner.discoverProfiles() {
            recordsByID[record.id] = record
        }

        if recordsByID.isEmpty {
            recordsByID[SafariProfileRecord.defaultID] = SafariProfileRecord(
                id: SafariProfileRecord.defaultID,
                displayName: "Personal",
                menuName: "Personal"
            )
        }

        let mapped = recordsByID.values
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            .map {
                BrowserProfile(
                    id: $0.id,
                    displayName: $0.displayName,
                    browser: .safari,
                    profilePath: $0.id,
                    internalName: $0.menuName
                )
            }

        safariProfiles.append(contentsOf: mapped)
        profiles = safariProfiles
        migrateLegacySafariTargets()
        ensureDefaultTargetIsValid()
        PermissionMonitor.shared.refresh()
    }

    func save() {
        do {
            try persist(settings)
        } catch {
            NSLog("BrowserPicker: failed to save settings – \(error.localizedDescription)")
        }
    }

    private func persist(_ settings: AppSettings) throws {
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(settings)
        try data.write(to: configURL, options: .atomic)
    }

    func customIconData(for profile: BrowserProfile) -> Data? {
        settings.profileIcons[profile.browser.rawValue]?[profile.id]
    }

    var enabledProfiles: [BrowserProfile] {
        profiles.filter { isProfileEnabled($0) }
    }

    var enabledDefaultProfile: BrowserProfile? {
        guard let profile = profile(for: settings.defaultTarget), isProfileEnabled(profile) else { return nil }
        return profile
    }

    func enabledProfiles(for browser: BrowserKind) -> [BrowserProfile] {
        enabledProfiles.filter { $0.browser == browser }
    }

    func isProfileEnabled(_ profile: BrowserProfile) -> Bool {
        settings.isProfileEnabled(browser: profile.browser, profileID: profile.id)
    }

    func setProfileEnabled(_ enabled: Bool, for profile: BrowserProfile) throws {
        var updated = settings
        let browser = profile.browser.rawValue
        let profileID = profile.browser == .safari && profile.id == "safari-default" ? SafariProfileRecord.defaultID : profile.id
        if enabled {
            updated.disabledProfileIDs[browser]?.remove(profileID)
            if updated.disabledProfileIDs[browser]?.isEmpty == true {
                updated.disabledProfileIDs.removeValue(forKey: browser)
            }
        } else {
            updated.disabledProfileIDs[browser, default: []].insert(profileID)
        }
        updateDefaultTarget(in: &updated)
        try persist(updated)
        settings = updated
    }

    /// Passing nil restores the browser icon. Publish only after saving succeeds.
    func setCustomIcon(_ data: Data?, for profile: BrowserProfile) throws {
        var updated = settings
        let browser = profile.browser.rawValue
        updated.profileIcons[browser, default: [:]][profile.id] = data
        if updated.profileIcons[browser]?.isEmpty == true {
            updated.profileIcons.removeValue(forKey: browser)
        }
        try persist(updated)
        settings = updated
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        save()
    }

    func setDefaultTarget(_ target: RouteTarget) {
        guard let profile = profile(for: target), isProfileEnabled(profile) else { return }
        updateSettings { $0.defaultTarget = target }
    }

    func setFallbackMode(_ mode: FallbackMode) {
        updateSettings { $0.fallbackMode = mode }
    }

    func addRule(_ rule: RoutingRule) {
        updateSettings { settings in
            var rule = rule
            rule.priority = (settings.rules.map(\.priority).max() ?? -1) + 1
            settings.rules.append(rule)
        }
    }

    func updateRule(_ rule: RoutingRule) {
        updateSettings { settings in
            guard let index = settings.rules.firstIndex(where: { $0.id == rule.id }) else { return }
            settings.rules[index] = rule
        }
    }

    func setRuleEnabled(_ enabled: Bool, id: UUID) throws {
        var updated = settings
        guard let index = updated.rules.firstIndex(where: { $0.id == id }) else { return }
        updated.rules[index].enabled = enabled
        try persist(updated)
        settings = updated
    }

    func duplicateRule(id: UUID) throws {
        var updated = settings
        updated.rules.sort { $0.priority < $1.priority }
        guard let index = updated.rules.firstIndex(where: { $0.id == id }) else { return }
        var copy = updated.rules[index]
        copy.id = UUID()
        let baseName = "\(copy.name) Copy"
        copy.name = baseName
        var suffix = 2
        while updated.rules.contains(where: { $0.name == copy.name }) {
            copy.name = "\(baseName) \(suffix)"
            suffix += 1
        }
        updated.rules.insert(copy, at: index + 1)
        for index in updated.rules.indices {
            updated.rules[index].priority = index
        }
        try persist(updated)
        settings = updated
    }

    func deleteRule(id: UUID) {
        updateSettings { settings in
            settings.rules.removeAll { $0.id == id }
            settings.rules.sort { $0.priority < $1.priority }
            for index in settings.rules.indices {
                settings.rules[index].priority = index
            }
        }
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        updateSettings { settings in
            var rules = settings.rules.sorted { $0.priority < $1.priority }
            rules.move(fromOffsets: source, toOffset: destination)
            for index in rules.indices {
                rules[index].priority = index
            }
            settings.rules = rules
        }
    }

    func profile(for target: RouteTarget) -> BrowserProfile? {
        if let match = profiles.first(where: { $0.browser == target.browser && $0.id == target.profileId }) {
            return match
        }

        // Legacy Safari default id from early builds.
        if target.browser == .safari && target.profileId == "safari-default" {
            return profiles.first { $0.browser == .safari && $0.id == SafariProfileRecord.defaultID }
                ?? profiles.first { $0.browser == .safari }
        }

        return nil
    }

    func profiles(for browser: BrowserKind) -> [BrowserProfile] {
        profiles.filter { $0.browser == browser }
    }

    private func migrateLegacySafariTargets() {
        var changed = false

        if settings.defaultTarget.browser == .safari,
           settings.defaultTarget.profileId == "safari-default" {
            settings.defaultTarget.profileId = SafariProfileRecord.defaultID
            changed = true
        }

        for index in settings.rules.indices {
            if settings.rules[index].target.browser == .safari,
               settings.rules[index].target.profileId == "safari-default" {
                settings.rules[index].target.profileId = SafariProfileRecord.defaultID
                changed = true
            }
        }

        if changed { save() }
    }

    private func ensureDefaultTargetIsValid() {
        var updated = settings
        updateDefaultTarget(in: &updated)
        guard updated.defaultTarget != settings.defaultTarget else { return }
        settings = updated
        save()
    }

    private func updateDefaultTarget(in settings: inout AppSettings) {
        if let current = profile(for: settings.defaultTarget),
           settings.isProfileEnabled(browser: current.browser, profileID: current.id) { return }

        if let first = profiles.first(where: { settings.isProfileEnabled(browser: $0.browser, profileID: $0.id) }) {
            settings.defaultTarget = RouteTarget(browser: first.browser, profileId: first.id)
        }
        // With none enabled, keep the saved target but expose no active profile.
        // Routing then shows the empty picker so users can re-enable a profile.
    }

    private static func loadSettings(from url: URL, decoder: JSONDecoder) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AppSettings.self, from: data)
    }
}

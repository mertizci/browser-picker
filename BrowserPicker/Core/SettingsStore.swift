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

    private var configURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("BrowserPicker", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("config.json")
    }

    private init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("BrowserPicker", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let loadedURL = folder.appendingPathComponent("config.json")

        settings = Self.loadSettings(from: loadedURL, decoder: decoder) ?? .default
    }

    func reloadProfiles() {
        profiles = ProfileDiscoveryService.discoverAll()
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
            let data = try encoder.encode(settings)
            try data.write(to: configURL, options: .atomic)
        } catch {
            NSLog("BrowserPicker: failed to save settings – \(error.localizedDescription)")
        }
    }

    func updateSettings(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        save()
    }

    func setDefaultTarget(_ target: RouteTarget) {
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
        if profile(for: settings.defaultTarget) != nil { return }

        if settings.defaultTarget.browser == .safari,
           settings.defaultTarget.profileId == "safari-default",
           let safariDefault = profiles.first(where: { $0.browser == .safari && $0.id == SafariProfileRecord.defaultID }) {
            settings.defaultTarget = RouteTarget(browser: .safari, profileId: safariDefault.id)
            save()
            return
        }

        if let first = profiles.first {
            settings.defaultTarget = RouteTarget(browser: first.browser, profileId: first.id)
            save()
        }
    }

    private static func loadSettings(from url: URL, decoder: JSONDecoder) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(AppSettings.self, from: data)
    }
}

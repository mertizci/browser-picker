import Foundation
@testable import BrowserPicker

/// Run with scripts/test-profile-availability.sh. Uses temporary settings and
/// fixture discovery; it never launches a browser or changes user settings.
@main
struct ProfileAvailabilityChecks {
    @MainActor
    static func main() throws {
        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: folder) }
        let configURL = folder.appendingPathComponent("config.json")

        let work = BrowserProfile(id: "Profile 1", displayName: "Work", browser: .chrome)
        let personal = BrowserProfile(id: "Profile 2", displayName: "Work", browser: .chrome)
        let safari = BrowserProfile.defaultProfile(for: .safari)
        let safariProfile = BrowserProfile(id: SafariProfileRecord.defaultID, displayName: "Personal", browser: .safari)
        let edge = BrowserProfile(id: work.id, displayName: "Work", browser: .edge)
        let zen = BrowserProfile(id: "zen-work", displayName: "Work", browser: .zen, spaces: [
            BrowserSpace(id: "space-work", name: "Work", containerName: "Company")
        ])
        var discovered = [work, personal, safariProfile, edge, zen]
        let workTarget = RouteTarget(browser: work.browser, profileId: work.id)
        let personalTarget = RouteTarget(browser: personal.browser, profileId: personal.id)
        let matcher = RuleMatcher(kind: .hostEquals, value: "example.com")
        let firstRule = RoutingRule(name: "Work first", priority: 0, matchers: [matcher], target: workTarget)
        let secondRule = RoutingRule(name: "Personal next", priority: 1, matchers: [matcher], target: personalTarget)
        let icon = Data("saved icon".utf8)
        let original = AppSettings(
            fallbackMode: .silent, defaultTarget: workTarget, rules: [firstRule, secondRule],
            profileIcons: [work.browser.rawValue: [work.id: icon]]
        )

        var legacyJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacyJSON.removeValue(forKey: "disabledProfileIDs")
        try JSONSerialization.data(withJSONObject: legacyJSON).write(to: configURL)
        let store = SettingsStore(configURL: configURL, discoverProfiles: { discovered })
        store.reloadProfiles()
        assert(store.enabledProfiles == discovered)
        assert(store.settings.rules == original.rules)
        assert(store.settings.defaultTarget == workTarget)
        assert(store.customIconData(for: work) == icon)
        print("PASS: older settings enable all profiles and preserve rules, icons, and defaults")

        try store.setProfileEnabled(false, for: work)
        try store.setProfileEnabled(false, for: work)
        assert(!store.isProfileEnabled(work))
        assert(store.isProfileEnabled(personal) && store.isProfileEnabled(edge))
        assert(store.settings.disabledProfileIDs["chrome"] == [work.id])
        assert(store.profiles == discovered)
        assert(store.enabledProfiles(for: .chrome) == [personal])
        assert(store.enabledDefaultProfile == personal)
        store.setDefaultTarget(workTarget)
        assert(store.settings.defaultTarget == personalTarget)
        assert(store.customIconData(for: work) == icon)
        print("PASS: disabling is isolated by browser and stable ID and replaces the active default")

        let context = RoutingContext(url: URL(string: "https://example.com/path")!, sourceApp: nil)
        let engine = RuleEngine()
        assert(engine.matchingRule(for: context, in: store.settings)?.id == secondRule.id)
        assert(engine.resolveTarget(for: context, settings: store.settings) == personalTarget)
        try store.setProfileEnabled(false, for: personal)
        assert(engine.matchingRule(for: context, in: store.settings) == nil)
        assert(engine.resolveTarget(for: context, settings: store.settings) == store.settings.defaultTarget)
        assert(store.enabledDefaultProfile == safariProfile)
        assert(store.settings.rules == original.rules)
        try store.setProfileEnabled(true, for: work)
        assert(engine.matchingRule(for: context, in: store.settings)?.id == firstRule.id)
        print("PASS: disabled rule destinations are skipped, later rules/fallback work, and re-enabling resumes rules")

        try store.setProfileEnabled(false, for: zen)
        let destinations = RouteDestinationGroup.all(in: store.enabledProfiles).flatMap(\.destinations)
        assert(!destinations.contains { $0.profile == zen })
        assert(!destinations.contains { $0.space?.id == "space-work" })
        try store.setProfileEnabled(false, for: safari)
        assert(!store.isProfileEnabled(safariProfile))
        let legacySafariRule = RoutingRule(name: "Legacy Safari", priority: 0, matchers: [matcher],
            target: RouteTarget(browser: safari.browser, profileId: safari.id))
        var legacySafariSettings = store.settings
        legacySafariSettings.rules = [legacySafariRule]
        assert(engine.matchingRule(for: context, in: legacySafariSettings) == nil)
        print("PASS: disabled profiles hide their spaces and block legacy Safari rule targets")

        try store.setProfileEnabled(false, for: work)
        discovered.removeAll { $0.id == work.id && $0.browser == work.browser }
        store.reloadProfiles()
        var renamed = work
        renamed.displayName = "Company"
        discovered.append(renamed)
        let newProfile = BrowserProfile(id: "new-profile", displayName: "New", browser: .chrome)
        discovered.append(newProfile)
        store.reloadProfiles()
        let restarted = SettingsStore(configURL: configURL, discoverProfiles: { discovered })
        restarted.reloadProfiles()
        assert(!restarted.isProfileEnabled(renamed))
        assert(restarted.isProfileEnabled(newProfile))
        assert(restarted.customIconData(for: renamed) == icon)
        assert(restarted.settings.rules == original.rules)
        print("PASS: refresh, temporary disappearance, renaming, and restart preserve preferences; new profiles are enabled")

        for profile in restarted.profiles {
            try restarted.setProfileEnabled(false, for: profile)
        }
        assert(restarted.enabledProfiles.isEmpty)
        assert(restarted.enabledDefaultProfile == nil)
        assert(engine.matchingRule(for: context, in: restarted.settings) == nil)
        restarted.reloadProfiles()
        assert(restarted.enabledProfiles.isEmpty && restarted.enabledDefaultProfile == nil)
        let allDisabled = SettingsStore(configURL: configURL, discoverProfiles: { discovered })
        allDisabled.reloadProfiles()
        assert(allDisabled.enabledDefaultProfile == nil)
        try allDisabled.setProfileEnabled(true, for: personal)
        assert(allDisabled.enabledProfiles == [personal])
        assert(allDisabled.settings.defaultTarget == personalTarget)
        assert(engine.matchingRule(for: context, in: allDisabled.settings)?.id == secondRule.id)
        print("PASS: all-disabled state survives refresh/restart and re-enabling restores a valid default")

        let beforeFailure = allDisabled.settings
        try fileManager.removeItem(at: configURL)
        try fileManager.createDirectory(at: configURL, withIntermediateDirectories: false)
        do {
            try allDisabled.setProfileEnabled(false, for: personal)
            fatalError("Saving to a directory should fail")
        } catch {}
        assert(allDisabled.settings.disabledProfileIDs == beforeFailure.disabledProfileIDs)
        assert(allDisabled.settings.defaultTarget == beforeFailure.defaultTarget)
        assert(allDisabled.isProfileEnabled(personal))
        print("PASS: failed saves preserve profile availability and the active default")
    }
}

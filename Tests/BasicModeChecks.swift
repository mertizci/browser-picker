import Foundation
@testable import BrowserPicker

@main
struct BasicModeChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("config.json")
        let work = BrowserProfile(id: "company", displayName: "Company", browser: .chrome)
        let target = RouteTarget(browser: .chrome, profileId: work.id, spaceId: "saved-space")
        let rule = RoutingRule(name: "Work", priority: 0, matchers: [RuleMatcher(kind: .urlContains, value: "example.com")], target: target)
        let original = AppSettings(fallbackMode: .silent, defaultTarget: target, rules: [rule],
            profileIcons: ["chrome": [work.id: Data([1, 2, 3])]], disabledProfileIDs: ["safari": ["saved-profile"]])
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        legacy.removeValue(forKey: "basicMode")
        try JSONSerialization.data(withJSONObject: legacy).write(to: config)
        var fullDiscoveries = 0
        var basicDiscoveries = 0
        let browsers: [BrowserProfile] = [.browserOnly(for: .chrome), .browserOnly(for: .safari), .browserOnly(for: .zen)]
        let store = SettingsStore(configURL: config, discoverProfiles: {
            fullDiscoveries += 1
            return [work]
        }, discoverBrowsers: {
            basicDiscoveries += 1
            return browsers
        })
        assert(!store.settings.basicMode)
        try store.setBasicMode(true)
        store.reloadProfiles()
        store.rescanSafariProfilesFromMenu()
        assert(fullDiscoveries == 0 && basicDiscoveries == 2)
        assert(store.profiles == browsers && store.enabledDefaultProfile == nil)
        assert(store.profiles.allSatisfy { $0.spaces.isEmpty && $0.profilePath == nil })
        assert(store.settings.rules == original.rules && store.settings.defaultTarget == original.defaultTarget)
        assert(store.settings.profileIcons == original.profileIcons && store.settings.disabledProfileIDs == original.disabledProfileIDs)
        assert(SettingsStore(configURL: config).settings.basicMode)
        print("PASS: Basic mode persists, skips profile/Safari discovery, and preserves saved profile settings")

        let context = RoutingContext(url: URL(string: "https://example.com/work/")!, sourceApp: nil)
        let engine = RuleEngine()
        assert(engine.matchingRule(for: context, in: store.settings) == nil)
        guard case .picker = engine.decision(for: context, settings: store.settings, hasEnabledDefault: true) else { fatalError("Basic mode must show picker, even for matching rules and silent fallback") }
        assert(RuleTester.test(url: context.url, store: store).detail.contains("Basic mode"))
        for profile in browsers {
            let destination = RouteDestination(profile: profile, space: nil)
            assert(destination.title == profile.browser.displayName && destination.subtitle == nil)
            assert(profile.routeLabel() == profile.browser.displayName)
        }
        assert(RouteDestinationGroup.all(in: store.enabledProfiles).flatMap(\.destinations).count == 3)
        print("PASS: Basic mode always asks for a browser, bypasses rules and renders one destination per browser")

        try store.setProfileEnabled(false, for: browsers[0])
        assert(!store.enabledProfiles.contains(browsers[0]) && store.enabledProfiles.contains(browsers[1]))
        assert(store.settings.defaultTarget == target)
        store.setDefaultTarget(RouteTarget(browser: .safari, profileId: "browser-only"))
        assert(store.settings.defaultTarget == target)
        for profile in browsers.dropFirst() { try store.setProfileEnabled(false, for: profile) }
        assert(store.enabledProfiles.isEmpty)
        guard case .picker = engine.decision(for: context, settings: store.settings, hasEnabledDefault: false) else { fatalError("Must show empty picker") }
        try store.setBasicMode(false)
        assert(fullDiscoveries == 1 && store.profiles == [work])
        assert(store.enabledDefaultProfile == work && store.settings.defaultTarget == target)
        assert(engine.matchingRule(for: context, in: store.settings)?.id == rule.id)
        assert(!SettingsStore(configURL: config).settings.basicMode)
        print("PASS: browser availability is separate from profiles; switching back restores default and rule behavior")

        let blockedParent = folder.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        let blocked = SettingsStore(configURL: blockedParent.appendingPathComponent("config.json"),
            discoverProfiles: { fatalError("Must not discover on failed save") },
            discoverBrowsers: { fatalError("Must not discover on failed save") })
        do {
            try blocked.setBasicMode(true)
            fatalError("Expected save failure")
        } catch {
            assert(!blocked.settings.basicMode && blocked.profiles.isEmpty)
        }
        print("PASS: failed mode saves leave the previous mode and destinations unchanged")
    }
}

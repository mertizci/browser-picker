import Foundation
@testable import BrowserPicker

@main
struct RuleTesterChecks {
    @MainActor
    static func main() throws {
        for input in ["", "example.com", "/work/", "https://", "https://exa mple.com", "https://example.com/a b", "https://example.com/%ZZ", "file:///tmp/test", "javascript:alert(1)"] {
            assert(RuleTester.parseURL(input) == nil, "Unexpected valid URL: \(input)")
        }
        for input in ["https://example.com", "  https://example.com/work/?q=hello%20world#tab\n", "http://localhost:8080/a", "https://[::1]/", "HTTPS://EXAMPLE.COM"] {
            assert(RuleTester.parseURL(input) != nil, "Unexpected invalid URL: \(input)")
        }
        print("PASS: tester validates absolute HTTP(S) URLs and preserves encoded URLs")

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configURL = folder.appendingPathComponent("config.json")
        let work = BrowserProfile(id: "work", displayName: "Company", browser: .chrome)
        let personal = BrowserProfile(id: "private", displayName: "Private", browser: .chrome)
        let zen = BrowserProfile(id: "zen-work", displayName: "Work profile", browser: .zen,
            spaces: [BrowserSpace(id: "team", name: "Team", containerName: "Company")])
        let workTarget = RouteTarget(browser: .chrome, profileId: work.id)
        let personalTarget = RouteTarget(browser: .chrome, profileId: personal.id)
        let specific = RoutingRule(name: "Company", priority: 0, matchers: [
            RuleMatcher(kind: .hostEquals, value: "example.com"),
            RuleMatcher(kind: .pathPrefix, value: "/work/"),
            RuleMatcher(kind: .urlRegex, value: "[?&]private=1", isNegated: true)
        ], matchMode: .all, target: workTarget)
        let later = RoutingRule(name: "Personal", priority: 1,
            matchers: [RuleMatcher(kind: .hostEquals, value: "example.com")], target: personalTarget)
        let settings = AppSettings(fallbackMode: .silent, defaultTarget: personalTarget, rules: [later, specific])
        try JSONEncoder().encode(settings).write(to: configURL)
        let store = SettingsStore(configURL: configURL, discoverProfiles: { [work, personal, zen] })
        store.reloadProfiles()
        let url = RuleTester.parseURL("https://example.com/work/item")!
        let unrelated = RuleTester.parseURL("https://unrelated.test/")!
        let before = try Data(contentsOf: configURL)
        let result = RuleTester.test(url: url, store: store)
        assert(result.matchedRuleID == specific.id && result.profile == work && result.target == workTarget)
        let after = try Data(contentsOf: configURL)
        assert(after == before)
        assert(store.settings.rules == settings.rules)
        let privateURL = RuleTester.parseURL("https://example.com/work/item?private=1")!
        assert(RuleTester.test(url: privateURL, store: store).matchedRuleID == later.id)
        print("PASS: tester uses priority, AND, NOT, path and regex without changing saved settings")

        try store.setRuleEnabled(false, id: specific.id)
        assert(RuleTester.test(url: url, store: store).profile == personal)
        try store.setRuleEnabled(true, id: specific.id)
        try store.setProfileEnabled(false, for: work)
        assert(RuleTester.test(url: url, store: store).matchedRuleID == later.id)
        let fallback = RuleTester.test(url: unrelated, store: store)
        assert(fallback.profile == personal && fallback.matchedRuleID == nil)
        store.updateSettings { $0.fallbackMode = .picker }
        let picker = RuleTester.test(url: unrelated, store: store)
        assert(picker.title == "Browser picker would open" && picker.target == nil)
        assert(RuleTester.test(url: url, store: store).matchedRuleID == later.id)
        try store.setProfileEnabled(false, for: personal)
        try store.setProfileEnabled(false, for: zen)
        let empty = RuleTester.test(url: url, store: store)
        assert(empty.title == "No enabled profiles" && empty.isWarning && empty.profile == nil)
        print("PASS: disabled rules/profiles, menu bar fallback, picker fallback and all-disabled state match live routing")

        try store.setProfileEnabled(true, for: personal)
        var missing = specific
        missing.target = RouteTarget(browser: .edge, profileId: "removed-profile")
        store.updateRule(missing)
        let unavailable = RuleTester.test(url: url, store: store)
        assert(unavailable.matchedRuleID == specific.id && unavailable.isWarning && unavailable.profile == nil)
        assert(unavailable.target == missing.target)
        store.updateSettings { $0.rules = []; $0.fallbackMode = .silent; $0.defaultTarget = missing.target }
        assert(RuleTester.test(url: unrelated, store: store).title == "Browser picker would open")
        print("PASS: missing matched profile reports failure; missing default opens picker")

        try store.setProfileEnabled(true, for: zen)
        store.updateSettings { $0.rules = [specific]; $0.rules[0].target = RouteTarget(browser: .zen, profileId: zen.id, spaceId: "team") }
        let space = RuleTester.test(url: url, store: store)
        assert(space.profile?.displayName == "Work profile" && space.spaceDescription == "Space: Company · Team")
        store.updateSettings { $0.rules[0].target.spaceId = "deleted-space" }
        assert(RuleTester.test(url: url, store: store).spaceDescription == "Saved space unavailable; uses the current space.")
        store.updateSettings { $0.rules[0].target.spaceId = nil }
        assert(RuleTester.test(url: url, store: store).spaceDescription == "Space: current space")
        print("PASS: tester identifies the actual profile and named/current/missing Zen spaces")
    }
}

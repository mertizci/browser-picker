import Foundation
@testable import BrowserPicker

@main
struct RuleEditingChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configURL = folder.appendingPathComponent("config.json")
        let work = BrowserProfile(id: "work", displayName: "Work", browser: .chrome)
        let personal = BrowserProfile(id: "private", displayName: "Private", browser: .chrome)
        let target = RouteTarget(browser: .chrome, profileId: work.id, spaceId: "saved-space")
        let first = RuleMatcher(kind: .hostEquals, value: "gitlab.example.com")
        let rule = RoutingRule(name: "Work", priority: 0, matchers: [first], target: target)
        let later = RoutingRule(name: "Later", priority: 1,
            matchers: [RuleMatcher(kind: .urlContains, value: "example.com")],
            target: RouteTarget(browser: .chrome, profileId: personal.id))
        let original = AppSettings(fallbackMode: .picker, defaultTarget: later.target, rules: [rule, later])

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        var legacyRules = legacy["rules"] as! [[String: Any]]
        for index in legacyRules.indices {
            legacyRules[index].removeValue(forKey: "matchMode")
            legacyRules[index]["matcher"] = (legacyRules[index].removeValue(forKey: "matchers") as! [Any])[0]
        }
        legacy["rules"] = legacyRules
        try JSONSerialization.data(withJSONObject: legacy).write(to: configURL)
        let store = SettingsStore(configURL: configURL, discoverProfiles: { [work, personal] })
        store.reloadProfiles()
        assert(store.settings.rules == original.rules)
        print("PASS: legacy single-condition JSON preserves rule IDs, routing, state, and priority")

        let conditions = [first, RuleMatcher(kind: .hostSuffix, value: ".company.test"),
            RuleMatcher(kind: .urlContains, value: "/work/")]
        var multi = rule
        multi.matchers = conditions
        store.updateRule(multi)
        let engine = RuleEngine()
        for value in ["https://gitlab.example.com", "https://docs.company.test", "https://other.test/work/item"] {
            let context = RoutingContext(url: URL(string: value)!, sourceApp: nil)
            assert(engine.matchingRule(for: context, in: store.settings)?.id == rule.id)
        }
        let unrelated = RoutingContext(url: URL(string: "https://unrelated.test")!, sourceApp: nil)
        assert(engine.matchingRule(for: unrelated, in: store.settings) == nil)
        assert(SettingsStore(configURL: configURL).settings.rules.first?.matchers == conditions)
        let savedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        let savedRule = (savedJSON["rules"] as! [[String: Any]])[0]
        assert(savedRule["matcher"] == nil && (savedRule["matchers"] as! [Any]).count == 3)
        print("PASS: any condition can trigger the rule and all condition types persist after restart")

        // The previous multi-condition format also omitted matchMode.
        var previousMulti = try JSONSerialization.jsonObject(with: JSONEncoder().encode(multi)) as! [String: Any]
        previousMulti.removeValue(forKey: "matchMode")
        let migratedMulti = try JSONDecoder().decode(RoutingRule.self, from: JSONSerialization.data(withJSONObject: previousMulti))
        assert(migratedMulti.matchMode == .any && migratedMulti.matchers == conditions)

        var allRule = multi
        allRule.matchMode = .all
        allRule.matchers = [first, RuleMatcher(kind: .urlContains, value: "/work/")]
        store.updateRule(allRule)
        let both = RoutingContext(url: URL(string: "https://gitlab.example.com/work/item")!, sourceApp: nil)
        let onlyHost = RoutingContext(url: URL(string: "https://gitlab.example.com/personal/item")!, sourceApp: nil)
        let onlyPath = RoutingContext(url: URL(string: "https://other.test/work/item")!, sourceApp: nil)
        assert(engine.matchingRule(for: both, in: store.settings)?.id == rule.id)
        assert(engine.matchingRule(for: onlyHost, in: store.settings)?.id == later.id)
        assert(engine.matchingRule(for: onlyPath, in: store.settings) == nil)
        assert(SettingsStore(configURL: configURL).settings.rules[0] == allRule)
        allRule.matchMode = .any
        assert(allRule.matches(url: onlyHost.url, sourceApp: nil))
        assert(allRule.matches(url: onlyPath.url, sourceApp: nil))
        store.updateRule(multi)
        print("PASS: AND requires every condition, OR accepts either, and modes persist with legacy rules defaulting to OR")

        for value in ["", " \n\t"] {
            let blank = RuleMatcher(kind: .urlContains, value: value)
            assert(!blank.isValid && !blank.matches(url: unrelated.url, sourceApp: nil))
        }
        assert(!RuleMatcher(kind: .hostSuffix, value: "...").isValid)
        var empty = multi
        empty.matchers = []
        assert(!empty.matches(url: unrelated.url, sourceApp: nil))
        let emptyReloaded = try JSONDecoder().decode(RoutingRule.self, from: JSONEncoder().encode(empty))
        assert(emptyReloaded.matchers.isEmpty)
        empty.matchMode = .all
        assert(!empty.matches(url: unrelated.url, sourceApp: nil))
        empty.matchers = [first, RuleMatcher(kind: .urlContains, value: "")]
        assert(!empty.matches(url: URL(string: "https://gitlab.example.com")!, sourceApp: nil))
        print("PASS: empty condition lists and blank conditions never match every URL")

        let context = RoutingContext(url: URL(string: "https://gitlab.example.com")!, sourceApp: nil)
        try store.setRuleEnabled(false, id: rule.id)
        assert(engine.matchingRule(for: context, in: store.settings)?.id == later.id)
        let disabled = store.settings.rules[0]
        assert(!disabled.enabled && disabled.matchers == conditions && disabled.target == target)
        assert(disabled.id == rule.id && disabled.priority == rule.priority)
        assert(SettingsStore(configURL: configURL).settings.rules[0] == disabled)
        try store.setRuleEnabled(true, id: rule.id)
        assert(engine.matchingRule(for: context, in: store.settings)?.id == rule.id)
        try store.setProfileEnabled(false, for: work)
        assert(engine.matchingRule(for: context, in: store.settings)?.id == later.id)
        try store.setProfileEnabled(true, for: work)
        print("PASS: list toggles persist without changing other rule fields and respect disabled profiles")

        multi.matchMode = .all
        store.updateRule(multi)
        try store.setRuleEnabled(false, id: rule.id)
        try store.duplicateRule(id: rule.id)
        let copy = store.settings.rules[1]
        assert(copy.id != rule.id && copy.name == "Work Copy" && !copy.enabled)
        assert(copy.matchers == conditions && copy.target == target)
        assert(copy.matchMode == .all)
        assert(store.settings.rules.map(\.id) == [rule.id, copy.id, later.id])
        assert(store.settings.rules.map(\.priority) == [0, 1, 2])
        var editedCopy = copy
        editedCopy.matchers.removeFirst()
        store.updateRule(editedCopy)
        assert(store.settings.rules[0].matchers == conditions)
        try store.duplicateRule(id: rule.id)
        assert(store.settings.rules[1].name == "Work Copy 2")
        assert(Set(store.settings.rules.map(\.id)).count == 4)
        assert(store.settings.rules.map(\.priority) == [0, 1, 2, 3])
        assert(SettingsStore(configURL: configURL).settings.rules == store.settings.rules)
        print("PASS: duplicates have unique IDs/names, preserve state and destination, and edit independently")

        let before = store.settings.rules
        try FileManager.default.removeItem(at: configURL)
        try FileManager.default.createDirectory(at: configURL, withIntermediateDirectories: false)
        do {
            try store.setRuleEnabled(true, id: rule.id)
            fatalError("Saving to a directory should fail")
        } catch {}
        assert(store.settings.rules == before)
        do {
            try store.duplicateRule(id: rule.id)
            fatalError("Saving to a directory should fail")
        } catch {}
        assert(store.settings.rules == before)
        print("PASS: failed toggles and duplicates leave rule state unchanged")
    }
}

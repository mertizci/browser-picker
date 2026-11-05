import Foundation
@testable import BrowserPicker

/// Rules that ask which profile to use instead of opening a fixed one. Run with
/// scripts/test-profile-availability.sh. Uses temporary settings and fixture
/// discovery; it never shows the picker or launches a browser.
@main
struct AskRuleChecks {
    @MainActor
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let configURL = folder.appendingPathComponent("config.json")

        let work = BrowserProfile(id: "work", displayName: "Work", browser: .chrome)
        let personal = BrowserProfile(id: "private", displayName: "Private", browser: .chrome)
        let firefox = BrowserProfile(id: "ff-default", displayName: "Default", browser: .firefox)
        let zen = BrowserProfile(id: "zen-main", displayName: "Main", browser: .zen, spaces: [
            BrowserSpace(id: "team", name: "Team", containerName: "Company"),
            BrowserSpace(id: "home", name: "Home")
        ])
        let safari = BrowserProfile(id: SafariProfileRecord.defaultID, displayName: "Personal", browser: .safari)
        let workTarget = RouteTarget(browser: .chrome, profileId: work.id)
        let personalTarget = RouteTarget(browser: .chrome, profileId: personal.id)
        let firefoxTarget = RouteTarget(browser: .firefox, profileId: firefox.id)
        let zenTeamTarget = RouteTarget(browser: .zen, profileId: zen.id, spaceId: "team")
        let missingTarget = RouteTarget(browser: .edge, profileId: "removed-profile")

        let google = RuleMatcher(kind: .hostEquals, value: "accounts.google.com")
        let ask = RoutingRule(name: "Google sign-in", priority: 0, matchers: [google],
                              action: .ask, target: personalTarget, choices: [personalTarget, workTarget])
        let later = RoutingRule(name: "Other Google", priority: 1,
                                matchers: [RuleMatcher(kind: .hostSuffix, value: "google.com")], target: firefoxTarget)
        let original = AppSettings(fallbackMode: .silent, defaultTarget: firefoxTarget, rules: [ask, later])
        try JSONEncoder().encode(original).write(to: configURL)
        let store = SettingsStore(configURL: configURL, discoverProfiles: { [work, personal, firefox, zen, safari] })
        store.reloadProfiles()

        // MARK: Routing decision

        let engine = RuleEngine()
        let sso = RoutingContext(url: URL(string: "https://accounts.google.com/o/oauth2/auth?client_id=x")!,
                                 sourceApp: "com.tinyspeck.slackmacgap")
        let docs = RoutingContext(url: URL(string: "https://docs.google.com/document")!, sourceApp: nil)
        func decision(_ context: RoutingContext, _ settings: AppSettings? = nil) -> RoutingDecision {
            engine.decision(for: context, settings: settings ?? store.settings, hasEnabledDefault: true)
        }
        guard case .ask(let asked) = decision(sso), asked.id == ask.id else { fatalError("An ask rule must ask") }
        guard case .rule(let opened) = decision(docs), opened.id == later.id else { fatalError("Open rules still open") }
        assert(engine.resolveTarget(for: sso, settings: store.settings, pickerChoice: workTarget) == workTarget)
        assert(engine.resolveTarget(for: sso, settings: store.settings) == personalTarget)
        var basic = store.settings
        basic.basicMode = true
        guard case .picker = decision(sso, basic) else { fatalError("Basic mode pauses ask rules too") }
        print("PASS: ask rules ask, keep their priority among open rules, and pause in Basic mode")

        try store.setProfileEnabled(false, for: work)
        guard case .ask = decision(sso) else { fatalError("One enabled choice keeps the rule active") }
        try store.setProfileEnabled(false, for: personal)
        guard case .rule(let next) = decision(sso), next.id == later.id else {
            fatalError("A rule whose choices are all disabled is skipped like a disabled open rule")
        }
        try store.setProfileEnabled(true, for: work)
        try store.setProfileEnabled(true, for: personal)
        print("PASS: an ask rule is skipped only once every choice is disabled")

        // MARK: Persistence

        let restarted = SettingsStore(configURL: configURL)
        assert(restarted.settings.rules == store.settings.rules)
        let savedJSON = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as! [String: Any]
        let savedRule = (savedJSON["rules"] as! [[String: Any]]).first { $0["name"] as? String == ask.name }!
        assert(savedRule["action"] as? String == "ask" && (savedRule["choices"] as? [Any])?.count == 2)
        // Versions without ask rules require "target" and open it instead.
        assert((savedRule["target"] as? [String: Any])?["profileId"] as? String == personal.id)

        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(later)) as! [String: Any]
        legacy.removeValue(forKey: "action")
        legacy.removeValue(forKey: "choices")
        let decoded = try JSONDecoder().decode(RoutingRule.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(decoded.action == .open && decoded.choices.isEmpty && decoded == later)
        assert(decoded.destinations == [firefoxTarget] && asked.destinations == [personalTarget, workTarget])
        print("PASS: ask rules survive a restart, keep a target for older versions, and legacy rules stay open rules")

        // MARK: What the picker offers

        func offered(_ choices: [RouteTarget]) -> [RouteDestinationGroup] {
            RouteDestinationGroup.all(in: store.enabledProfiles, offering: choices)
        }
        // Discovery order, not choice order, so the prompt reads like the browser.
        assert(offered([workTarget, personalTarget]).flatMap(\.destinations).map(\.target) == [workTarget, personalTarget])
        assert(offered([personalTarget, workTarget]).flatMap(\.destinations).map(\.target) == [workTarget, personalTarget])
        let mixed = offered([firefoxTarget, zenTeamTarget])
        assert(mixed.flatMap(\.destinations).map(\.target) == [firefoxTarget, zenTeamTarget])
        assert(mixed.map(\.title) == [nil, "Zen · Company"])
        let currentSpace = offered([RouteTarget(browser: .zen, profileId: zen.id)]).flatMap(\.destinations)
        assert(currentSpace.count == 1 && currentSpace[0].title == "Current Space")
        assert(offered([missingTarget]).isEmpty)
        assert(offered([RouteTarget(browser: .zen, profileId: zen.id, spaceId: "deleted-space")]).isEmpty)
        try store.setProfileEnabled(false, for: work)
        assert(offered([workTarget, personalTarget]).flatMap(\.destinations).map(\.target) == [personalTarget])
        assert(offered([workTarget]).isEmpty)
        try store.setProfileEnabled(true, for: work)
        print("PASS: the picker offers only enabled choices, across browsers and Zen spaces, with fitting headings")

        // MARK: Conflicts

        let analyzer = RuleConflictAnalyzer()
        func settings(_ rules: [RoutingRule]) -> AppSettings {
            var result = store.settings
            result.rules = rules.enumerated().map { index, rule in
                var copy = rule
                copy.priority = index
                return copy
            }
            return result
        }
        let sameOpen = RoutingRule(name: "Open Work", priority: 0, matchers: [google], target: workTarget)
        let openVsAsk = analyzer.conflicts(in: settings([ask, sameOpen]))[sameOpen.id]
        assert(openVsAsk?.kind == .sameConditions && openVsAsk?.hasDifferentDestination == true)
        let reordered = RoutingRule(name: "Copy", priority: 0, matchers: [google], action: .ask,
                                    target: workTarget, choices: [workTarget, personalTarget])
        assert(analyzer.conflicts(in: settings([ask, reordered]))[reordered.id]?.hasDifferentDestination == false)
        var otherChoices = reordered
        otherChoices.choices = [workTarget, firefoxTarget]
        assert(analyzer.conflicts(in: settings([ask, otherChoices]))[otherChoices.id]?.hasDifferentDestination == true)
        try store.setProfileEnabled(false, for: work)
        try store.setProfileEnabled(false, for: personal)
        assert(analyzer.conflicts(in: settings([ask, sameOpen])).isEmpty)
        try store.setProfileEnabled(true, for: work)
        try store.setProfileEnabled(true, for: personal)
        print("PASS: conflicts tell ask from open rules, ignore choice order, and skip rules with no enabled choice")

        // MARK: Rule tester and labels

        let tested = RuleTester.test(url: sso.url, store: store, sourceApp: sso.sourceApp)
        assert(tested.title == "Browser picker would open" && tested.matchedRuleID == ask.id && !tested.isWarning)
        assert(tested.detail.contains("Google sign-in") && tested.detail.contains("Chrome · Work, Chrome · Private"))
        assert(tested.profile == nil && tested.target == nil)
        assert(store.destinationLabel(for: ask) == "Ask: Chrome · Private or Chrome · Work")
        var three = ask
        three.choices = [personalTarget, workTarget, missingTarget]
        assert(store.destinationLabel(for: three) == "Ask: Chrome · Private, Chrome · Work or Edge · removed-profile")
        assert(store.destinationLabel(for: later) == "Firefox · Default")

        var unavailable = ask
        unavailable.choices = [missingTarget]
        unavailable.target = missingTarget
        store.updateRule(unavailable)
        let warning = RuleTester.test(url: sso.url, store: store)
        assert(warning.isWarning && warning.matchedRuleID == ask.id && warning.detail.contains("None of its profiles"))
        print("PASS: the tester lists what the prompt would offer and warns when none of it is available")

        // MARK: Legacy Safari IDs

        var legacySafari = ask
        legacySafari.choices = [RouteTarget(browser: .safari, profileId: "safari-default"), workTarget]
        legacySafari.target = legacySafari.choices[0]
        store.updateRule(legacySafari)
        store.reloadProfiles()
        let migrated = store.settings.rules.first { $0.id == ask.id }!
        assert(migrated.choices.first?.profileId == SafariProfileRecord.defaultID)
        assert(migrated.target.profileId == SafariProfileRecord.defaultID)
        assert(offered(migrated.choices).flatMap(\.destinations).map(\.profile) == [work, safari])
        print("PASS: legacy Safari IDs inside choices are migrated")
    }
}

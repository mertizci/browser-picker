import Foundation
@testable import BrowserPicker

@main
struct RuleConflictChecks {
    static let work = RouteTarget(browser: .chrome, profileId: "work")
    static let personal = RouteTarget(browser: .chrome, profileId: "personal")

    static func rule(_ matchers: [RuleMatcher], mode: RuleMatchMode = .any,
                     target: RouteTarget = work) -> RoutingRule {
        RoutingRule(name: "Example", priority: 0, matchers: matchers, matchMode: mode, target: target)
    }

    static func settings(_ rules: [RoutingRule]) -> AppSettings {
        var result = AppSettings.default
        result.rules = rules.enumerated().map { index, rule in
            var copy = rule
            copy.priority = index
            return copy
        }
        return result
    }

    static func conflict(_ earlier: RoutingRule, _ later: RoutingRule) -> RuleConflict? {
        RuleConflictAnalyzer().conflicts(in: settings([earlier, later]))[later.id]
    }

    static func main() {
        let host = RuleMatcher(kind: .hostEquals, value: "example.com")
        let path = RuleMatcher(kind: .pathPrefix, value: "/work/")
        let mail = RuleMatcher(kind: .sourceApplication, value: "com.apple.mail", applicationName: "Mail")
        let broad = rule([host])
        let narrow = rule([host, path, mail], mode: .all, target: personal)

        let covered = conflict(broad, narrow)!
        precondition(covered.kind == .coveredByEarlierRule && covered.hasDifferentDestination)
        precondition(covered.earlierRule.id == broad.id)
        precondition(conflict(narrow, broad) == nil)
        precondition(conflict(rule([host, mail], mode: .all), rule([host, mail], mode: .any)) == nil)
        precondition(conflict(rule([host, mail], mode: .any), narrow) != nil)
        precondition(conflict(rule([host]), rule([host, path], mode: .any)) == nil)
        precondition(conflict(rule([host, path], mode: .all), narrow) != nil)
        print("PASS: coverage honors AND/OR branches and does not confuse partial overlap with full coverage")

        let reordered = rule([RuleMatcher(kind: .sourceApplication, value: "COM.APPLE.MAIL", applicationName: "Renamed"),
                              RuleMatcher(kind: .hostEquals, value: " Example.COM "), path, path], mode: .all)
        precondition(conflict(narrow, reordered)?.kind == .sameConditions)
        precondition(conflict(broad, rule([host], mode: .all))?.kind == .sameConditions)
        precondition(conflict(broad, rule([host], target: personal))?.hasDifferentDestination == true)
        precondition(conflict(broad, rule([host]))?.hasDifferentDestination == false)
        let otherSpace = RouteTarget(browser: .chrome, profileId: "work", spaceId: "another-space")
        precondition(conflict(broad, rule([host], target: otherSpace))?.hasDifferentDestination == true)
        print("PASS: duplicate conditions ignore order, repeated entries and app display names, but retain destination and space differences")

        precondition(conflict(rule([RuleMatcher(kind: .hostSuffix, value: ".EXAMPLE.com.")]), broad) != nil)
        precondition(conflict(rule([RuleMatcher(kind: .hostSuffix, value: "example.com")]),
                              rule([RuleMatcher(kind: .hostEquals, value: "notexample.com")])) != nil)
        precondition(conflict(rule([path]), rule([RuleMatcher(kind: .pathEquals, value: "/work/report")])) != nil)
        precondition(conflict(rule([path]), rule([RuleMatcher(kind: .pathEquals, value: "/workshop")])) == nil)
        precondition(conflict(rule([path]), rule([RuleMatcher(kind: .pathPrefix, value: "/Work/")])) == nil)
        precondition(conflict(rule([RuleMatcher(kind: .pathContains, value: "work")]), rule([path])) != nil)
        precondition(conflict(rule([RuleMatcher(kind: .urlContains, value: "WORK")]),
                              rule([RuleMatcher(kind: .urlContains, value: "team/work")])) != nil)
        // Decoded path text is not necessarily present in the encoded full URL.
        precondition(conflict(rule([RuleMatcher(kind: .urlContains, value: "work")]), rule([path])) == nil)

        let notWork = rule([RuleMatcher(kind: .pathPrefix, value: "/work/", isNegated: true)])
        let notWorkAdmin = rule([RuleMatcher(kind: .pathPrefix, value: "/work/admin/", isNegated: true)])
        precondition(conflict(notWorkAdmin, notWork) != nil)
        precondition(conflict(notWork, notWorkAdmin) == nil)
        precondition(conflict(rule([path]), notWork) == nil)
        precondition(conflict(rule([mail]), rule([RuleMatcher(kind: .sourceApplication, value: mail.value, isNegated: true)])) == nil)
        print("PASS: literal suffixes, path case/boundaries, URL encoding and reversed NOT implications match routing semantics")

        let regex = RuleMatcher(kind: .urlRegex, value: "^https://example\\.com/work/")
        precondition(conflict(rule([regex]), rule([regex]))?.kind == .sameConditions)
        precondition(conflict(rule([RuleMatcher(kind: .urlRegex, value: ".*")]), rule([regex])) == nil)
        precondition(conflict(rule([regex]), narrow) == nil)
        precondition(conflict(broad, rule([host, regex], mode: .all))?.kind == .coveredByEarlierRule)
        precondition(conflict(broad, rule([host, RuleMatcher(kind: .urlRegex, value: "[")], mode: .any)) == nil)
        precondition(conflict(rule([]), broad) == nil)
        precondition(conflict(broad, rule([RuleMatcher(kind: .urlContains, value: " ")])) == nil)
        print("PASS: regexes are only compared as duplicate text; incomplete or invalid drafts are not diagnosed")

        var config = settings([broad, narrow])
        let analyzer = RuleConflictAnalyzer()
        config.rules[0].enabled = false
        precondition(analyzer.conflicts(in: config).isEmpty)
        config.rules[0].enabled = true
        config.rules[1].enabled = false
        precondition(analyzer.conflicts(in: config).isEmpty)
        config.rules[1].enabled = true
        config.disabledProfileIDs = ["chrome": ["work"]]
        precondition(analyzer.conflicts(in: config).isEmpty)
        config.disabledProfileIDs = ["chrome": ["personal"]]
        precondition(analyzer.conflicts(in: config).isEmpty)
        config.disabledProfileIDs = [:]
        config.basicMode = true
        precondition(analyzer.conflicts(in: config).isEmpty)
        config.basicMode = false
        // Profiles are not passed in: RuleEngine does not skip missing profiles.
        precondition(analyzer.conflicts(in: config)[narrow.id] != nil)
        print("PASS: disabled rules/profiles and Basic mode are ignored; missing profiles retain live routing priority")

        precondition(analyzer.conflict(for: narrow, in: settings([broad])) != nil)
        precondition(analyzer.conflict(for: broad, in: settings([broad])) == nil)
        config.rules[0].priority = 10
        config.rules[1].priority = 0
        // The saved reorder, not the stale editor priority, determines the result.
        precondition(analyzer.conflict(for: narrow, in: config) == nil)
        config = settings([broad, narrow])
        var edited = narrow
        edited.matchers = [RuleMatcher(kind: .hostEquals, value: "other.test")]
        precondition(analyzer.conflict(for: edited, in: config) == nil)
        let third = rule([host])
        let firstConflict = analyzer.conflicts(in: settings([broad, third, rule([host])]))[third.id]
        precondition(firstConflict?.earlierRule.id == broad.id)
        config.rules[1].priority = config.rules[0].priority
        precondition(analyzer.conflicts(in: config)[narrow.id]?.earlierRule.id == broad.id)
        print("PASS: draft insertion, editing, deletion/self-exclusion, equal priorities and live reordering use the saved rule order")

        // Check every reported implication against the real matcher on a varied
        // corpus. This catches AND/OR and negation errors without implementing
        // a second matcher in the test.
        let atoms = [host, path, mail,
                     RuleMatcher(kind: .hostEquals, value: "notexample.com"),
                     RuleMatcher(kind: .hostSuffix, value: "example.com"),
                     RuleMatcher(kind: .hostSuffix, value: ".com"),
                     RuleMatcher(kind: .pathEquals, value: "/work/"),
                     RuleMatcher(kind: .pathContains, value: "work"),
                     RuleMatcher(kind: .pathPrefix, value: "/work/admin/"),
                     RuleMatcher(kind: .urlContains, value: "work"),
                     RuleMatcher(kind: .urlContains, value: "work/admin")]
        let bothSigns = atoms + atoms.map { var c = $0; c.isNegated = true; return c }
        let candidates = bothSigns.map { rule([$0]) } + [broad, narrow,
            rule([host, path], mode: .any), rule([host, path], mode: .all),
            rule([host, mail], mode: .any), rule([host, mail], mode: .all),
            rule([path, mail], mode: .all), notWork, notWorkAdmin]
        let sources: [String?] = [nil, "com.apple.mail", "com.example.other"]
        var checked = 0
        for first in candidates {
            for second in candidates where first.id != second.id {
                guard conflict(first, second) != nil else { continue }
                for domain in ["example.com", "docs.example.com", "notexample.com", "other.test"] {
                    for route in ["/", "/work/", "/work/admin/", "/workshop", "/Work/", "/%77ork/report", "/?next=/work/"] {
                        let url = URL(string: "https://\(domain)\(route)")!
                        for source in sources where second.matches(url: url, sourceApp: source) {
                            precondition(first.matches(url: url, sourceApp: source), "False coverage warning for \(url)")
                            checked += 1
                        }
                    }
                }
            }
        }
        precondition(checked > 100)
        print("PASS: \(checked) matching URL/source cases confirm reported coverage against the real matcher")
    }
}

import Foundation
@testable import BrowserPicker

@main
struct AdvancedMatcherChecks {
    static func main() throws {
        func matches(_ matcher: RuleMatcher, _ url: String) -> Bool {
            matcher.matches(url: URL(string: url)!, sourceApp: nil)
        }
        let legacy = try JSONDecoder().decode(RuleMatcher.self, from: Data(#"{"kind":"urlContains","value":"work"}"#.utf8))
        assert(!legacy.isNegated && matches(legacy, "https://example.com/work/"))

        let exact = RuleMatcher(kind: .pathEquals, value: "/work/report")
        assert(matches(exact, "https://example.com/work/report?tab=1#top"))
        assert(!matches(exact, "https://example.com/work/report/"))
        assert(!matches(exact, "https://example.com/Work/report"))
        assert(!matches(exact, "https://example.com/?next=/work/report"))
        assert(matches(RuleMatcher(kind: .pathEquals, value: "/"), "https://example.com"))
        assert(matches(RuleMatcher(kind: .pathEquals, value: "/my files/a"), "https://example.com/my%20files/a"))
        let prefix = RuleMatcher(kind: .pathPrefix, value: "/work/")
        assert(matches(prefix, "https://example.com/work/report"))
        assert(!matches(prefix, "https://example.com/workspace"))
        assert(!matches(prefix, "https://example.com/work"))
        let contains = RuleMatcher(kind: .pathContains, value: "/invoices/")
        assert(matches(contains, "https://example.com/accounts/invoices/42"))
        assert(!matches(contains, "https://example.com/accounts?next=/invoices/42"))
        assert(!RuleMatcher(kind: .pathPrefix, value: "work/").isValid)
        assert(!RuleMatcher(kind: .pathEquals, value: "https://example.com/work").isValid)
        print("PASS: path matching handles boundaries, trailing slashes, case, decoding, and query exclusion")

        let exclude = RuleMatcher(kind: .pathPrefix, value: "/personal/", isNegated: true)
        assert(matches(exclude, "https://example.com/work/report"))
        assert(!matches(exclude, "https://example.com/personal/report"))
        let rule = RoutingRule(name: "Work except personal", priority: 0, matchers: [
            RuleMatcher(kind: .hostEquals, value: "example.com"), exclude,
            RuleMatcher(kind: .pathEquals, value: "/personal", isNegated: true)
        ], matchMode: .all, target: RouteTarget(browser: .chrome, profileId: "work"))
        assert(rule.matches(url: URL(string: "https://example.com/work/")!, sourceApp: nil))
        for url in ["https://example.com/personal", "https://example.com/personal/", "https://other.com/work/"] {
            assert(!rule.matches(url: URL(string: url)!, sourceApp: nil))
        }
        var any = rule
        any.matchMode = .any
        assert(any.matches(url: URL(string: "https://other.com/work/")!, sourceApp: nil))
        let restored = try JSONDecoder().decode(RoutingRule.self, from: JSONEncoder().encode(rule))
        assert(restored == rule && restored.matchers[1].isNegated)
        for kind in RuleMatcherKind.allCases {
            assert(!matches(RuleMatcher(kind: kind, value: "", isNegated: true), "https://example.com"))
        }
        print("PASS: NOT is applied per condition, respects AND/OR, persists, and never inverts invalid inputs")

        let regex = RuleMatcher(kind: .urlRegex, value: #"^https://example\.com/(work|admin)(/|[?#]|$)"#)
        assert(regex.isValid)
        assert(matches(regex, "https://example.com/work/report"))
        assert(matches(regex, "https://example.com/admin?tab=users"))
        assert(!matches(regex, "https://example.com/workspace"))
        assert(!matches(regex, "https://other.com/work/"))
        assert(!matches(regex, "https://example.com/Work/report"))
        let pdf = RuleMatcher(kind: .urlRegex, value: #"(?i)\.pdf([?#]|$)"#)
        assert(matches(pdf, "https://example.com/report.PDF?download=1"))
        assert(!matches(pdf, "https://example.com/report.pdfx"))
        let domain = RuleMatcher(kind: .urlRegex, value: #"(?i)^https?://([a-z0-9-]+\.)*example\.com(:[0-9]+)?(/|[?#]|$)"#)
        for url in ["https://example.com", "http://docs.example.com/path", "https://a.b.example.com:8443/path"] {
            assert(matches(domain, url))
        }
        assert(!matches(domain, "https://notexample.com/"))
        assert(!matches(domain, "https://example.com.evil.test/"))
        var invertedRegex = regex
        invertedRegex.isNegated = true
        assert(!matches(invertedRegex, "https://example.com/work/report"))
        assert(matches(invertedRegex, "https://example.com/personal/report"))
        assert(RuleMatcher(kind: .urlRegex, value: " x ").normalizedValue == " x ")
        let invalid = RuleMatcher(kind: .urlRegex, value: "[", isNegated: true)
        assert(invalid.validationMessage != nil && !matches(invalid, "https://example.com"))
        let restoredRegex = try JSONDecoder().decode(RuleMatcher.self, from: JSONEncoder().encode(invertedRegex))
        assert(restoredRegex == invertedRegex)
        print("PASS: regex examples, anchors, flags, NOT, validation, and serialization behave as documented")

        let slow = RuleMatcher(kind: .urlRegex, value: "(a+)+$", isNegated: true)
        let started = Date.timeIntervalSinceReferenceDate
        assert(!matches(slow, "https://example.com/" + String(repeating: "a", count: 4000) + "!"))
        assert(Date.timeIntervalSinceReferenceDate - started < 2)
        print("PASS: expensive regex matching is interrupted and remains a non-match under NOT")
    }
}

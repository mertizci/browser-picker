import Foundation

struct RuleTestResult {
    let title: String
    let detail: String
    var profile: BrowserProfile?
    var target: RouteTarget?
    var matchedRuleID: UUID?
    var isWarning = false

    var spaceDescription: String? {
        guard let profile, let target else { return nil }
        if let space = profile.space(id: target.spaceId) {
            return "Space: \(space.nestedLabel)"
        }
        if target.spaceId != nil {
            return "Saved space unavailable; uses the current space."
        }
        return profile.browser == .zen ? "Space: current space" : nil
    }
}

enum RuleTester {
    static func parseURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// A read-only preview: no discovery, persistence, picker, or browser launch.
    @MainActor
    static func test(url: URL, store: SettingsStore, sourceApp: String? = nil) -> RuleTestResult {
        if store.settings.basicMode {
            return RuleTestResult(title: "Browser picker would open", detail: "Basic mode asks you to choose a browser. Profile routing rules are paused.", isWarning: store.enabledProfiles.isEmpty)
        }
        let decision = RuleEngine().decision(
            for: RoutingContext(url: url, sourceApp: sourceApp),
            settings: store.settings,
            hasEnabledDefault: store.enabledDefaultProfile != nil
        )
        let target: RouteTarget
        let rule: RoutingRule?
        switch decision {
        case .rule(let matched):
            rule = matched
            target = matched.target
        case .defaultTarget(let fallback):
            rule = nil
            target = fallback
        case .picker:
            if store.enabledProfiles.isEmpty {
                return RuleTestResult(title: "No enabled profiles", detail: "No rule matched. The picker would ask you to enable a profile in Settings → Browsers.", isWarning: true)
            }
            return RuleTestResult(title: "Browser picker would open", detail: "No rule matched. You would choose a browser and profile in the picker.")
        }

        let reason = rule.map { "Matched rule: \($0.name)" } ?? "No rule matched. Uses your menu bar selection."
        guard let profile = store.profile(for: target) else {
            return RuleTestResult(title: "Destination unavailable", detail: "\(reason) The saved \(target.browser.displayName) profile “\(target.profileId)” was not found. Update the rule’s destination in Settings → Rules.", target: target, matchedRuleID: rule?.id, isWarning: true)
        }
        return RuleTestResult(title: "Would open in", detail: reason, profile: profile, target: target, matchedRuleID: rule?.id)
    }
}

import Foundation

enum RoutingDecision {
    case rule(RoutingRule)
    case defaultTarget(RouteTarget)
    case picker
}

struct RuleEngine {
    /// Shared by live routing and the rule tester so fallback behavior stays identical.
    func decision(for context: RoutingContext, settings: AppSettings, hasEnabledDefault: Bool) -> RoutingDecision {
        if settings.basicMode { return .picker }
        if let rule = matchingRule(for: context, in: settings) {
            return .rule(rule)
        }
        if settings.fallbackMode == .picker || !hasEnabledDefault {
            return .picker
        }
        return .defaultTarget(settings.defaultTarget)
    }

    func matchingRule(for context: RoutingContext, in settings: AppSettings) -> RoutingRule? {
        guard !settings.basicMode else { return nil }
        return settings.rules
            .filter(\.enabled)
            .filter { settings.isProfileEnabled(browser: $0.target.browser, profileID: $0.target.profileId) }
            .sorted { $0.priority < $1.priority }
            .first { $0.matches(url: context.url, sourceApp: context.sourceApp) }
    }

    func resolveTarget(
        for context: RoutingContext,
        settings: AppSettings,
        pickerChoice: RouteTarget? = nil
    ) -> RouteTarget {
        if let rule = matchingRule(for: context, in: settings) {
            return rule.target
        }
        if let pickerChoice {
            return pickerChoice
        }
        return settings.defaultTarget
    }
}

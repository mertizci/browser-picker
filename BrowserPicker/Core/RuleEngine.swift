import Foundation

enum RoutingDecision {
    /// An `.open` rule matched: send the link to its target.
    case rule(RoutingRule)
    /// An `.ask` rule matched: show the picker with the rule's choices.
    case ask(RoutingRule)
    case defaultTarget(RouteTarget)
    case picker
}

struct RuleEngine {
    /// Shared by live routing and the rule tester so fallback behavior stays identical.
    func decision(for context: RoutingContext, settings: AppSettings, hasEnabledDefault: Bool) -> RoutingDecision {
        if settings.basicMode { return .picker }
        if let rule = matchingRule(for: context, in: settings) {
            return rule.action == .ask ? .ask(rule) : .rule(rule)
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
            .filter { settings.hasEnabledDestination($0) }
            .sorted { $0.priority < $1.priority }
            .first { $0.matches(url: context.url, sourceApp: context.sourceApp) }
    }

    func resolveTarget(
        for context: RoutingContext,
        settings: AppSettings,
        pickerChoice: RouteTarget? = nil
    ) -> RouteTarget {
        if let rule = matchingRule(for: context, in: settings) {
            return rule.action == .ask ? pickerChoice ?? rule.target : rule.target
        }
        if let pickerChoice {
            return pickerChoice
        }
        return settings.defaultTarget
    }
}

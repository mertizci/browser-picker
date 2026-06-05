import Foundation

struct RuleEngine {
    func matchingRule(for context: RoutingContext, in settings: AppSettings) -> RoutingRule? {
        settings.rules
            .filter(\.enabled)
            .sorted { $0.priority < $1.priority }
            .first { $0.matcher.matches(url: context.url, sourceApp: context.sourceApp) }
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

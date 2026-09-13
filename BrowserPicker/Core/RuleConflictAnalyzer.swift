import Foundation

struct RuleConflict {
    enum Kind {
        case sameConditions
        case coveredByEarlierRule
    }

    let rule: RoutingRule
    let earlierRule: RoutingRule
    let kind: Kind

    var hasDifferentDestination: Bool { rule.target != earlierRule.target }

    var title: String {
        switch kind {
        case .sameConditions:
            return hasDifferentDestination ? "Same conditions, different destination" : "Duplicate conditions"
        case .coveredByEarlierRule:
            return "Covered by an earlier rule"
        }
    }

    var explanation: String {
        switch kind {
        case .sameConditions:
            return "“\(earlierRule.name)” has the same conditions and takes priority when it matches."
        case .coveredByEarlierRule:
            return "Every link matching this rule also matches “\(earlierRule.name)” above it. This rule will not be reached."
        }
    }
}

/// Conservative implications, not sampled URLs: report full coverage only when
/// it follows from the matchers. Different regexes and cross-field URL/path
/// relationships are deliberately not inferred.
struct RuleConflictAnalyzer {
    func conflicts(in settings: AppSettings) -> [UUID: RuleConflict] {
        guard !settings.basicMode else { return [:] }
        // Keep the same ordering and enabled-profile policy as RuleEngine.
        // A missing (but not disabled) profile still wins routing and then fails
        // to launch, so it must not be silently omitted from this analysis.
        let active = settings.rules
            .filter { $0.enabled && settings.isProfileEnabled(browser: $0.target.browser, profileID: $0.target.profileId) }
            .sorted { $0.priority < $1.priority }
            .filter { !$0.matchers.isEmpty && $0.matchers.allSatisfy(\.isValid) }

        var result: [UUID: RuleConflict] = [:]
        for (index, rule) in active.enumerated() {
            for earlier in active.prefix(index) {
                if sameConditions(rule, earlier) {
                    result[rule.id] = RuleConflict(rule: rule, earlierRule: earlier, kind: .sameConditions)
                    break
                }
                if implies(rule, earlier) {
                    result[rule.id] = RuleConflict(rule: rule, earlierRule: earlier, kind: .coveredByEarlierRule)
                    break
                }
            }
        }
        return result
    }

    /// Insert a new draft at the same position as SettingsStore.addRule, or
    /// replace an edited rule in place using its current (possibly moved) priority.
    func conflict(for draft: RoutingRule, in settings: AppSettings) -> RuleConflict? {
        var proposed = settings
        var draft = draft
        if let index = proposed.rules.firstIndex(where: { $0.id == draft.id }) {
            draft.priority = proposed.rules[index].priority
            proposed.rules[index] = draft
        } else {
            draft.priority = (proposed.rules.map(\.priority).max() ?? -1) + 1
            proposed.rules.append(draft)
        }
        return conflicts(in: proposed)[draft.id]
    }

    private func sameConditions(_ lhs: RoutingRule, _ rhs: RoutingRule) -> Bool {
        let left = Set(lhs.matchers.map(Condition.init))
        let right = Set(rhs.matchers.map(Condition.init))
        return left == right && (left.count == 1 || lhs.matchMode == rhs.matchMode)
    }

    private func implies(_ narrower: RoutingRule, _ broader: RoutingRule) -> Bool {
        let narrow = narrower.matchers.map(Condition.init)
        let broad = broader.matchers.map(Condition.init)

        // An OR rule can match via any branch, so every branch must be covered.
        // For AND, a single conjunct can be sufficient to imply an earlier
        // condition; all earlier conjuncts must still be proved independently.
        if narrower.matchMode == .any {
            return narrow.allSatisfy { condition in
                broader.matchMode == .any
                    ? broad.contains { condition.implies($0) }
                    : broad.allSatisfy { condition.implies($0) }
            }
        }
        return broader.matchMode == .any
            ? broad.contains { earlier in narrow.contains { $0.implies(earlier) } }
            : broad.allSatisfy { earlier in narrow.contains { $0.implies(earlier) } }
    }

    private struct Condition: Hashable {
        let kind: RuleMatcherKind
        let value: String
        let negated: Bool

        init(_ matcher: RuleMatcher) {
            kind = matcher.kind
            negated = matcher.isNegated
            switch kind {
            case .urlContains, .hostEquals, .sourceApplication:
                value = matcher.normalizedValue.lowercased()
            case .hostSuffix:
                value = matcher.normalizedValue.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            case .pathEquals, .pathPrefix, .pathContains, .urlRegex:
                value = matcher.normalizedValue
            }
        }

        func implies(_ broader: Condition) -> Bool {
            // Regex execution can be interrupted. Identical expressions are
            // reported as duplicate conditions, never used to prove coverage.
            guard kind != .urlRegex, broader.kind != .urlRegex,
                  negated == broader.negated else { return false }
            // NOT A implies NOT B when B implies A. Source application checks
            // only compare to the same field, retaining unknown-source behavior.
            return negated ? broader.positiveImplies(self) : positiveImplies(broader)
        }

        private func positiveImplies(_ broader: Condition) -> Bool {
            if kind == broader.kind && value == broader.value { return true }
            switch (kind, broader.kind) {
            case (.urlContains, .urlContains), (.pathContains, .pathContains),
                 (.pathEquals, .pathContains), (.pathPrefix, .pathContains):
                return value.contains(broader.value)
            case (.pathEquals, .pathPrefix), (.pathPrefix, .pathPrefix):
                return value.hasPrefix(broader.value)
            case (.hostEquals, .hostSuffix), (.hostSuffix, .hostSuffix):
                // Host suffix intentionally has literal suffix semantics in RuleMatcher.
                return value.hasSuffix(broader.value)
            default:
                return false
            }
        }
    }
}

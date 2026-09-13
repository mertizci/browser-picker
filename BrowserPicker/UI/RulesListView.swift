import SwiftUI

struct RulesListView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var ruleToDelete: RoutingRule?
    @State private var operationError: String?

    private var sortedRules: [RoutingRule] {
        settingsStore.settings.rules.sorted { $0.priority < $1.priority }
    }

    var body: some View {
        let conflicts = RuleConflictAnalyzer().conflicts(in: settingsStore.settings)
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "Rules",
                    subtitle: "Route links automatically by URL pattern. First match wins.",
                    icon: "arrow.triangle.branch",
                    action: { RuleEditorWindowController.shared.show(rule: nil, settingsStore: settingsStore) },
                    actionTitle: "Add Rule",
                    actionIcon: "plus"
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 12)

            RuleTesterView()
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

            if sortedRules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules Yet", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("Create a rule like “URL contains r2o → Firefox Work”.")
                } actions: {
                    Button("Add Rule") {
                        RuleEditorWindowController.shared.show(rule: nil, settingsStore: settingsStore)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(sortedRules.enumerated()), id: \.element.id) { index, rule in
                        RuleCardView(
                            rule: rule,
                            priority: index + 1,
                            conflict: conflicts[rule.id],
                            settingsStore: settingsStore,
                            onEdit: { RuleEditorWindowController.shared.show(rule: rule, settingsStore: settingsStore) },
                            onDelete: { ruleToDelete = rule },
                            onSetEnabled: { enabled in
                                do {
                                    try settingsStore.setRuleEnabled(enabled, id: rule.id)
                                } catch {
                                    operationError = error.localizedDescription
                                }
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 5, leading: 28, bottom: 5, trailing: 28))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Edit") {
                                RuleEditorWindowController.shared.show(rule: rule, settingsStore: settingsStore)
                            }
                            Button("Duplicate") {
                                do {
                                    try settingsStore.duplicateRule(id: rule.id)
                                } catch {
                                    operationError = error.localizedDescription
                                }
                            }
                            Button("Delete", role: .destructive) {
                                ruleToDelete = rule
                            }
                        }
                    }
                    .onMove { source, destination in
                        settingsStore.moveRules(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Couldn’t Update Rule", isPresented: Binding(
            get: { operationError != nil },
            set: { if !$0 { operationError = nil } }
        )) {
            Button("OK", role: .cancel) { operationError = nil }
        } message: {
            Text(operationError ?? "")
        }
        .confirmationDialog(
            "Delete “\(ruleToDelete?.name ?? "")”?",
            isPresented: Binding(
                get: { ruleToDelete != nil },
                set: { if !$0 { ruleToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                if let rule = ruleToDelete {
                    settingsStore.deleteRule(id: rule.id)
                }
                ruleToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                ruleToDelete = nil
            }
        } message: {
            Text("This rule will be permanently removed. This action cannot be undone.")
        }
    }
}

private struct RuleCardView: View {
    let rule: RoutingRule
    let priority: Int
    let conflict: RuleConflict?
    @ObservedObject var settingsStore: SettingsStore
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onSetEnabled: (Bool) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: onEdit) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Text("\(priority)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(rule.name)
                                .font(.body.weight(.semibold))
                            if !rule.enabled || !settingsStore.settings.isProfileEnabled(browser: rule.target.browser, profileID: rule.target.profileId) {
                                Text(rule.enabled ? "Profile disabled" : "Disabled")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            if rule.matchers.count > 1 {
                                Text(rule.matchMode == .any ? "Matches any condition" : "Matches all conditions")
                                    .font(.caption2.weight(.medium))
                            }
                            ForEach(Array(rule.matchers.prefix(2).enumerated()), id: \.offset) { _, matcher in
                                Label(matcher.summary, systemImage: matcherIcon(for: matcher.kind))
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            if rule.matchers.count > 2 {
                                Text("+\(rule.matchers.count - 2) more conditions")
                                    .font(.caption2)
                            }
                        }
                        .foregroundStyle(.secondary)
                        .help(rule.matchers.map(\.summary).joined(separator: "\n\(rule.matchMode.conjunction) "))

                        destinationRow

                        if let conflict {
                            RuleConflictNotice(
                                conflict: conflict,
                                earlierDestination: settingsStore.profile(for: conflict.earlierRule.target)?.routeLabel(spaceId: conflict.earlierRule.target.spaceId)
                                    ?? "\(conflict.earlierRule.target.browser.displayName) · \(conflict.earlierRule.target.profileId)",
                                compact: true
                            )
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("Enabled", isOn: Binding(get: { rule.enabled }, set: onSetEnabled))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel("Enable rule \(rule.name)")
                .help(rule.enabled ? "Disable rule" : "Enable rule")

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(width: 28, height: 28)
                        .background(Color.red.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Delete rule")
            }

            Image(systemName: "line.3.horizontal")
                .font(.body)
                .foregroundStyle(.tertiary)
                .frame(width: 24, height: 28)
                .contentShape(Rectangle())
                .help("Drag to reorder")
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.07), lineWidth: 1)
        }
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var destinationRow: some View {
        if let profile = settingsStore.profile(for: rule.target) {
            HStack(spacing: 8) {
                ProfileIconView(profile: profile, size: 18)
                Text(profile.routeLabel(spaceId: rule.target.spaceId))
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: Capsule())
        } else {
            Label {
                Text("\(rule.target.browser.displayName) · \(rule.target.profileId)")
                    .font(.caption)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        }
    }

    private func matcherIcon(for kind: RuleMatcherKind) -> String {
        switch kind {
        case .urlContains: return "text.magnifyingglass"
        case .hostEquals: return "equal"
        case .hostSuffix: return "globe"
        case .pathEquals, .pathPrefix, .pathContains: return "folder"
        case .urlRegex: return "asterisk"
        case .sourceApplication: return "app"
        }
    }
}

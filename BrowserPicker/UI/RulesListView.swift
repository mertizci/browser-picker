import SwiftUI

private enum RuleEditorContext: Identifiable {
    case create
    case edit(RoutingRule)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let rule): return rule.id.uuidString
        }
    }

    var existingRule: RoutingRule? {
        if case .edit(let rule) = self { return rule }
        return nil
    }
}

struct RulesListView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var editorContext: RuleEditorContext?
    @State private var ruleToDelete: RoutingRule?

    private var sortedRules: [RoutingRule] {
        settingsStore.settings.rules.sorted { $0.priority < $1.priority }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(
                    title: "Rules",
                    subtitle: "Route links automatically by URL pattern. First match wins.",
                    icon: "arrow.triangle.branch",
                    action: { editorContext = .create },
                    actionTitle: "Add Rule",
                    actionIcon: "plus"
                )
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 12)

            if sortedRules.isEmpty {
                ContentUnavailableView {
                    Label("No Rules Yet", systemImage: "arrow.triangle.branch")
                } description: {
                    Text("Create a rule like “URL contains r2o → Firefox Work”.")
                } actions: {
                    Button("Add Rule") {
                        editorContext = .create
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
                            settingsStore: settingsStore,
                            onEdit: { editorContext = .edit(rule) },
                            onDelete: { ruleToDelete = rule }
                        )
                        .listRowInsets(EdgeInsets(top: 5, leading: 28, bottom: 5, trailing: 28))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Edit") {
                                editorContext = .edit(rule)
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
        .sheet(item: $editorContext) { context in
            RuleEditorView(rule: context.existingRule) { saved in
                switch context {
                case .create:
                    settingsStore.addRule(saved)
                case .edit:
                    settingsStore.updateRule(saved)
                }
            }
            .environmentObject(settingsStore)
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
    let settingsStore: SettingsStore
    let onEdit: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
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
                    if !rule.enabled {
                        Text("Disabled")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: matcherIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(rule.matcher.kind.displayName): \(rule.matcher.value)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                destinationRow
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 20)
                    .help("Drag to reorder")
            }
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
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture(perform: onEdit)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var destinationRow: some View {
        if let profile = settingsStore.profile(for: rule.target) {
            HStack(spacing: 8) {
                ProfileIconView(profile: profile, size: 18)
                Text("\(profile.browser.displayName) · \(profile.displayName)")
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

    private var matcherIcon: String {
        switch rule.matcher.kind {
        case .urlContains: return "text.magnifyingglass"
        case .hostEquals: return "equal"
        case .hostSuffix: return "globe"
        }
    }
}

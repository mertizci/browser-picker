import SwiftUI

struct RuleEditorView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var enabled: Bool
    @State private var matcherKind: RuleMatcherKind
    @State private var matcherValue: String
    @State private var selectedBrowser: BrowserKind
    @State private var selectedProfileId: String
    @State private var showDeleteConfirmation = false

    private let existingID: UUID?
    private let existingPriority: Int?
    private let onSave: (RoutingRule) -> Void

    init(rule: RoutingRule?, onSave: @escaping (RoutingRule) -> Void) {
        existingID = rule?.id
        existingPriority = rule?.priority
        _name = State(initialValue: rule?.name ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
        _matcherKind = State(initialValue: rule?.matcher.kind ?? .urlContains)
        _matcherValue = State(initialValue: rule?.matcher.value ?? "")
        _selectedBrowser = State(initialValue: rule?.target.browser ?? .firefox)
        _selectedProfileId = State(initialValue: rule?.target.profileId ?? "")
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: existingID == nil ? "plus.circle.fill" : "pencil.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(existingID == nil ? "Add Rule" : "Edit Rule")
                        .font(.title2.weight(.bold))
                    Text("Define when this rule matches and where links open.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rulePreview

                    editorSection(title: "Name", subtitle: "A clear label for this rule.", icon: "tag") {
                        TextField("e.g. Work links → Firefox", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    editorSection(title: "Match", subtitle: "Choose how incoming URLs are matched.", icon: "text.magnifyingglass") {
                        Picker("Match type", selection: $matcherKind) {
                            ForEach(RuleMatcherKind.allCases) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        TextField(matcherPlaceholder, text: $matcherValue)
                            .textFieldStyle(.roundedBorder)
                    }

                    editorSection(title: "Open in", subtitle: "Pick the browser and profile for matched links.", icon: "arrow.up.forward.app") {
                        Picker("Browser", selection: $selectedBrowser) {
                            ForEach(BrowserKind.allCases) { browser in
                                Text(browser.displayName).tag(browser)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: selectedBrowser) { _, newValue in
                            resolveProfileSelection(for: newValue)
                        }

                        let profiles = settingsStore.profiles(for: selectedBrowser)
                        if profiles.isEmpty {
                            Label("No profiles found for this browser.", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.vertical, 4)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(profiles) { profile in
                                    ProfilePickerRow(
                                        profile: profile,
                                        isSelected: selectedProfileId == profile.id,
                                        action: { selectedProfileId = profile.id }
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                if existingID != nil {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Rule") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 500, height: 600)
        .onAppear {
            resolveProfileSelection()
        }
        .confirmationDialog(
            "Delete “\(name)”?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                if let existingID {
                    settingsStore.deleteRule(id: existingID)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This rule will be permanently removed. This action cannot be undone.")
        }
    }

    @ViewBuilder
    private var rulePreview: some View {
        let trimmedValue = matcherValue.trimmingCharacters(in: .whitespaces)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHEN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(trimmedValue.isEmpty ? "…" : "\(matcherKind.displayName) “\(trimmedValue)”")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text("OPEN IN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                if let profile = settingsStore.profiles(for: selectedBrowser).first(where: { $0.id == selectedProfileId }) {
                    HStack(spacing: 6) {
                        ProfileIconView(profile: profile, size: 16)
                        Text("\(profile.browser.displayName) · \(profile.displayName)")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                } else {
                    Text("\(selectedBrowser.displayName) · …")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 1)
        )
    }

    private func editorSection<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func resolveProfileSelection() {
        let available = settingsStore.profiles(for: selectedBrowser)
        if available.contains(where: { $0.id == selectedProfileId }) {
            return
        }

        if let match = available.first(where: {
            $0.displayName == selectedProfileId
                || $0.internalName == selectedProfileId
                || (selectedProfileId == "safari-default" && $0.id == SafariProfileRecord.defaultID)
        }) {
            selectedProfileId = match.id
            return
        }

        if let first = available.first {
            selectedProfileId = first.id
        } else {
            selectedProfileId = ""
        }
    }

    private var matcherPlaceholder: String {
        switch matcherKind {
        case .urlContains: return "e.g. r2o"
        case .hostEquals: return "e.g. github.com"
        case .hostSuffix: return "e.g. .company.com"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !matcherValue.trimmingCharacters(in: .whitespaces).isEmpty
            && !selectedProfileId.isEmpty
    }

    private func resolveProfileSelection(for browser: BrowserKind? = nil) {
        let browserKind = browser ?? selectedBrowser
        let available = settingsStore.profiles(for: browserKind)

        if available.contains(where: { $0.id == selectedProfileId }) {
            return
        }

        if let match = available.first(where: {
            $0.displayName == selectedProfileId
                || $0.internalName == selectedProfileId
                || (selectedProfileId == "safari-default" && $0.id == SafariProfileRecord.defaultID)
        }) {
            selectedProfileId = match.id
            return
        }

        if let first = available.first {
            selectedProfileId = first.id
        } else {
            selectedProfileId = ""
        }
    }

    private func save() {
        let rule = RoutingRule(
            id: existingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            enabled: enabled,
            priority: existingPriority ?? 0,
            matcher: RuleMatcher(kind: matcherKind, value: matcherValue.trimmingCharacters(in: .whitespaces)),
            target: RouteTarget(browser: selectedBrowser, profileId: selectedProfileId)
        )
        onSave(rule)
        dismiss()
    }
}

private struct ProfilePickerRow: View {
    let profile: BrowserProfile
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProfileIconView(profile: profile, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.body.weight(.medium))
                    Text(profile.browser.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.03))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

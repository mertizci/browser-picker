import SwiftUI

struct RuleEditorView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    @State private var name: String
    @State private var enabled: Bool
    @State private var conditions: [EditableRuleCondition]
    @State private var matchMode: RuleMatchMode
    @State private var action: RuleAction
    @State private var selectedBrowser: BrowserKind
    @State private var selectedProfileId: String
    @State private var selectedSpaceId: String?
    /// What an ask rule offers. Kept while switching to "Open in profile" and
    /// back, like the open destination is kept the other way round.
    @State private var selectedChoices: Set<RouteTarget>
    @State private var showDeleteConfirmation = false
    @State private var draftID: UUID

    private let existingID: UUID?
    private let existingPriority: Int?
    /// The saved order of the choices, for those the list cannot show.
    private let existingChoices: [RouteTarget]
    private let onSave: (RoutingRule) -> Void
    private let onClose: () -> Void

    /// An ask rule with a single choice would never need to ask.
    private static let minimumChoices = 2

    init(rule: RoutingRule?, onClose: @escaping () -> Void, onSave: @escaping (RoutingRule) -> Void) {
        self.onClose = onClose
        existingID = rule?.id
        existingPriority = rule?.priority
        existingChoices = rule?.choices ?? []
        _draftID = State(initialValue: rule?.id ?? UUID())
        _name = State(initialValue: rule?.name ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
        _matchMode = State(initialValue: rule?.matchMode ?? .any)
        _action = State(initialValue: rule?.action ?? .open)
        _selectedChoices = State(initialValue: Set(rule?.choices ?? []))
        let matchers = rule?.matchers ?? []
        _conditions = State(initialValue: (matchers.isEmpty ? [RuleMatcher(kind: .urlContains, value: "")] : matchers)
            .map { EditableRuleCondition(matcher: $0) })
        _selectedBrowser = State(initialValue: rule?.target.browser ?? .firefox)
        _selectedProfileId = State(initialValue: rule?.target.profileId ?? "")
        _selectedSpaceId = State(initialValue: rule?.target.spaceId)
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

            GeometryReader { viewport in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        rulePreview

                        if let conflict = draftConflict {
                            RuleConflictNotice(
                                conflict: conflict,
                                earlierDestination: settingsStore.destinationLabel(for: conflict.earlierRule)
                            )
                            .padding(14)
                            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }

                        editorSection(title: "Name", subtitle: "A clear label for this rule.", icon: "tag") {
                            TextField("e.g. Work links → Firefox", text: $name)
                                .textFieldStyle(.roundedBorder)
                        }

                        editorSection(title: "Match conditions", subtitle: matchMode.explanation, icon: "text.magnifyingglass") {
                            Button {
                                HelpWindowController.ruleMatching.show()
                            } label: {
                                Label("Matching help", systemImage: "questionmark.circle")
                            }
                            .buttonStyle(.link)

                            Picker("Match mode", selection: $matchMode) {
                                ForEach(RuleMatchMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            ForEach($conditions) { $condition in
                                if condition.id != conditions.first?.id {
                                    Text(matchMode.conjunction)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                MatchConditionRow(
                                    matcher: $condition.matcher,
                                    number: (conditions.firstIndex { $0.id == condition.id } ?? 0) + 1,
                                    canRemove: conditions.count > 1,
                                    onRemove: { conditions.removeAll { $0.id == condition.id } }
                                )
                            }

                            Button {
                                conditions.append(EditableRuleCondition(matcher: RuleMatcher(kind: .urlContains, value: "")))
                            } label: {
                                Label("Add Condition", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }

                        editorSection(title: "Then", subtitle: actionSubtitle, icon: action == .ask ? "questionmark.app" : "arrow.up.forward.app") {
                            Picker("Action", selection: $action) {
                                ForEach(RuleAction.allCases) { action in
                                    Text(action.displayName).tag(action)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()

                            switch action {
                            case .open: openDestinationPicker
                            case .ask: askChoicesPicker
                            }
                        }
                    }
                    // Native controls must stay within the viewport, even if their
                    // intrinsic width changes on a new macOS release.
                    .frame(width: max(0, viewport.size.width - 48), alignment: .leading)
                    .padding(24)
                }
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
                Button("Cancel", action: onClose)
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
        .frame(minWidth: 480, idealWidth: 620, maxWidth: .infinity,
               minHeight: 380, idealHeight: 680, maxHeight: .infinity)
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
                onClose()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This rule will be permanently removed. This action cannot be undone.")
        }
    }

    private var actionSubtitle: String {
        switch action {
        case .open: return "Pick the browser, profile and space for matched links."
        case .ask: return "Matched links show a prompt with the profiles you tick."
        }
    }

    @ViewBuilder
    private var openDestinationPicker: some View {
        Picker("Browser", selection: $selectedBrowser) {
            ForEach(BrowserKind.allCases) { browser in
                Text(browser.displayName).tag(browser)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedBrowser) { _, newValue in
            resolveProfileSelection(for: newValue)
        }

        if let profile = selectedProfile, !settingsStore.isProfileEnabled(profile) {
            Label("This rule’s profile is disabled. Choose an enabled profile or re-enable it in Browsers.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        let profiles = settingsStore.enabledProfiles(for: selectedBrowser)
        if profiles.isEmpty {
            Label("No enabled profiles for this browser. Enable one in Settings → Browsers.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.vertical, 4)
        } else {
            destinationList(RouteDestinationGroup.all(in: profiles), multiSelect: false,
                            isSelected: { $0 == selectedTarget }) { destination in
                selectedProfileId = destination.profile.id
                selectedSpaceId = destination.space?.id
            }
        }
    }

    /// Every enabled destination across browsers, since one prompt can offer
    /// profiles of different browsers.
    @ViewBuilder
    private var askChoicesPicker: some View {
        let groups = RouteDestinationGroup.all(in: settingsStore.enabledProfiles)
        if groups.isEmpty {
            Label("No enabled profiles. Enable some in Settings → Browsers.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.vertical, 4)
        } else {
            destinationList(groups, multiSelect: true,
                            isSelected: { selectedChoices.contains($0) }) { destination in
                if selectedChoices.remove(destination.target) == nil {
                    selectedChoices.insert(destination.target)
                }
            }
        }

        let unlisted = unlistedChoices
        if !unlisted.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("Also offers \(unlisted.count == 1 ? "a profile that is" : "\(unlisted.count) profiles that are") disabled or no longer found. The prompt skips \(unlisted.count == 1 ? "it" : "them").",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(unlisted.map { settingsStore.destinationLabel(for: $0) }.joined(separator: "\n"))
                Spacer(minLength: 0)
                Button("Remove") { selectedChoices.subtract(unlisted) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }

        if listedChoices.count < Self.minimumChoices {
            Text("Choose at least two profiles to ask between.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func destinationList(
        _ groups: [RouteDestinationGroup],
        multiSelect: Bool,
        isSelected: @escaping (RouteTarget) -> Bool,
        onSelect: @escaping (RouteDestination) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = group.title {
                        Text(title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(group.destinations) { destination in
                        DestinationPickerRow(
                            destination: destination,
                            isSelected: isSelected(destination.target),
                            multiSelect: multiSelect,
                            action: { onSelect(destination) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var rulePreview: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("WHEN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(conditionSummary)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 4) {
                Text(action == .ask ? "ASK BETWEEN" : "OPEN IN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                if action == .ask {
                    let choices = listedChoices
                    Text(choices.isEmpty ? "Choose profiles…" : choices.map { settingsStore.destinationLabel(for: $0) }.joined(separator: " or "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(choices.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                } else if let profile = selectedProfile {
                    HStack(spacing: 6) {
                        ProfileIconView(profile: profile, size: 16)
                        Text(profile.routeLabel(spaceId: selectedSpaceId))
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

    private var selectedProfile: BrowserProfile? {
        settingsStore.profiles(for: selectedBrowser).first { $0.id == selectedProfileId }
    }

    private var selectedTarget: RouteTarget {
        RouteTarget(browser: selectedBrowser, profileId: selectedProfileId, spaceId: selectedSpaceId)
    }

    private var conditionSummary: String {
        if conditions.count > 1 {
            return matchMode == .any ? "Any of \(conditions.count) conditions" : "All \(conditions.count) conditions"
        }
        guard let matcher = conditions.first?.matcher, matcher.isValid else { return "…" }
        return matcher.summary
    }

    /// Ticked choices the editor lists, in the order the prompt shows them.
    private var listedChoices: [RouteTarget] {
        RouteDestinationGroup.all(in: settingsStore.enabledProfiles)
            .flatMap(\.destinations)
            .map(\.target)
            .filter { selectedChoices.contains($0) }
    }

    /// Saved choices the list cannot show, because their profile is disabled
    /// or no longer discovered. They are kept, like an open rule's target is.
    private var unlistedChoices: [RouteTarget] {
        let listed = Set(listedChoices)
        return existingChoices.filter { selectedChoices.contains($0) && !listed.contains($0) }
    }

    private var hasValidDestination: Bool {
        switch action {
        case .open: return selectedProfile.map { settingsStore.isProfileEnabled($0) } == true
        case .ask: return listedChoices.count >= Self.minimumChoices
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !conditions.isEmpty && conditions.allSatisfy { $0.matcher.isValid }
            && hasValidDestination
    }

    /// The rule as it would be saved.
    private var draftRule: RoutingRule {
        let choices = action == .ask ? listedChoices + unlistedChoices : []
        return RoutingRule(
            id: draftID,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            enabled: enabled,
            priority: existingPriority ?? 0,
            matchers: conditions.map {
                RuleMatcher(kind: $0.matcher.kind, value: $0.matcher.normalizedValue, isNegated: $0.matcher.isNegated,
                            applicationName: $0.matcher.applicationName)
            },
            matchMode: matchMode,
            action: action,
            // An ask rule keeps its first choice as target for older versions.
            target: choices.first ?? selectedTarget,
            choices: choices
        )
    }

    private var draftConflict: RuleConflict? {
        // Incomplete conditions are not diagnosed while the user is typing.
        switch action {
        case .open: guard !selectedProfileId.isEmpty else { return nil }
        case .ask: guard !selectedChoices.isEmpty else { return nil }
        }
        return RuleConflictAnalyzer().conflict(for: draftRule, in: settingsStore.settings)
    }

    private func resolveProfileSelection(for browser: BrowserKind? = nil) {
        let available = settingsStore.profiles(for: browser ?? selectedBrowser)
        defer { discardSpaceUnlessAvailable(in: available) }

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

        selectedProfileId = available.first(where: { settingsStore.isProfileEnabled($0) })?.id ?? ""
    }

    /// A space belongs to one profile, so it cannot survive a change of profile.
    private func discardSpaceUnlessAvailable(in profiles: [BrowserProfile]) {
        let profile = profiles.first { $0.id == selectedProfileId }
        if profile?.space(id: selectedSpaceId) == nil {
            selectedSpaceId = nil
        }
    }

    private func save() {
        guard canSave else { return }
        onSave(draftRule)
        onClose()
    }
}

private struct EditableRuleCondition: Identifiable {
    let id = UUID()
    var matcher: RuleMatcher
}

private struct MatchConditionRow: View {
    @Binding var matcher: RuleMatcher
    let number: Int
    let canRemove: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Condition \(number) match type", selection: $matcher.kind) {
                    ForEach(RuleMatcherKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

                .onChange(of: matcher.kind) { old, new in
                    if old == .sourceApplication || new == .sourceApplication {
                        matcher.value = ""
                        matcher.applicationName = nil
                    }
                }

                Toggle("NOT", isOn: $matcher.isNegated)
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .help("Invert this condition: match links that do not satisfy it.")
                    .accessibilityLabel("Negate condition \(number)")

                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(!canRemove)
                .help("Remove condition")
                .accessibilityLabel("Remove condition \(number)")
            }
            if matcher.kind == .sourceApplication {
                SourceApplicationPicker(bundleIdentifier: $matcher.value, savedName: matcher.applicationName) { app in
                    matcher.applicationName = app.name
                }
            } else {
                TextField(placeholder, text: $matcher.value)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Condition \(number) value")
            }
            if !matcher.value.isEmpty, let message = matcher.validationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var placeholder: String {
        switch matcher.kind {
        case .urlContains: return "e.g. r2o"
        case .hostEquals: return "e.g. github.com"
        case .hostSuffix: return "e.g. .company.com"
        case .pathEquals: return "e.g. /dashboard"
        case .pathPrefix: return "e.g. /work/"
        case .pathContains: return "e.g. /invoices/"
        case .urlRegex: return #"e.g. ^https://example\.com/work/"#
        case .sourceApplication: return "Choose Application…"
        }
    }
}

private struct DestinationPickerRow: View {
    let destination: RouteDestination
    let isSelected: Bool
    /// Checkboxes for picking several destinations, radio circles for one.
    var multiSelect = false
    let action: () -> Void

    private var indicator: String {
        switch (multiSelect, isSelected) {
        case (true, true): return "checkmark.square.fill"
        case (true, false): return "square"
        case (false, true): return "checkmark.circle.fill"
        case (false, false): return "circle"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ProfileIconView(profile: destination.profile, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.body.weight(.medium))
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: indicator)
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

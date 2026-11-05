import SwiftUI

struct PickerPromptView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var urlRouter: URLRouter
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTarget: RouteTarget?

    var body: some View {
        Group {
            if let request = urlRouter.pendingPicker {
                promptContent(for: request)
            } else {
                ContentUnavailableView(
                    "No Link",
                    systemImage: "link",
                    description: Text("Waiting for a link to open.")
                )
            }
        }
        .onChange(of: urlRouter.pendingPicker) { _, newValue in
            if newValue == nil {
                dismiss()
            }
        }
        .onAppear {
            selectedTarget = settingsStore.settings.defaultTarget
            bringWindowToFront()
        }
    }

    /// Show at most this many rows before the list starts scrolling.
    private let maxVisibleRows = 5

    @ViewBuilder
    private func promptContent(for request: PickerRequest) -> some View {
        let offered = offeredGroups(for: request)
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Link In")
                    .font(.title2.bold())
                Text(request.url.host ?? request.url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let rule = request.rule {
                    Label("Rule: \(rule.name)", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if offered.isEmpty {
                        Label("None of this rule’s profiles are available.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            profileList(for: request.url, groups: offered.isEmpty ? allGroups : offered)

            HStack {
                Button("Cancel") {
                    urlRouter.cancelPicker()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var allGroups: [RouteDestinationGroup] {
        RouteDestinationGroup.all(in: settingsStore.enabledProfiles)
    }

    /// An ask rule offers only its own choices; the plain picker offers all.
    /// Empty when none of an ask rule's choices is available.
    private func offeredGroups(for request: PickerRequest) -> [RouteDestinationGroup] {
        guard let rule = request.rule else { return allGroups }
        return RouteDestinationGroup.all(in: settingsStore.enabledProfiles, offering: rule.choices)
    }

    /// Grows with the number of destinations, only scrolling once the list would
    /// exceed `maxVisibleRows` — so a couple of profiles don't leave dead space.
    @ViewBuilder
    private func profileList(for url: URL, groups: [RouteDestinationGroup]) -> some View {
        let shortcuts = shortcutNumbers(for: groups)
        let rows = VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = group.title {
                        Text(title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(group.destinations) { destination in
                        destinationRow(destination, url: url, shortcut: shortcuts[destination.target])
                    }
                }
            }
        }

        if groups.isEmpty {
            ContentUnavailableView {
                Label(settingsStore.settings.basicMode ? "No Enabled Browsers" : "No Enabled Profiles", systemImage: "globe")
            } description: {
                Text(settingsStore.settings.basicMode ? "Enable a browser in Settings → Browsers to open this link." : "Enable a profile in Settings → Browsers to open this link.")
            } actions: {
                Button("Open Settings") {
                    SettingsWindowController.shared.show(settingsStore: settingsStore, appState: .shared)
                }
                .buttonStyle(.borderedProminent)
            }
        } else if rowCount(of: groups) > maxVisibleRows {
            ScrollView { rows }
                .frame(height: estimatedRowHeight * CGFloat(maxVisibleRows))
        } else {
            rows
        }
    }

    /// Number keys 1–9 pick the first nine destinations, in the order shown.
    private func shortcutNumbers(for groups: [RouteDestinationGroup]) -> [RouteTarget: Int] {
        let targets = groups.flatMap(\.destinations).prefix(9).map(\.target)
        return Dictionary(targets.enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    /// Group headings take room of their own, so they count towards the height
    /// the list is allowed before it starts scrolling.
    private func rowCount(of groups: [RouteDestinationGroup]) -> Int {
        groups.reduce(0) { total, group in
            total + group.destinations.count + (group.title == nil ? 0 : 1)
        }
    }

    private var estimatedRowHeight: CGFloat { 56 }

    @ViewBuilder
    private func destinationRow(_ destination: RouteDestination, url: URL, shortcut: Int?) -> some View {
        let button = Button {
            selectedTarget = destination.target
            urlRouter.completePickerSelection(url: url, target: destination.target)
        } label: {
            HStack(spacing: 12) {
                ProfileIconView(profile: destination.profile, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.title)
                        .font(.headline)
                    if let subtitle = destination.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if selectedTarget == destination.target {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                if let shortcut {
                    Text("\(shortcut)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
                        .help("Press \(shortcut) to open here")
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)

        if let shortcut {
            button.keyboardShortcut(KeyEquivalent(Character("\(shortcut)")), modifiers: [])
        } else {
            button
        }
    }

    private func bringWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

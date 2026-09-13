import SwiftUI

struct PickerPromptView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var urlRouter: URLRouter
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTarget: RouteTarget?

    private var url: URL? { urlRouter.pendingPickerURL }

    var body: some View {
        Group {
            if let url {
                promptContent(for: url)
            } else {
                ContentUnavailableView(
                    "No Link",
                    systemImage: "link",
                    description: Text("Waiting for a link to open.")
                )
            }
        }
        .onChange(of: urlRouter.pendingPickerURL) { _, newValue in
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
    private func promptContent(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Link In")
                    .font(.title2.bold())
                Text(url.host ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            profileList(for: url)

            HStack {
                Button("Cancel") {
                    urlRouter.cancelPicker()
                    dismiss()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    /// Grows with the number of destinations, only scrolling once the list would
    /// exceed `maxVisibleRows` — so a couple of profiles don't leave dead space.
    @ViewBuilder
    private func profileList(for url: URL) -> some View {
        let groups = RouteDestinationGroup.all(in: settingsStore.enabledProfiles)
        let rows = VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    if let title = group.title {
                        Text(title.uppercased())
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(group.destinations) { destination in
                        destinationRow(destination, url: url)
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

    /// Group headings take room of their own, so they count towards the height
    /// the list is allowed before it starts scrolling.
    private func rowCount(of groups: [RouteDestinationGroup]) -> Int {
        groups.reduce(0) { total, group in
            total + group.destinations.count + (group.title == nil ? 0 : 1)
        }
    }

    private var estimatedRowHeight: CGFloat { 56 }

    @ViewBuilder
    private func destinationRow(_ destination: RouteDestination, url: URL) -> some View {
        Button {
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
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func bringWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

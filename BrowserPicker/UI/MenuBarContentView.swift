import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissions: PermissionMonitor
    @EnvironmentObject private var updateController: UpdateController
    @Environment(\.dismiss) private var dismiss

    private var activeProfile: BrowserProfile? {
        settingsStore.enabledDefaultProfile
    }

    private var activeSpace: BrowserSpace? {
        activeProfile?.space(id: settingsStore.settings.defaultTarget.spaceId)
    }

    /// The active profile, or — once a space is targeted — that space under its
    /// container, the way the menus below nest them.
    private var activeProfileLabel: String? {
        guard let activeProfile else { return nil }
        guard let activeSpace else { return activeProfile.displayName }
        return activeSpace.nestedLabel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()
                .padding(.horizontal, 12)

            if permissions.isOnboardingActive {
                onboardingNotice
                    .padding(12)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    sectionLabel("Switch Profile")
                    profileMenus
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

                Divider()
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 2) {
                    actionRows
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()
                .padding(.horizontal, 12)

            VStack(spacing: 2) {
                MenuRow(title: "Quit Browser Picker", systemImage: "power", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .frame(width: 268)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Group {
                if let activeProfile {
                    ProfileIconView(profile: activeProfile, size: 30)
                } else {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activeProfileLabel ?? "Browser Picker")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(activeProfile.map { "\($0.browser.displayName) · active" } ?? "No profile selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var onboardingNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Finish setup")
                    .font(.subheadline.weight(.medium))
                Text("Grant permissions to continue.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Open") {
                dismiss()
                PermissionsOnboardingWindowController.shared.showIfNeeded()
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var profileMenus: some View {
        if settingsStore.enabledProfiles.isEmpty {
            Text("No enabled profiles. Enable a profile in Settings → Browsers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        ForEach(BrowserKind.allCases) { browser in
            let profiles = settingsStore.enabledProfiles(for: browser)
            if !profiles.isEmpty {
                let groups = RouteDestinationGroup.all(in: profiles)
                Menu {
                    ForEach(groups) { group in
                        if let title = group.title {
                            Menu(title) {
                                ForEach(group.destinations) { destinationButton($0) }
                            }
                        } else {
                            ForEach(group.destinations) { destinationButton($0) }
                            if groups.count > 1 {
                                Divider()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        BrowserIconView(browser: browser, size: 18)
                        Text(browser.displayName)
                            .font(.system(size: 13))
                        Spacer(minLength: 0)
                        if activeProfile?.browser == browser {
                            Text(activeProfileLabel ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.visible)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
        }
    }

    private func destinationButton(_ destination: RouteDestination) -> some View {
        Button {
            settingsStore.setDefaultTarget(destination.target)
            dismiss()
        } label: {
            if settingsStore.settings.defaultTarget == destination.target {
                Label(destination.title, systemImage: "checkmark")
            } else {
                Text(destination.title)
            }
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        if appState.isDefaultBrowser {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .frame(width: 18)
                Text("Default browser")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        } else {
            MenuRow(title: "Set as Default Browser…", systemImage: "star") {
                appState.registerAsDefaultBrowser()
                dismiss()
            }
        }

        MenuRow(title: "Refresh Profiles", systemImage: "arrow.clockwise") {
            settingsStore.reloadProfiles()
            dismiss()
        }

        MenuRow(title: "Settings…", systemImage: "gearshape") {
            dismiss()
            SettingsWindowController.shared.show(
                settingsStore: settingsStore,
                appState: appState
            )
        }

        MenuRow(title: "Check for Updates…", systemImage: "arrow.down.circle") {
            dismiss()
            updateController.checkForUpdates(silent: false)
        }

        MenuRow(title: "FAQ", systemImage: "questionmark.circle") {
            dismiss()
            FAQWindowController.shared.show()
        }

        MenuRow(title: "About", systemImage: "info.circle") {
            dismiss()
            AboutWindowController.shared.show()
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 1)
    }

}

private struct MenuRow: View {
    let title: String
    var systemImage: String
    var role: ButtonRole?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(role == .destructive ? Color.red : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

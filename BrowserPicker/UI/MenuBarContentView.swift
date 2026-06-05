import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var permissions: PermissionMonitor
    @EnvironmentObject private var updateController: UpdateController
    @Environment(\.dismiss) private var dismiss

    private var activeProfile: BrowserProfile? {
        settingsStore.profile(for: settingsStore.settings.defaultTarget)
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
                Text(activeProfile?.displayName ?? "Browser Picker")
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
        ForEach(BrowserKind.allCases) { browser in
            let profiles = settingsStore.profiles(for: browser)
            if !profiles.isEmpty {
                Menu {
                    ForEach(profiles) { profile in
                        Button {
                            settingsStore.setDefaultTarget(
                                RouteTarget(browser: profile.browser, profileId: profile.id)
                            )
                            dismiss()
                        } label: {
                            if isSelected(profile) {
                                Label(profile.displayName, systemImage: "checkmark")
                            } else {
                                Text(profile.displayName)
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
                            Text(activeProfile?.displayName ?? "")
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

    private func isSelected(_ profile: BrowserProfile) -> Bool {
        let target = settingsStore.settings.defaultTarget
        return target.browser == profile.browser && target.profileId == profile.id
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

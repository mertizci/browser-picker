import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 232)

            Divider()

            Group {
                switch selection {
                case .general:
                    GeneralSettingsTab()
                case .rules:
                    RulesListView()
                case .browsers:
                    BrowsersSettingsTab()
                }
            }
            .environmentObject(settingsStore)
            .environmentObject(appState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section,
                        action: { selection = section }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 0)

            sidebarFooter
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text("Browser Picker")
                    .font(.headline)
                Text("v\(appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.isDefaultBrowser ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(appState.isDefaultBrowser ? "Default browser" : "Not default")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

private struct SidebarRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(section.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(section.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.primary.opacity(0.07) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsDetailScaffold(title: "General", subtitle: "Control how Browser Picker handles links.", icon: "gearshape.fill") {
            if appState.isDefaultBrowser {
                StatusBanner(
                    style: .success,
                    title: "Default browser active",
                    message: "Links from other apps are routed through Browser Picker."
                )
            } else {
                StatusBanner(
                    style: .warning,
                    title: "Not the default browser",
                    message: "Set Browser Picker as default to intercept links system-wide.",
                    actionTitle: "Make Default",
                    action: appState.registerAsDefaultBrowser
                )
            }

            SettingsCard(
                title: "When no rule matches",
                subtitle: "Choose what happens for links that don't match any rule."
            ) {
                VStack(spacing: 8) {
                    SettingsOptionRow(
                        title: "Use menu bar selection",
                        subtitle: "Open links silently in your current menu bar choice.",
                        systemImage: "menubar.rectangle",
                        isSelected: settingsStore.settings.fallbackMode == .silent,
                        action: { settingsStore.setFallbackMode(.silent) }
                    )
                    SettingsOptionRow(
                        title: "Show picker",
                        subtitle: "Ask which browser and profile to use each time.",
                        systemImage: "list.bullet.rectangle.portrait",
                        isSelected: settingsStore.settings.fallbackMode == .picker,
                        action: { settingsStore.setFallbackMode(.picker) }
                    )
                }
            }

            SettingsCard(
                title: "Menu bar selection",
                subtitle: "This browser and profile are used when no rule matches and fallback is silent."
            ) {
                if let profile = settingsStore.enabledDefaultProfile {
                    ProfileSummaryRow(
                        profile: profile,
                        spaceId: settingsStore.settings.defaultTarget.spaceId
                    )
                    .padding(.horizontal, 4)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(.secondary)
                        Text("Enable a profile in Browsers to select a default.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingsCard(
                title: "Quick tip",
                subtitle: nil
            ) {
                Label {
                    Text("Change the active profile from the menu bar icon anytime.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(.yellow)
                }
            }
        }
    }
}

private struct BrowsersSettingsTab: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var permissions: PermissionMonitor

    var body: some View {
        SettingsDetailScaffold(
            title: "Browsers",
            subtitle: "Choose which browser profiles can open links.",
            icon: "globe",
            action: {
                settingsStore.reloadProfiles()
                permissions.refresh()
            },
            actionTitle: "Refresh",
            actionIcon: "arrow.clockwise"
        ) {
            Text("Disabled profiles are hidden from the picker and menu bar. Rules targeting them are skipped until you re-enable the profile.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if settingsStore.profiles.isEmpty {
                ContentUnavailableView {
                    Label("No Browsers Found", systemImage: "globe")
                } description: {
                    Text("Install Chrome, Firefox, or Safari, then refresh profiles.")
                } actions: {
                    Button("Refresh Profiles") {
                        settingsStore.reloadProfiles()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ForEach(BrowserKind.allCases) { browser in
                    let profiles = settingsStore.profiles(for: browser)
                    if !profiles.isEmpty {
                        BrowserProfilesCard(browser: browser, profiles: profiles)
                    }
                }
            }

            safariPermissionsCard

            if !permissions.canReadSafariDatabase {
                SettingsCard(title: "Full Disk Access", subtitle: "Needed to read Safari profile names from disk.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("macOS blocks access to Safari's profile database without Full Disk Access. Add Browser Picker in System Settings → Privacy & Security → Full Disk Access, then restart the app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Open Full Disk Access Settings") {
                            permissions.openFullDiskAccessSettings()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .onAppear {
            permissions.refresh()
        }
    }

    @ViewBuilder
    private var safariPermissionsCard: some View {
        SettingsCard(title: "Safari automation", subtitle: "Required to open links in a specific Safari profile.") {
            VStack(alignment: .leading, spacing: 12) {
                if permissions.isAccessibilityTrusted {
                    Label {
                        Text("Accessibility access is enabled.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Label {
                        Text("Enable Browser Picker in System Settings → Privacy & Security → Accessibility, then quit and reopen this app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }

                    Text(permissions.applicationPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                        .lineLimit(2)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Button("Grant Access") {
                                permissions.requestAccessibilityPermission()
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Open Settings") {
                                permissions.openAccessibilitySettings()
                            }
                            .buttonStyle(.bordered)
                        }

                        HStack(spacing: 8) {
                            Button("Quit & Reopen") {
                                permissions.restartApplication()
                            }
                            .buttonStyle(.bordered)

                            Button("Check Again") {
                                permissions.refresh()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Divider()

                if SafariRuntime.isRunning {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Safari is running")
                                .font(.subheadline.weight(.medium))
                            Text("Scan the File → New Window menu to detect profile names.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Scan Safari Profiles") {
                            settingsStore.rescanSafariProfilesFromMenu()
                            permissions.refresh()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!permissions.isAccessibilityTrusted)
                    }
                } else {
                    Label {
                        Text("Open Safari first, then use “Scan Safari Profiles” to detect profile names without launching Safari from Refresh.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "safari")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct BrowserProfilesCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var profileError: String?
    let browser: BrowserKind
    let profiles: [BrowserProfile]

    /// Reads as "Default: Space, asd · Work: work": the profile's spaces under
    /// the containers they belong to, which is how links are routed to them.
    private func spacesDetail(for profile: BrowserProfile) -> String? {
        guard !profile.spaces.isEmpty else { return nil }
        return profile.spacesByContainer
            .map { container, spaces in
                "\(container): \(spaces.map(\.name).joined(separator: ", "))"
            }
            .joined(separator: " · ")
    }

    var body: some View {
        SettingsCard(
            title: browser.displayName,
            subtitle: "\(profiles.count) profile\(profiles.count == 1 ? "" : "s") detected · \(profiles.filter { settingsStore.isProfileEnabled($0) }.count) enabled"
        ) {
            VStack(spacing: 0) {
                ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                    HStack(spacing: 12) {
                        ProfileSummaryRow(profile: profile, detail: spacesDetail(for: profile))
                            .opacity(settingsStore.isProfileEnabled(profile) ? 1 : 0.5)

                        VStack(alignment: .trailing, spacing: 6) {
                            Toggle("Enabled", isOn: Binding(
                                get: { settingsStore.isProfileEnabled(profile) },
                                set: { enabled in
                                    do {
                                        try settingsStore.setProfileEnabled(enabled, for: profile)
                                    } catch {
                                        profileError = error.localizedDescription
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .font(.caption)
                            .accessibilityLabel("Enable \(browser.displayName) \(profile.displayName)")

                            Button(settingsStore.customIconData(for: profile) == nil ? "Choose Icon…" : "Change Icon…") {
                                chooseIcon(for: profile)
                            }
                            .accessibilityLabel("Choose icon for \(browser.displayName) \(profile.displayName)")

                            if settingsStore.customIconData(for: profile) != nil {
                                Button("Use Browser Icon") {
                                    do {
                                        try settingsStore.setCustomIcon(nil, for: profile)
                                    } catch {
                                        profileError = error.localizedDescription
                                    }
                                }
                                .accessibilityLabel("Restore browser icon for \(browser.displayName) \(profile.displayName)")
                            }
                        }
                        .controlSize(.small)
                        .fixedSize()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)

                    if index < profiles.count - 1 {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .alert("Couldn’t Update Profile", isPresented: Binding(
            get: { profileError != nil },
            set: { if !$0 { profileError = nil } }
        )) {
            Button("OK", role: .cancel) { profileError = nil }
        } message: {
            Text(profileError ?? "")
        }
    }

    private func chooseIcon(for profile: BrowserProfile) {
        let panel = NSOpenPanel()
        panel.title = "Choose Icon for \(profile.displayName)"
        panel.message = "Choose an image or logo for this profile. A copy will be saved in Browser Picker."
        panel.prompt = "Use Icon"
        panel.allowedContentTypes = ProfileIconImporter.supportedTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try ProfileIconImporter.pngData(from: url)
            try settingsStore.setCustomIcon(data, for: profile)
        } catch {
            profileError = error.localizedDescription
        }
    }
}

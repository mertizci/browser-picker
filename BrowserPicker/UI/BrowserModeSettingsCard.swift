import SwiftUI

struct BrowserModeSettingsCard: View {
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard(title: "Browser mode", subtitle: "Choose the features you need.") {
            VStack(spacing: 8) {
                SettingsOptionRow(title: "Basic browser picker",
                    subtitle: "Choose a browser for every link. No Full Disk Access or Accessibility required.",
                    systemImage: "globe", isSelected: settingsStore.settings.basicMode) {
                    do {
                        try settingsStore.setBasicMode(true)
                        URLRouter.shared.cancelPicker()
                    } catch { errorMessage = error.localizedDescription }
                }
                SettingsOptionRow(title: "Profiles and routing rules",
                    subtitle: "Select profiles and spaces, and route links automatically. Requires additional permissions.",
                    systemImage: "arrow.triangle.branch", isSelected: !settingsStore.settings.basicMode) {
                    PermissionsOnboardingWindowController.shared.showIfNeeded(forProfileSetup: true)
                }
            }
            if settingsStore.settings.basicMode {
                Text("Each browser chooses its current or default profile. Saved profile settings and rules are kept and resume when profile features are enabled.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .alert("Couldn’t Save Browser Mode", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

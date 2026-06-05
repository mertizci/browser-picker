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

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(settingsStore.profiles) { profile in
                        let target = RouteTarget(browser: profile.browser, profileId: profile.id)
                        Button {
                            selectedTarget = target
                            urlRouter.completePickerSelection(url: url, target: target)
                        } label: {
                            HStack(spacing: 12) {
                                ProfileIconView(profile: profile, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName)
                                        .font(.headline)
                                    Text(profile.browser.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedTarget == target {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    urlRouter.cancelPicker()
                    dismiss()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(minWidth: 380, minHeight: 320)
    }

    private func bringWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

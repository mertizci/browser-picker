import SwiftUI

struct PermissionsOnboardingView: View {
    @ObservedObject var permissions: PermissionMonitor
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 6) {
                Text("Add this app in System Settings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(permissions.applicationPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 12) {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionOnboardingRow(
                        kind: kind,
                        isGranted: permissions.isGranted(kind),
                        permissions: permissions
                    )
                }
            }

            if !permissions.isAccessibilityTrusted {
                Label {
                    Text("macOS only applies Accessibility after a restart. Click “Quit & Reopen” below — “Check Again” alone will not detect it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 10) {
                if !permissions.isAccessibilityTrusted {
                    Button("Quit & Reopen") {
                        permissions.restartApplication()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Check Again") {
                        permissions.refresh()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Check Again") {
                        permissions.refresh()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!permissions.allRequiredPermissionsGranted)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            permissions.refresh()
            permissions.startPolling()
        }
        .onDisappear {
            permissions.stopPolling()
        }
        .onChange(of: permissions.refreshCount) {
            if permissions.allRequiredPermissionsGranted {
                onContinue()
            }
        }
    }

    private var grantedCount: Int {
        PermissionKind.allCases.filter { permissions.isGranted($0) }.count
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 5) {
                Text("Welcome to Browser Picker")
                    .font(.title2.weight(.semibold))
                Text("Grant the permissions below so links open in the right browser profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: grantedCount == PermissionKind.allCases.count ? "checkmark.circle.fill" : "circle.lefthalf.filled")
                        .foregroundStyle(grantedCount == PermissionKind.allCases.count ? .green : .secondary)
                    Text("\(grantedCount) of \(PermissionKind.allCases.count) granted")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PermissionOnboardingRow: View {
    let kind: PermissionKind
    let isGranted: Bool
    @ObservedObject var permissions: PermissionMonitor

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isGranted ? .green : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(kind.title, systemImage: kind.systemImage)
                        .font(.headline)
                    Spacer()
                    if isGranted {
                        Text("Granted")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                Text(kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !isGranted {
                    HStack(spacing: 8) {
                        if kind == .accessibility {
                            Button("Grant Access") {
                                permissions.requestAccessibilityPermission()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }

                        Button("Open Settings") {
                            permissions.openSettings(for: kind)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

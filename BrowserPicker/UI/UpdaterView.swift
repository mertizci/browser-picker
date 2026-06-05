import AppKit
import SwiftUI

struct UpdaterView: View {
    @ObservedObject var controller: UpdateController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
        }
        .padding(24)
        .frame(width: 440)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .idle, .checking:
            checkingView
        case .available(let release):
            availableView(release)
        case .downloading(let fraction):
            downloadingView(fraction)
        case .installing:
            installingView
        case .upToDate:
            upToDateView
        case .failed(let message):
            failedView(message)
        case .justUpdated(let version, let notes):
            justUpdatedView(version: version, notes: notes)
        }
    }

    // MARK: - States

    private var checkingView: some View {
        HStack(spacing: 12) {
            ProgressView()
            Text("Checking for updates…")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func availableView(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(
                title: "A new version is available",
                subtitle: "Browser Picker \(release.displayVersion) — you have \(controller.currentVersion)."
            )

            releaseNotes(release.releaseNotes)

            HStack {
                Spacer()
                Button("Later") { controller.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Download & Install") { controller.startDownload(release) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func downloadingView(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Downloading update…", subtitle: nil)
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
            Text("\(Int(fraction * 100))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var installingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header(title: "Installing & restarting…", subtitle: nil)
            ProgressView()
                .progressViewStyle(.linear)
        }
    }

    private var upToDateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(
                title: "You're up to date",
                subtitle: "Browser Picker \(controller.currentVersion) is the latest version."
            )
            HStack {
                Spacer()
                Button("OK") { controller.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: "Update failed", subtitle: message)
            HStack {
                Spacer()
                Button("Close") { controller.dismiss() }
                Button("Check Again") { controller.checkForUpdates(silent: false) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func justUpdatedView(version: String, notes: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            header(title: "Updated to \(version)", subtitle: "What's new in this version:")
            releaseNotes(notes)
            HStack {
                Spacer()
                Button("Done") { controller.dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Shared pieces

    private func header(title: String, subtitle: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func releaseNotes(_ raw: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            ScrollView {
                Text(markdown(trimmed))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .frame(height: 200)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }

    /// Best-effort GitHub-flavored markdown rendering. Falls back to plain text.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

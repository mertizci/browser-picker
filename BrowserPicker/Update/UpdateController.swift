import AppKit
import Foundation

/// The user-facing state of the update flow, consumed by `UpdaterView`.
enum UpdateState: Equatable {
    case idle
    case checking
    case available(GitHubRelease)
    case downloading(Double)
    case installing
    case upToDate
    case failed(String)
    case justUpdated(version: String, notes: String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking), (.installing, .installing), (.upToDate, .upToDate):
            return true
        case let (.available(l), .available(r)):
            return l.tagName == r.tagName
        case let (.downloading(l), .downloading(r)):
            return l == r
        case let (.failed(l), .failed(r)):
            return l == r
        case let (.justUpdated(lv, ln), .justUpdated(rv, rn)):
            return lv == rv && ln == rn
        default:
            return false
        }
    }
}

/// Orchestrates the check → prompt → download → install → relaunch flow and
/// the post-update notice. All UI state is published for `UpdaterView`.
@MainActor
final class UpdateController: ObservableObject {
    static let shared = UpdateController()

    @Published private(set) var state: UpdateState = .idle

    private let service: GitHubReleaseService
    private let installer = UpdateInstaller()
    private var isWorking = false

    private static let pendingUpdateKey = "BrowserPicker.pendingUpdate"

    private struct PendingUpdate: Codable {
        let version: String
        let notes: String
    }

    init(service: GitHubReleaseService = GitHubReleaseService()) {
        self.service = service
    }

    // MARK: - Current version

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Checking

    /// Checks GitHub for a newer release. When `silent`, nothing is shown unless
    /// an update is actually available (used for the automatic launch check).
    func checkForUpdates(silent: Bool) {
        guard !isWorking else { return }
        isWorking = true
        state = .checking

        Task {
            defer { isWorking = false }
            do {
                let release = try await service.latestRelease()
                guard let latest = SemanticVersion(release.tagName),
                      let current = SemanticVersion(currentVersion) else {
                    finishCheck(silent: silent, result: .upToDate)
                    return
                }

                if latest > current {
                    state = .available(release)
                    UpdaterWindowController.shared.show()
                } else {
                    finishCheck(silent: silent, result: .upToDate)
                }
            } catch {
                finishCheck(silent: silent, result: .failed(error.localizedDescription))
            }
        }
    }

    private func finishCheck(silent: Bool, result: UpdateState) {
        if silent {
            state = .idle
        } else {
            state = result
            UpdaterWindowController.shared.show()
        }
    }

    // MARK: - Download & install

    func startDownload(_ release: GitHubRelease) {
        guard !isWorking else { return }
        isWorking = true

        Task {
            defer { isWorking = false }
            do {
                guard let asset = service.dmgAsset(in: release) else {
                    throw GitHubReleaseError.noDMGAsset
                }

                // Persist now so the post-update popup works even offline later.
                persistPendingUpdate(version: release.displayVersion, notes: release.releaseNotes)

                state = .downloading(0)
                let downloader = UpdateDownloader()
                let dmgURL = try await downloader.download(asset.browserDownloadURL) { [weak self] fraction in
                    self?.state = .downloading(fraction)
                }

                state = .installing
                let staged = try await Task.detached(priority: .userInitiated) {
                    try UpdateInstaller().prepareStagedApp(fromDMG: dmgURL)
                }.value

                try? FileManager.default.removeItem(at: dmgURL)

                // Replaces the bundle and relaunches; terminates this process.
                try installer.installAndRelaunch(stagedApp: staged, into: Bundle.main.bundleURL)
            } catch let error as UpdateInstallError where error == .destinationNotWritable {
                clearPendingUpdate()
                state = .failed(error.localizedDescription)
                revealDownloadFolder()
            } catch {
                clearPendingUpdate()
                state = .failed(error.localizedDescription)
            }
        }
    }

    func dismiss() {
        state = .idle
        UpdaterWindowController.shared.close()
    }

    // MARK: - Post-update notice

    /// If the app was just relaunched into the version we updated to, surfaces
    /// the "Updated to vX.Y.Z" popup with release notes, then clears the flag.
    func consumePostUpdateNoticeIfNeeded() {
        guard let pending = loadPendingUpdate() else { return }
        clearPendingUpdate()

        guard let pendingVersion = SemanticVersion(pending.version),
              let current = SemanticVersion(currentVersion),
              current >= pendingVersion else {
            return
        }

        state = .justUpdated(version: pending.version, notes: pending.notes)
        UpdaterWindowController.shared.show()
    }

    // MARK: - Persistence

    private func persistPendingUpdate(version: String, notes: String) {
        let pending = PendingUpdate(version: version, notes: notes)
        if let data = try? JSONEncoder().encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.pendingUpdateKey)
        }
    }

    private func loadPendingUpdate() -> PendingUpdate? {
        guard let data = UserDefaults.standard.data(forKey: Self.pendingUpdateKey) else { return nil }
        return try? JSONDecoder().decode(PendingUpdate.self, from: data)
    }

    private func clearPendingUpdate() {
        UserDefaults.standard.removeObject(forKey: Self.pendingUpdateKey)
    }

    private func revealDownloadFolder() {
        let url = URL(string: "https://github.com/\(GitHubReleaseService.repository)/releases/latest")!
        NSWorkspace.shared.open(url)
    }
}

import AppKit
import Foundation

@MainActor
final class URLRouter: ObservableObject {
    static let shared = URLRouter(settingsStore: .shared)

    @Published var pendingPickerURL: URL?
    @Published var pendingPickerContext: RoutingContext?

    private let ruleEngine = RuleEngine()
    private let launcher = BrowserLauncher()
    private let settingsStore: SettingsStore

    /// Links whose open is still on its way to a browser. A link is dropped
    /// while its own open is in flight, so it cannot end up in two tabs when it
    /// arrives twice — macOS re-delivering it, or a second click made while a
    /// cold browser is still starting and nothing has appeared yet.
    private var linksBeingOpened: Set<URL> = []
    private var waitingForSetup: [RoutingContext] = []

    /// A browser opens its tab shortly after the launcher is done, so a link
    /// stays guarded a moment longer than the open itself takes.
    private static let openSettleDelay: Duration = .seconds(2)

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func handleOpenURLs(_ urls: [URL], sourceApp: String? = nil) {
        for url in urls {
            route(url: url, sourceApp: sourceApp)
        }
    }

    func route(url: URL, sourceApp: String? = nil) {
        if !settingsStore.settings.basicMode && !PermissionMonitor.shared.allRequiredPermissionsGranted {
            waitingForSetup.append(RoutingContext(url: url, sourceApp: sourceApp))
            PermissionsOnboardingWindowController.shared.showIfNeeded()
            return
        }
        // On a cold launch the link arrives before profiles have been
        // discovered. Load them on demand so the very first click resolves
        // instead of failing with "profile not found".
        ensureProfilesLoaded()

        let context = RoutingContext(url: url, sourceApp: sourceApp)
        let settings = settingsStore.settings

        switch ruleEngine.decision(for: context, settings: settings, hasEnabledDefault: settingsStore.enabledDefaultProfile != nil) {
        case .picker:
            pendingPickerURL = url
            pendingPickerContext = context
            PickerWindowController.shared.show(settingsStore: settingsStore, urlRouter: self)
        case .rule(let rule):
            open(url: url, target: rule.target)
        case .defaultTarget(let target):
            open(url: url, target: target)
        }
    }

    func completePickerSelection(url: URL, target: RouteTarget) {
        guard let profile = settingsStore.profile(for: target), settingsStore.isProfileEnabled(profile) else { return }
        pendingPickerURL = nil
        pendingPickerContext = nil
        PickerWindowController.shared.close()
        open(url: url, target: target)
    }

    func cancelPicker() {
        pendingPickerURL = nil
        pendingPickerContext = nil
        PickerWindowController.shared.close()
    }

    func open(url: URL, target: RouteTarget) {
        // A link is being routed to a browser — never let our own windows steal focus.
        SettingsWindowController.shared.hide()

        guard let profile = settingsStore.profile(for: target) else {
            showError(BrowserPickerError.profileNotFound)
            return
        }

        guard settingsStore.isProfileEnabled(profile) else {
            showError(BrowserPickerError.profileDisabled)
            return
        }

        guard linksBeingOpened.insert(url).inserted else { return }

        let siblingProfileNames = settingsStore.profiles(for: profile.browser)
            .map { $0.internalName ?? $0.displayName }
        let space = profile.space(id: target.spaceId)
        let basicMode = settingsStore.settings.basicMode

        Task {
            do {
                if basicMode {
                    try await launcher.openBrowser(url: url, browser: profile.browser)
                } else {
                    try await launcher.open(
                        url: url,
                        profile: profile,
                        space: space,
                        siblingProfileNames: siblingProfileNames
                    )
                }
            } catch {
                showError(error)
            }

            try? await Task.sleep(for: Self.openSettleDelay)
            linksBeingOpened.remove(url)
        }
    }

    private func ensureProfilesLoaded() {
        guard settingsStore.profiles.isEmpty else { return }
        settingsStore.reloadProfiles()
    }

    func resumeAfterSetup() {
        let queued = waitingForSetup
        waitingForSetup = []
        for context in queued { route(url: context.url, sourceApp: context.sourceApp) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Browser Picker"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

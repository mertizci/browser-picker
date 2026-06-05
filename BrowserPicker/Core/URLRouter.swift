import AppKit
import Foundation

@MainActor
final class URLRouter: ObservableObject {
    static let shared = URLRouter()

    @Published var pendingPickerURL: URL?
    @Published var pendingPickerContext: RoutingContext?

    private let ruleEngine = RuleEngine()
    private let launcher = BrowserLauncher()
    private var settingsStore: SettingsStore { .shared }

    private init() {}

    func handleOpenURLs(_ urls: [URL], sourceApp: String? = nil) {
        for url in urls {
            route(url: url, sourceApp: sourceApp)
        }
    }

    func route(url: URL, sourceApp: String? = nil) {
        // On a cold launch the link arrives before profiles have been
        // discovered. Load them on demand so the very first click resolves
        // instead of failing with "profile not found".
        ensureProfilesLoaded()

        let context = RoutingContext(url: url, sourceApp: sourceApp)
        let settings = settingsStore.settings

        if settings.fallbackMode == .picker,
           ruleEngine.matchingRule(for: context, in: settings) == nil {
            pendingPickerURL = url
            pendingPickerContext = context
            PickerWindowController.shared.show(settingsStore: settingsStore, urlRouter: self)
            return
        }

        let target = ruleEngine.resolveTarget(for: context, settings: settings)
        open(url: url, target: target)
    }

    func completePickerSelection(url: URL, target: RouteTarget) {
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

        Task {
            do {
                try await launcher.open(url: url, profile: profile)
            } catch {
                showError(error)
            }
        }
    }

    private func ensureProfilesLoaded() {
        guard settingsStore.profiles.isEmpty else { return }
        settingsStore.reloadProfiles()
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Browser Picker"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isDefaultBrowser = false

    private init() {}

    func refreshDefaultBrowserStatus() {
        isDefaultBrowser = DefaultBrowserService.isDefaultBrowser
    }

    func registerAsDefaultBrowser() {
        Task {
            await DefaultBrowserService.setAsDefaultBrowser()
            refreshDefaultBrowserStatus()
        }
    }
}

enum DefaultBrowserService {
    static var isDefaultBrowser: Bool {
        guard let defaultURL = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "http://example.com")!) else {
            return false
        }
        return defaultURL.path == Bundle.main.bundlePath
    }

    static func setAsDefaultBrowser() async {
        do {
            try await NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL,
                toOpenURLsWithScheme: "http"
            )
        } catch {
            NSLog("BrowserPicker: failed to set default browser – \(error.localizedDescription)")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            URLRouter.shared.handleOpenURLs(urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            PermissionMonitor.shared.refresh()
            PermissionsOnboardingWindowController.shared.showIfNeeded()

            if PermissionMonitor.shared.allRequiredPermissionsGranted {
                SettingsStore.shared.reloadProfiles()
            }

            AppState.shared.refreshDefaultBrowserStatus()

            // Surface the "Updated to X" popup if we just self-updated, then
            // silently check GitHub for a newer release on every launch.
            UpdateController.shared.consumePostUpdateNoticeIfNeeded()
            UpdateController.shared.checkForUpdates(silent: true)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            PermissionMonitor.shared.refresh()

            if !PermissionMonitor.shared.allRequiredPermissionsGranted {
                PermissionsOnboardingWindowController.shared.showIfNeeded()
            }
        }
    }
}

@main
struct BrowserPickerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore = SettingsStore.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var urlRouter = URLRouter.shared
    @StateObject private var permissionMonitor = PermissionMonitor.shared
    @StateObject private var updateController = UpdateController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(settingsStore)
                .environmentObject(appState)
                .environmentObject(urlRouter)
                .environmentObject(permissionMonitor)
                .environmentObject(updateController)
        } label: {
            Image(systemName: "arrow.triangle.branch")
        }
        .menuBarExtraStyle(.window)
    }
}

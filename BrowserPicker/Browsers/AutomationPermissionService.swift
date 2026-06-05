import AppKit
import ApplicationServices
import Combine

enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case fullDiskAccess

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility:
            return "Accessibility"
        case .fullDiskAccess:
            return "Full Disk Access"
        }
    }

    var subtitle: String {
        switch self {
        case .accessibility:
            return "Control Safari to open links in the correct profile."
        case .fullDiskAccess:
            return "Read Safari profile names from the system database."
        }
    }

    var systemImage: String {
        switch self {
        case .accessibility:
            return "hand.raised.fill"
        case .fullDiskAccess:
            return "externaldrive.fill.badge.checkmark"
        }
    }
}

@MainActor
final class PermissionMonitor: ObservableObject {
    static let shared = PermissionMonitor()

    @Published private(set) var isAccessibilityTrusted = false
    @Published private(set) var canReadSafariDatabase = false
    @Published private(set) var refreshCount = 0
    @Published private(set) var isOnboardingActive = false

    func setOnboardingActive(_ active: Bool) {
        isOnboardingActive = active
    }

    var applicationPath: String {
        Bundle.main.bundleURL.path
    }

    var allRequiredPermissionsGranted: Bool {
        isAccessibilityTrusted && canReadSafariDatabase
    }

    func isGranted(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:
            return isAccessibilityTrusted
        case .fullDiskAccess:
            return canReadSafariDatabase
        }
    }

    private var observers: [NSObjectProtocol] = []
    private var pollingTask: Task<Void, Never>?

    private init() {
        refresh()

        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        )
    }

    func refresh() {
        let accessibility = AXIsProcessTrusted()
        let safariDatabase = SafariProfileStore.canReadDatabase

        isAccessibilityTrusted = accessibility
        canReadSafariDatabase = safariDatabase
        refreshCount += 1
    }

    func startPolling() {
        stopPolling()
        pollingTask = Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            refresh()
        }
    }

    func openSettings(for kind: PermissionKind) {
        switch kind {
        case .accessibility:
            openAccessibilitySettings()
        case .fullDiskAccess:
            openFullDiskAccessSettings()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func restartApplication() {
        let appPath = Bundle.main.bundleURL.path

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open -n \"\(appPath)\""]

        do {
            try task.run()
        } catch {
            NSLog("BrowserPicker: failed to schedule relaunch – \(error.localizedDescription)")
        }

        NSApplication.shared.terminate(nil)
    }
}

enum SafariRuntime {
    static var isRunning: Bool {
        !NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == "com.apple.Safari" }.isEmpty
    }
}

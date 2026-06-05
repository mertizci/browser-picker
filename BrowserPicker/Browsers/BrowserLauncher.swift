import AppKit
import Foundation

struct BrowserLauncher {
    func open(url: URL, profile: BrowserProfile) async throws {
        guard FileManager.default.fileExists(atPath: profile.browser.appPath) else {
            throw BrowserPickerError.browserNotInstalled(profile.browser)
        }

        switch profile.browser {
        case .chrome:
            try launchChrome(url: url, profile: profile)
        case .firefox:
            try launchFirefox(url: url, profile: profile)
        case .safari:
            try SafariLauncher().open(url: url, profile: profile)
        }
    }

    private func launchChrome(url: URL, profile: BrowserProfile) throws {
        let directory = profile.profilePath ?? "Default"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: profile.browser.executablePath)
        process.arguments = ["--profile-directory=\(directory)", url.absoluteString]
        try process.run()
    }

    private func launchFirefox(url: URL, profile: BrowserProfile) throws {
        var attempts: [[String]] = []

        if let profilePath = profile.profilePath,
           profile.id != "\(BrowserKind.firefox.rawValue)-default" {
            attempts.append(["--profile", profilePath, "-url", url.absoluteString])
            if let internalName = profile.internalName {
                attempts.append(["-P", internalName, "-url", url.absoluteString])
                attempts.append(["-P", internalName, "-no-remote", "-url", url.absoluteString])
            }
        } else {
            attempts.append(["-url", url.absoluteString])
        }

        var lastError: Error?
        for arguments in attempts {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: profile.browser.executablePath)
            process.arguments = arguments
            do {
                try process.run()
                return
            } catch {
                lastError = error
            }
        }

        throw BrowserPickerError.launchFailed(lastError?.localizedDescription ?? "Unknown error")
    }
}

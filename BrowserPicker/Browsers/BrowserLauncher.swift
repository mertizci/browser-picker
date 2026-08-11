import AppKit
import Foundation

struct BrowserLauncher {
    /// - Parameter siblingProfileNames: every profile name of `profile`'s
    ///   browser, which browsers driven by automation need to tell profiles apart.
    func open(url: URL, profile: BrowserProfile, siblingProfileNames: [String] = []) async throws {
        guard profile.browser.isInstalled else {
            throw BrowserPickerError.browserNotInstalled(profile.browser)
        }

        switch profile.browser.profileLaunchStyle {
        case .chromiumArguments:
            try launchChromium(url: url, profile: profile)
        case .firefoxArguments:
            try launchFirefox(url: url, profile: profile)
        case .safariAutomation:
            try SafariLauncher().open(url: url, profile: profile, allProfileNames: siblingProfileNames)
        case .diaAutomation:
            try DiaLauncher().open(url: url, profile: profile, allProfileNames: siblingProfileNames)
        }
    }

    private func launchChromium(url: URL, profile: BrowserProfile) throws {
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

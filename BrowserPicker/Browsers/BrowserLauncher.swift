import AppKit
import Foundation

struct BrowserLauncher {
    /// - Parameter space: a space inside `profile`, or `nil` to use whichever
    ///   space the browser already has open.
    /// - Parameter siblingProfileNames: every profile name of `profile`'s
    ///   browser, which browsers driven by automation need to tell profiles apart.
    func open(
        url: URL,
        profile: BrowserProfile,
        space: BrowserSpace? = nil,
        siblingProfileNames: [String] = []
    ) async throws {
        guard profile.browser.isInstalled else {
            throw BrowserPickerError.browserNotInstalled(profile.browser)
        }

        switch profile.browser.profileLaunchStyle {
        case .chromiumArguments:
            try launchChromium(url: url, profile: profile)
        case .geckoArguments:
            try GeckoLauncher().launch(url: url, profile: profile)
        case .zenAutomation:
            try ZenLauncher().open(url: url, profile: profile, space: space)
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

}

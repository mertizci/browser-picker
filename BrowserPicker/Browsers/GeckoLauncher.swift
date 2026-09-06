import Foundation

/// Hands a link to a Gecko browser (Firefox, Zen) through its profile switches,
/// falling back to the `-P` name when the profile path is refused.
struct GeckoLauncher {
    /// - Parameter url: `nil` starts the browser without opening a link, which
    ///   Zen needs before its space can be switched.
    func launch(url: URL?, profile: BrowserProfile) throws {
        var lastError: Error?
        for arguments in argumentAttempts(url: url, profile: profile) {
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

    private func argumentAttempts(url: URL?, profile: BrowserProfile) -> [[String]] {
        let urlArguments = url.map { ["-url", $0.absoluteString] } ?? []

        guard let profilePath = profile.profilePath,
              profile.id != BrowserProfile.defaultProfile(for: profile.browser).id
        else { return [urlArguments] }

        var attempts = [["--profile", profilePath] + urlArguments]
        if let internalName = profile.internalName {
            attempts.append(["-P", internalName] + urlArguments)
            attempts.append(["-P", internalName, "-no-remote"] + urlArguments)
        }
        return attempts
    }
}

import Foundation

/// Discovers the profiles of a Gecko browser (Firefox, Zen), which all keep
/// `profiles.ini`, a `Profiles` folder and their profile groups in the same
/// layout — only the support directory differs.
struct GeckoProfileDiscovery: ProfileDiscovery {
    let browser: BrowserKind

    init(browser: BrowserKind) {
        self.browser = browser
    }

    private static let genericNames: Set<String> = [
        "default",
        "default-release",
        "default-esr",
        "default-nightly",
        "dev-edition-default"
    ]

    private var supportRoot: URL? {
        guard let directoryName = browser.geckoSupportDirectoryName else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(directoryName)
    }

    func discoverProfiles() -> [BrowserProfile] {
        guard browser.isInstalled, let supportRoot else { return [] }

        let selectableNames = GeckoProfileGroupReader(supportDirectory: supportRoot)
            .selectableProfileNames()
        var byRelativePath: [String: BrowserProfile] = [:]

        for entry in parseProfilesIni(in: supportRoot) {
            byRelativePath[entry.relativePath] = makeProfile(
                relativePath: entry.relativePath,
                iniName: entry.iniName,
                fullPath: entry.fullPath,
                selectableNames: selectableNames
            )
        }

        for directory in profileDirectories(in: supportRoot) {
            let relativePath = "Profiles/\(directory.lastPathComponent)"
            if byRelativePath[relativePath] != nil { continue }

            let displayName = selectableNames[relativePath]
                ?? folderDisplayName(from: directory.lastPathComponent)
                ?? directory.lastPathComponent

            byRelativePath[relativePath] = profile(
                id: relativePath,
                displayName: displayName,
                path: directory.path,
                internalName: displayName
            )
        }

        let profiles = byRelativePath.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return profiles.isEmpty ? [BrowserProfile.defaultProfile(for: browser)] : profiles
    }

    private func profileDirectories(in supportRoot: URL) -> [URL] {
        let profilesDirectory = supportRoot.appendingPathComponent("Profiles")
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return directories.filter { directory in
            var isDirectory = ObjCBool(false)
            return FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    private struct INIEntry {
        let relativePath: String
        let iniName: String
        let fullPath: String
    }

    private func parseProfilesIni(in supportRoot: URL) -> [INIEntry] {
        let profilesIniURL = supportRoot.appendingPathComponent("profiles.ini")
        guard let content = try? String(contentsOf: profilesIniURL, encoding: .utf8) else { return [] }

        var entries: [INIEntry] = []
        var currentSection = ""
        var currentValues: [String: String] = [:]

        func flushProfileSection() {
            guard currentSection.hasPrefix("Profile"),
                  currentValues["IsRelative"] == "1",
                  let path = currentValues["Path"] else { return }

            let iniName = currentValues["Name"] ?? path
            let fullPath = supportRoot.appendingPathComponent(path).path
            entries.append(INIEntry(relativePath: path, iniName: iniName, fullPath: fullPath))
        }

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                flushProfileSection()
                currentSection = String(trimmed.dropFirst().dropLast())
                currentValues = [:]
                continue
            }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                currentValues[parts[0].trimmingCharacters(in: .whitespaces)] =
                    parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        flushProfileSection()
        return entries
    }

    private func makeProfile(
        relativePath: String,
        iniName: String,
        fullPath: String,
        selectableNames: [String: String]
    ) -> BrowserProfile {
        let folderLabel = folderDisplayName(from: URL(fileURLWithPath: fullPath).lastPathComponent)
        let displayName = selectableNames[relativePath]
            ?? resolvedDisplayName(iniName: iniName, folderLabel: folderLabel)

        return profile(
            id: relativePath,
            displayName: displayName,
            path: fullPath,
            internalName: iniName
        )
    }

    private func profile(
        id: String,
        displayName: String,
        path: String,
        internalName: String
    ) -> BrowserProfile {
        BrowserProfile(
            id: id,
            displayName: displayName,
            browser: browser,
            profilePath: path,
            internalName: internalName,
            spaces: browser == .zen ? ZenSpaceReader.spaces(inProfileAt: path) : []
        )
    }

    private func resolvedDisplayName(iniName: String, folderLabel: String?) -> String {
        let iniLower = iniName.lowercased()
        guard Self.genericNames.contains(iniLower) else { return iniName }

        if let folderLabel,
           !folderLabel.isEmpty,
           !Self.genericNames.contains(folderLabel.lowercased()) {
            return folderLabel
        }

        return humanizeGenericName(iniName)
    }

    private func humanizeGenericName(_ name: String) -> String {
        switch name.lowercased() {
        case "default-release": return "Release"
        case "default-esr": return "ESR"
        case "default-nightly": return "Nightly"
        case "dev-edition-default": return "Developer Edition"
        default: return name
        }
    }

    /// Gecko profile folders use `{hash}.{label}` — return the label portion.
    private func folderDisplayName(from folderName: String) -> String? {
        guard let dotIndex = folderName.firstIndex(of: ".") else { return nil }
        let label = String(folderName[folderName.index(after: dotIndex)...])
        return label.isEmpty ? nil : label
    }
}

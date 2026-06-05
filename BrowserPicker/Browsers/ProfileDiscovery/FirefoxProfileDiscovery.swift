import Foundation

struct FirefoxProfileDiscovery: ProfileDiscovery {
    let browser: BrowserKind = .firefox

    private static let genericNames: Set<String> = [
        "default",
        "default-release",
        "default-esr",
        "default-nightly",
        "dev-edition-default"
    ]

    private var firefoxRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Firefox")
    }

    private var profilesIniURL: URL {
        firefoxRoot.appendingPathComponent("profiles.ini")
    }

    private var profilesDirectory: URL {
        firefoxRoot.appendingPathComponent("Profiles")
    }

    func discoverProfiles() -> [BrowserProfile] {
        guard FileManager.default.fileExists(atPath: browser.appPath) else { return [] }

        let selectableNames = FirefoxProfileGroupReader.selectableProfileNames()
        let iniEntries = parseProfilesIni()
        var byRelativePath: [String: BrowserProfile] = [:]

        for entry in iniEntries {
            let profile = makeProfile(
                relativePath: entry.relativePath,
                iniName: entry.iniName,
                fullPath: entry.fullPath,
                selectableNames: selectableNames
            )
            byRelativePath[entry.relativePath] = profile
        }

        if let directories = try? FileManager.default.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for directory in directories {
                var isDirectory = ObjCBool(false)
                guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let relativePath = "Profiles/\(directory.lastPathComponent)"
                if byRelativePath[relativePath] != nil { continue }

                let displayName = selectableNames[relativePath]
                    ?? folderDisplayName(from: directory.lastPathComponent)
                    ?? directory.lastPathComponent

                byRelativePath[relativePath] = BrowserProfile(
                    id: relativePath,
                    displayName: displayName,
                    browser: .firefox,
                    profilePath: directory.path,
                    internalName: displayName
                )
            }
        }

        let profiles = byRelativePath.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        if profiles.isEmpty {
            return [BrowserProfile.defaultProfile(for: .firefox)]
        }

        return profiles
    }

    private struct INIEntry {
        let relativePath: String
        let iniName: String
        let fullPath: String
    }

    private func parseProfilesIni() -> [INIEntry] {
        guard let content = try? String(contentsOf: profilesIniURL, encoding: .utf8) else { return [] }

        var entries: [INIEntry] = []
        var currentSection = ""
        var currentValues: [String: String] = [:]

        func flushProfileSection() {
            guard currentSection.hasPrefix("Profile"),
                  currentValues["IsRelative"] == "1",
                  let path = currentValues["Path"] else { return }

            let iniName = currentValues["Name"] ?? path
            let fullPath = firefoxRoot.appendingPathComponent(path).path
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
        let folderName = URL(fileURLWithPath: fullPath).lastPathComponent
        let folderLabel = folderDisplayName(from: folderName)
        let displayName: String

        if let selectableName = selectableNames[relativePath] {
            displayName = selectableName
        } else {
            displayName = resolvedDisplayName(iniName: iniName, folderLabel: folderLabel)
        }

        return BrowserProfile(
            id: relativePath,
            displayName: displayName,
            browser: .firefox,
            profilePath: fullPath,
            internalName: iniName
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

    /// Firefox profile folders use `{hash}.{label}` — return the label portion.
    private func folderDisplayName(from folderName: String) -> String? {
        guard let dotIndex = folderName.firstIndex(of: ".") else { return nil }
        let label = String(folderName[folderName.index(after: dotIndex)...])
        return label.isEmpty ? nil : label
    }
}

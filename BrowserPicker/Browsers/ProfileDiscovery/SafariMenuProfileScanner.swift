import Foundation

enum SafariMenuProfileScanner {
    /// Reads profile names from Safari's menu. Does not launch Safari.
    static func discoverProfiles() -> [SafariProfileRecord] {
        guard SafariRuntime.isRunning else { return [] }

        let script = """
        on run
            tell application "System Events"
                if not (exists process "Safari") then return ""
                tell process "Safari"
                    set targetMenu to menu "New Window" of menu item "New Window" of menu "File" of menu bar 1
                    set menuItems to name of every menu item of targetMenu
                end tell
            end tell

            set AppleScript's text item delimiters to linefeed
            set output to menuItems as text
            return output
        end run
        """

        guard let output = runOSA(script), !output.isEmpty else { return [] }

        let profiles = output
            .split(separator: "\n")
            .map(String.init)
            .compactMap(parseMenuItem)

        var unique: [String: SafariProfileRecord] = [:]
        for profile in profiles {
            unique[profile.id] = profile
        }

        return unique.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func parseMenuItem(_ item: String) -> SafariProfileRecord? {
        let trimmed = item.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("New "), trimmed.hasSuffix(" Window") else { return nil }

        let namePart = trimmed
            .dropFirst(4)
            .dropLast(7)
            .trimmingCharacters(in: .whitespaces)

        let menuName = namePart.isEmpty ? "Personal" : String(namePart)
        let id = menuName == "Personal" ? SafariProfileRecord.defaultID : menuName

        return SafariProfileRecord(
            id: id,
            displayName: menuName,
            menuName: menuName
        )
    }

    private static func runOSA(_ source: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

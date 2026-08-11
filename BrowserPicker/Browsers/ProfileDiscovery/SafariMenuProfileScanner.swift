import Foundation

/// Language-independent fallback that reads Safari profile names from the menu
/// bar when the `SafariTabs.db` (the authoritative source) cannot be read.
///
/// It never relies on localized menu titles:
/// * The **File** menu is reached by position (`menu bar item 3`), not by the
///   word "File" (which is "Ablage", "Fichier", "ファイル", … in other languages).
/// * Profile names are extracted by stripping the **common prefix/suffix** shared
///   by the submenu entries. For "New Work Window" / "New Personal Window" the
///   shared boilerplate is `"New "` + `" Window"`, leaving `Work` / `Personal`.
///   The exact same logic recovers `Work` / `Personal` from the German
///   "Neues Work-Fenster" / "Neues Personal-Fenster", and so on for any locale.
enum SafariMenuProfileScanner {
    /// Byte used by the AppleScript to separate one candidate submenu from the next.
    private static let groupSeparator = "\u{1F}"

    /// Reads profile names from Safari's menu. Does not launch Safari.
    static func discoverProfiles() -> [SafariProfileRecord] {
        guard SafariRuntime.isRunning else { return [] }
        guard let output = AppleScriptRunner.output(of: script), !output.isEmpty else { return [] }

        // The File menu can contain several submenu-bearing items (New Window,
        // New Tab, Open Recent, Share …). "New Window" — the profile list — is
        // always the first of them, so we only trust the first group. This
        // avoids misreading unrelated submenus (e.g. "Open Recent") as profiles.
        guard let firstGroup = output
            .components(separatedBy: groupSeparator)
            .map(menuItemNames(from:))
            .first(where: { $0.count > 1 })
        else { return [] }

        return records(from: extractProfileNames(from: firstGroup))
    }

    private static let script = """
    on run
        tell application "System Events"
            if not (exists process "Safari") then return ""
            tell process "Safari"
                set fileMenu to menu 1 of menu bar item 3 of menu bar 1
                set groupList to {}
                repeat with mi in (menu items of fileMenu)
                    try
                        if (count of menus of mi) > 0 then
                            set subMenu to menu 1 of mi
                            set subItems to {}
                            repeat with smi in (menu items of subMenu)
                                try
                                    set n to name of smi
                                    if n is not missing value then
                                        if (n as string) is not "" then set end of subItems to (n as string)
                                    end if
                                end try
                            end repeat
                            if (count of subItems) > 1 then
                                set AppleScript's text item delimiters to linefeed
                                set end of groupList to (subItems as text)
                            end if
                        end if
                    end try
                end repeat
            end tell
        end tell
        set AppleScript's text item delimiters to (ASCII character 31)
        return groupList as text
    end run
    """

    private static func menuItemNames(from group: String) -> [String] {
        group
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Removes the boilerplate that every entry shares, leaving the profile name.
    private static func extractProfileNames(from items: [String]) -> [String] {
        guard items.count > 1 else { return [] }

        let prefix = commonPrefix(of: items)
        let suffix = commonSuffix(of: items, keepingRoomFor: prefix.count)

        // Require shared boilerplate; otherwise this submenu is something else
        // (e.g. "Open Recent", whose entries share nothing).
        guard prefix.count + suffix.count > 0 else { return [] }

        var seen = Set<String>()
        var names: [String] = []
        for item in items where item.count >= prefix.count + suffix.count {
            let start = item.index(item.startIndex, offsetBy: prefix.count)
            let end = item.index(item.endIndex, offsetBy: -suffix.count)
            let name = String(item[start..<end]).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }

    private static func commonPrefix(of items: [String]) -> String {
        guard var prefix = items.first else { return "" }
        for item in items.dropFirst() {
            prefix = String(prefix.commonPrefix(with: item))
            if prefix.isEmpty { break }
        }
        return prefix
    }

    private static func commonSuffix(of items: [String], keepingRoomFor prefixCount: Int) -> String {
        let reversedItems = items.map { String($0.reversed()) }
        var suffix = commonPrefix(of: reversedItems)

        // Never let the suffix overlap the shared prefix on the shortest entry.
        if let shortest = items.map(\.count).min() {
            let maxSuffix = max(0, shortest - prefixCount)
            if suffix.count > maxSuffix {
                suffix = String(suffix.prefix(maxSuffix))
            }
        }
        return String(suffix.reversed())
    }

    private static func records(from names: [String]) -> [SafariProfileRecord] {
        names
            .map { SafariProfileRecord(id: $0, displayName: $0, menuName: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}

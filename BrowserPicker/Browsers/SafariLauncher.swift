import Foundation

struct SafariLauncher {
    func open(url: URL, profile: BrowserProfile) throws {
        let menuName = profile.internalName ?? profile.displayName
        let script = appleScript(urlString: url.absoluteString, menuName: menuName)

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw BrowserPickerError.launchFailed(message?.isEmpty == false ? message! : "Safari automation failed. Grant Accessibility access in System Settings.")
        }
    }

    private func appleScript(urlString: String, menuName: String) -> String {
        let escapedURL = escapeAppleScript(urlString)
        let escapedMenuName = escapeAppleScript(menuName)

        return """
        on run
            set targetURL to "\(escapedURL)"
            set profileMenuName to "\(escapedMenuName)"

            tell application "Safari" to activate
            delay 0.4

            set targetWindow to missing value
            tell application "Safari"
                repeat with w in windows
                    if profileMenuName is "Personal" then
                        set windowName to name of w
                        if windowName is "Safari" or windowName starts with "Personal" then
                            set targetWindow to w
                            exit repeat
                        end if
                    else if name of w starts with profileMenuName then
                        set targetWindow to w
                        exit repeat
                    end if
                end repeat
            end tell

            if targetWindow is not missing value then
                tell application "Safari"
                    tell targetWindow
                        make new tab with properties {URL:targetURL}
                    end tell
                    set index of targetWindow to 1
                end tell
                return
            end if

            -- Build candidate menu item names for opening a new profile window
            set wantedNames to {"New " & profileMenuName & " Window"}
            if profileMenuName is "Personal" then
                set end of wantedNames to "New Window"
            end if

            set didClick to false
            tell application "System Events"
                tell process "Safari"
                    set fileMenu to menu "File" of menu bar 1

                    -- 1) direct items in the File menu
                    repeat with wanted in wantedNames
                        repeat with mi in (menu items of fileMenu)
                            try
                                if name of mi is (wanted as string) then
                                    click mi
                                    set didClick to true
                                    exit repeat
                                end if
                            end try
                        end repeat
                        if didClick then exit repeat
                    end repeat

                    -- 2) one level of submenus (e.g. a "New Window" submenu listing profiles)
                    if not didClick then
                        repeat with mi in (menu items of fileMenu)
                            try
                                if (count of menus of mi) > 0 then
                                    set subMenu to menu 1 of mi
                                    repeat with wanted in wantedNames
                                        repeat with smi in (menu items of subMenu)
                                            try
                                                if name of smi is (wanted as string) then
                                                    click smi
                                                    set didClick to true
                                                    exit repeat
                                                end if
                                            end try
                                        end repeat
                                        if didClick then exit repeat
                                    end repeat
                                end if
                            end try
                            if didClick then exit repeat
                        end repeat
                    end if
                end tell
            end tell

            if not didClick then
                error "Could not find a Safari menu item for profile \\"" & profileMenuName & "\\". Open Safari and verify the profile name."
            end if

            delay 0.6
            tell application "Safari"
                if (count of windows) > 0 then
                    set URL of current tab of front window to targetURL
                end if
            end tell
        end run
        """
    }

    private func escapeAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

import Foundation

struct SafariLauncher {
    func open(url: URL, profile: BrowserProfile, allProfileNames: [String] = []) throws {
        let menuName = profile.internalName ?? profile.displayName
        let isDefault = profile.id == SafariProfileRecord.defaultID
        let otherProfileNames = allProfileNames.filter { $0 != menuName }
        let script = appleScript(
            urlString: url.absoluteString,
            menuName: menuName,
            otherProfileNames: otherProfileNames,
            isDefault: isDefault
        )

        try AppleScriptRunner.run(
            script,
            fallbackMessage: "Safari automation failed. Grant Accessibility access in System Settings."
        )
    }

    private func appleScript(
        urlString: String,
        menuName: String,
        otherProfileNames: [String],
        isDefault: Bool
    ) -> String {
        let escapedURL = AppleScriptRunner.escaped(urlString)
        let escapedMenuName = AppleScriptRunner.escaped(menuName)
        let otherPrefixList = AppleScriptRunner.list(otherProfileNames.map { "\($0) — " })
        let isDefaultLiteral = isDefault ? "true" : "false"

        return """
        on run
            set targetURL to "\(escapedURL)"
            set profileMenuName to "\(escapedMenuName)"
            set profilePrefix to profileMenuName & " — "
            set isDefaultTarget to \(isDefaultLiteral)
            set otherPrefixes to \(otherPrefixList)

            tell application "Safari" to activate
            delay 0.4

            -- Reuse an existing window that belongs to this profile so links open
            -- as a new tab instead of a new window. Safari titles windows as
            -- "<Profile> — <Page>", so a named profile is matched by that prefix.
            -- The default profile has no prefix, so it is matched as any window
            -- not owned by one of the other profiles.
            set targetWindow to missing value
            tell application "Safari"
                repeat with w in windows
                    try
                        set wname to (name of w)
                        if wname is missing value then set wname to ""
                        if wname starts with profilePrefix then
                            set targetWindow to w
                            exit repeat
                        else if isDefaultTarget then
                            set matchedOther to false
                            repeat with op in otherPrefixes
                                if wname starts with op then
                                    set matchedOther to true
                                    exit repeat
                                end if
                            end repeat
                            if not matchedOther then
                                set targetWindow to w
                                exit repeat
                            end if
                        end if
                    end try
                end repeat
            end tell

            if targetWindow is not missing value then
                try
                    tell application "Safari"
                        set newTab to make new tab at end of tabs of targetWindow with properties {URL:targetURL}
                        set current tab of targetWindow to newTab
                        set index of targetWindow to 1
                    end tell
                    tell application "Safari" to activate
                    return
                on error
                    -- Reuse failed (e.g. the matched window can't host tabs);
                    -- fall through and open a fresh profile window below.
                    set targetWindow to missing value
                end try
            end if

            -- Open a new window that belongs to the requested profile by clicking
            -- its "New <profile> Window" item. The File menu is reached by
            -- position (menu bar item 3) instead of the localized title "File",
            -- and items are matched by *containing* the profile name, so this
            -- works regardless of the system language and picks the exact
            -- profile (including the default one, e.g. "Personal").
            set didClick to false
            tell application "System Events"
                tell process "Safari"
                    set fileMenu to menu 1 of menu bar item 3 of menu bar 1

                    -- 1) direct items in the File menu
                    repeat with mi in (menu items of fileMenu)
                        try
                            if name of mi contains profileMenuName then
                                click mi
                                set didClick to true
                                exit repeat
                            end if
                        end try
                    end repeat

                    -- 2) one level of submenus (e.g. a "New Window" submenu listing profiles)
                    if not didClick then
                        repeat with mi in (menu items of fileMenu)
                            try
                                if (count of menus of mi) > 0 then
                                    set subMenu to menu 1 of mi
                                    repeat with smi in (menu items of subMenu)
                                        try
                                            if name of smi contains profileMenuName then
                                                click smi
                                                set didClick to true
                                                exit repeat
                                            end if
                                        end try
                                    end repeat
                                end if
                            end try
                            if didClick then exit repeat
                        end repeat
                    end if
                end tell
            end tell

            if not didClick then
                if profileMenuName is "Personal" then
                    -- Only the default profile exists, so there is a plain
                    -- "New Window" instead of a "New Personal Window" item.
                    tell application "Safari" to make new document
                    set didClick to true
                else
                    error "Could not find a Safari menu item for profile \\"" & profileMenuName & "\\". Open Safari and verify the profile name."
                end if
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
}

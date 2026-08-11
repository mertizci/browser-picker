import Foundation

/// Opens links in a chosen Dia profile.
///
/// Dia renders with Chromium but is a native app that never sees Chromium's
/// command line: `--profile-directory` and even the URL itself are dropped, so
/// links are handed over with AppleScript instead.
///
/// * When the target profile already has a window, the link opens as a tab in it.
/// * Otherwise the link is parked in a fresh window, which is then moved into
///   the profile. Dia cannot open a window for a profile on demand, but moving
///   a tab across profiles carries its window over.
struct DiaLauncher {
    func open(url: URL, profile: BrowserProfile, allProfileNames: [String] = []) throws {
        let profileName = targetProfileName(for: profile, allProfileNames: allProfileNames)
        let script = appleScript(
            urlString: url.absoluteString,
            profileName: profileName ?? "",
            otherProfileNames: allProfileNames.filter { $0 != profileName }
        )

        try AppleScriptRunner.run(
            script,
            fallbackMessage: "Dia automation failed. Grant Accessibility access in System Settings."
        )
    }

    /// The profile Dia should end up showing, or `nil` when the link may open
    /// wherever Dia already is: a lone profile needs no switching, and a
    /// synthetic default profile carries no name Dia would recognise.
    private func targetProfileName(for profile: BrowserProfile, allProfileNames: [String]) -> String? {
        guard allProfileNames.count > 1,
              profile.id != BrowserProfile.defaultProfile(for: .dia).id
        else { return nil }

        return profile.internalName ?? profile.displayName
    }

    private func appleScript(
        urlString: String,
        profileName: String,
        otherProfileNames: [String]
    ) -> String {
        """
        on run
            set targetURL to "\(AppleScriptRunner.escaped(urlString))"
            set profileName to "\(AppleScriptRunner.escaped(profileName))"
            set otherProfileNames to \(AppleScriptRunner.list(otherProfileNames))
            set profilePrefix to profileName & ": "

            -- A cold launch restores windows one by one, so wait for the whole
            -- set before concluding that a profile has no window.
            set wasRunning to isRunning()
            tell application "Dia" to activate
            if wasRunning then
                waitForWindow()
            else
                waitForWindowsToSettle()
            end if

            -- No profile to target: the link belongs wherever Dia already is.
            if profileName is "" then
                ensureWindow()
                openLink(targetURL)
                return
            end if

            set windowIndex to windowIndexForProfile(profilePrefix)
            if windowIndex > 1 then
                tell application "System Events" to tell process "Dia"
                    perform action "AXRaise" of window windowIndex
                end tell
                delay 0.4
            end if

            -- Re-read the front window instead of trusting the raise: a
            -- minimized or otherwise unraisable window must not silently
            -- receive the link in the wrong profile.
            if windowIndexForProfile(profilePrefix) is 1 then
                openLink(targetURL)
                return
            end if

            tell application "Dia" to make new window
            delay 0.6
            openLink(targetURL)
            moveActiveTabToProfile(profileName, otherProfileNames)
        end run

        on isRunning()
            tell application "System Events" to return (exists process "Dia")
        end isRunning

        -- Dia restores its windows asynchronously, so a cold launch needs a moment.
        on waitForWindow()
            repeat 60 times
                try
                    tell application "Dia"
                        if (count of windows) > 0 then return true
                    end tell
                end try
                delay 0.25
            end repeat
            return false
        end waitForWindow

        on waitForWindowsToSettle()
            waitForWindow()
            set previousCount to -1
            repeat 12 times
                set currentCount to 0
                try
                    tell application "Dia"
                        set currentCount to count of windows
                    end tell
                end try
                if currentCount > 0 and currentCount is previousCount then return true
                set previousCount to currentCount
                delay 0.4
            end repeat
            return false
        end waitForWindowsToSettle

        on ensureWindow()
            tell application "Dia"
                if (count of windows) is 0 then
                    make new window
                    delay 0.6
                end if
            end tell
        end ensureWindow

        on openLink(targetURL)
            tell application "Dia"
                tell window 1 to make new tab with properties {URL:targetURL}
                delay 0.3
                focus tab (count of tabs of window 1) of window 1
            end tell
        end openLink

        -- Only the accessibility title of a Dia window reveals its profile, as
        -- "<Profile>: <tab title>". Titles are truncated, so match the prefix.
        on windowIndexForProfile(profilePrefix)
            tell application "System Events" to tell process "Dia"
                set windowTitles to name of every window
            end tell
            repeat with i from 1 to (count of windowTitles)
                set windowTitle to item i of windowTitles
                if windowTitle is not missing value then
                    if (windowTitle as string) starts with profilePrefix then return i
                end if
            end repeat
            return 0
        end windowIndexForProfile

        -- The profile list is found by content rather than by menu title: the
        -- only submenu naming several profiles is Dia's "move tab to profile"
        -- list, so this keeps working when menu wording or the language changes,
        -- and never mistakes a bookmark folder that shares a profile's name.
        on moveActiveTabToProfile(profileName, otherProfileNames)
            tell application "System Events" to tell process "Dia"
                repeat with topLevelItem in menu bar items of menu bar 1
                    try
                        repeat with parentItem in menu items of menu 1 of topLevelItem
                            try
                                if (count of menus of parentItem) > 0 then
                                    set entryNames to name of every menu item of menu 1 of parentItem
                                    if my listContains(entryNames, profileName) and my listContainsAny(entryNames, otherProfileNames) then
                                        click (first menu item of menu 1 of parentItem whose name is profileName)
                                        my confirmMoveIfAsked()
                                        return true
                                    end if
                                end if
                            end try
                        end repeat
                    end try
                end repeat
            end tell
            error "Dia does not list a profile named \\"" & profileName & "\\". Open Dia and verify the profile name."
        end moveActiveTabToProfile

        -- Moving a tab between profiles asks for confirmation unless the user
        -- silenced that prompt, and its default button confirms the move.
        on confirmMoveIfAsked()
            repeat 20 times
                tell application "System Events" to tell process "Dia"
                    set sheetCount to 0
                    repeat with w in windows
                        try
                            set sheetCount to sheetCount + (count of sheets of w)
                        end try
                    end repeat
                    if sheetCount > 0 then
                        key code 36
                        return true
                    end if
                end tell
                delay 0.25
            end repeat
            return false
        end confirmMoveIfAsked

        on listContains(values, target)
            repeat with value in values
                try
                    if (value as string) is target then return true
                end try
            end repeat
            return false
        end listContains

        on listContainsAny(values, targets)
            repeat with target in targets
                if listContains(values, target as string) then return true
            end repeat
            return false
        end listContainsAny
        """
    }
}

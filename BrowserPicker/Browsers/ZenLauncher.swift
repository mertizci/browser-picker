import AppKit
import Foundation

/// Opens links in a chosen Zen profile and space.
///
/// Zen takes Gecko's profile switches, so profiles are handled by
/// `GeckoLauncher`. Spaces, however, only exist inside a running window: no
/// command line reaches them. A link always lands in whichever space is open,
/// so the space is switched with AppleScript first and the link handed over
/// afterwards.
struct ZenLauncher {
    private let geckoLauncher = GeckoLauncher()

    func open(url: URL, profile: BrowserProfile, space: BrowserSpace?) throws {
        // A lone space is always the open one, so there is nothing to switch.
        guard let space, profile.spaces.count > 1 else {
            try geckoLauncher.launch(url: url, profile: profile)
            return
        }

        // Switching needs a window, and a cold launch has none: start Zen
        // without the link so it is not opened in the space Zen restores into.
        if !isRunning {
            try geckoLauncher.launch(url: nil, profile: profile)
        }

        try switchTo(space, in: profile)
        try geckoLauncher.launch(url: url, profile: profile)
    }

    private var isRunning: Bool {
        !NSRunningApplication
            .runningApplications(withBundleIdentifier: BrowserKind.zen.bundleIdentifier)
            .isEmpty
    }

    private func switchTo(_ space: BrowserSpace, in profile: BrowserProfile) throws {
        try AppleScriptRunner.run(
            appleScript(spaceName: space.name, knownSpaceNames: profile.spaces.map(\.name)),
            fallbackMessage: "Zen automation failed. Grant Accessibility access in System Settings."
        )
    }

    private func appleScript(spaceName: String, knownSpaceNames: [String]) -> String {
        """
        on run
            set targetSpace to "\(AppleScriptRunner.escaped(spaceName))"
            set knownSpaces to \(AppleScriptRunner.list(knownSpaceNames))

            -- Zen is only ever addressed through the accessibility API: an
            -- Apple Event sent while it is starting up hangs until the event
            -- times out, two minutes later.
            if not waitForWindow() then return "no-window"
            try
                tell application "System Events" to set frontmost of my zenProcess() to true
            end try
            delay 0.3

            return openSpace(targetSpace, knownSpaces)
        end run

        -- Clicking is verified rather than trusted: a click that lands while Zen
        -- is still restoring its session is undone by the restore, so the menu
        -- is read back and the click repeated until the space stays open.
        --
        -- Zen leaves the open space out of the menu, so the target being absent
        -- means it is open — but only once the menu is complete, which is when
        -- it names one space less than the profile has.
        on openSpace(targetSpace, knownSpaces)
            set expected to (count of knownSpaces) - 1
            set attempts to 0
            repeat 24 times
                set menuIndex to spacesMenuIndex(knownSpaces)
                if menuIndex > 0 then
                    set entryNames to spaceMenuEntries(menuIndex)
                    if my countKnown(entryNames, knownSpaces) is expected then
                        if not my listContains(entryNames, targetSpace) then return "open"
                        if attempts > 0 then dismissBlockingDialog()
                        try
                            tell application "System Events"
                                click menu item targetSpace of my spacesMenu(menuIndex)
                            end tell
                        end try
                        set attempts to attempts + 1
                        delay 0.7
                    else
                        delay 0.4
                    end if
                else
                    delay 0.4
                end if
            end repeat
            return "not-switched"
        end openSpace

        -- A modal Zen draws inside its own window — the prompt asking to become
        -- the default browser, for one — swallows the space switch, and being
        -- web content it is invisible to accessibility. Escape closes it without
        -- answering it.
        on dismissBlockingDialog()
            try
                tell application "System Events" to key code 53
            end try
            delay 0.4
        end dismissBlockingDialog

        on spacesMenu(menuIndex)
            tell application "System Events"
                return menu 1 of menu bar item menuIndex of menu bar 1 of my zenProcess()
            end tell
        end spacesMenu

        on spaceMenuEntries(menuIndex)
            try
                tell application "System Events"
                    return name of every menu item of my spacesMenu(menuIndex)
                end tell
            on error
                return {}
            end try
        end spaceMenuEntries

        on zenProcess()
            tell application "System Events"
                return first application process whose bundle identifier is "\(BrowserKind.zen.bundleIdentifier)"
            end tell
        end zenProcess

        -- Zen restores its windows asynchronously, so a cold launch needs a moment.
        on waitForWindow()
            repeat 120 times
                try
                    tell application "System Events"
                        if (count of windows of my zenProcess()) > 0 then return true
                    end tell
                end try
                delay 0.25
            end repeat
            return false
        end waitForWindow

        -- The space list is found by content rather than by menu title, so this
        -- keeps working when Zen is localised: the menu naming the most known
        -- spaces is Zen's space switcher, never a bookmark folder that happens
        -- to share one space's name.
        on spacesMenuIndex(knownSpaces)
            set bestIndex to 0
            set bestScore to 0
            tell application "System Events"
                set barItems to menu bar items of menu bar 1 of my zenProcess()
                repeat with i from 1 to (count of barItems)
                    try
                        set entryNames to name of every menu item of menu 1 of item i of barItems
                        set score to my countKnown(entryNames, knownSpaces)
                        if score > bestScore then
                            set bestScore to score
                            set bestIndex to i
                        end if
                    end try
                end repeat
            end tell
            return bestIndex
        end spacesMenuIndex

        on listContains(entryNames, target)
            repeat with entryName in entryNames
                try
                    if (entryName as string) is target then return true
                end try
            end repeat
            return false
        end listContains

        on countKnown(entryNames, knownSpaces)
            set total to 0
            repeat with entryName in entryNames
                try
                    set entryText to entryName as string
                    repeat with knownSpace in knownSpaces
                        if entryText is (knownSpace as string) then
                            set total to total + 1
                            exit repeat
                        end if
                    end repeat
                end try
            end repeat
            return total
        end countKnown
        """
    }
}

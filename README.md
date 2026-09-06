<p align="center">
<img src="https://raw.githubusercontent.com/mertizci/browser-picker/refs/heads/main/BrowserPicker/Assets.xcassets/AppIcon.appiconset/AppIcon-128.png" width="128" />
</p>

<h1 align="center">Browser Picker</h1>

<p align="center">
A native macOS menu bar app that becomes your <b>default browser</b> and sends every link to the right <b>browser <em>and</em> profile</b> — automatically with rules, or with a quick picker.
</p>

<p align="center">
<img src="https://img.shields.io/badge/macOS-14.0%2B-000000?logo=apple&logoColor=white" alt="macOS 14.0+" />
<img src="https://img.shields.io/badge/Apple%20Silicon%20%2B%20Intel-Universal-555555" alt="Universal binary" />
<img src="https://img.shields.io/badge/Signed%20%26%20Notarized-Apple-brightgreen" alt="Signed & notarized" />
<a href="https://github.com/mertizci/browser-picker/releases/latest"><img src="https://img.shields.io/github/v/release/mertizci/browser-picker?label=download&color=blue" alt="Latest release" /></a>
<a href="https://www.paypal.com/donate/?hosted_button_id=8BKTHWAHUPWPG"><img src="https://img.shields.io/badge/Donate-PayPal-0070ba?logo=paypal&logoColor=white" alt="Donate via PayPal" /></a>
</p>

---

## Why Browser Picker?

Juggling a personal Chrome, a work Chrome profile, and Firefox for clients? Stop opening links in the wrong place. Browser Picker routes each link to the exact **browser and profile** you want — so work links land in your work profile, personal links in your personal one, automatically.

## Install

> A **universal build** that runs natively on both Apple Silicon and Intel Macs (macOS 14.0+). Every release is signed with a Developer ID certificate and **notarized by Apple**, so it opens without Gatekeeper warnings.

### 1. DMG — recommended

1. Download `BrowserPicker-X.Y.Z.dmg` from the **[latest release](https://github.com/mertizci/browser-picker/releases/latest)**.
2. Open the DMG and drag **Browser Picker** into your **Applications** folder.
3. Launch it from Applications — the icon appears in your menu bar.

### 2. Homebrew

```bash
brew install --cask mertizci/tap/browser-picker
```

## Features

- 🎯 **Browser + profile routing** — not just "open in Chrome", but "open in Chrome → *Work*" or "Firefox → *Client A*". Each link lands in the right account, ready to go.
- 🧭 **Menu bar control** — pick the active browser + profile (Safari, Chrome, Edge, Brave, Vivaldi, Dia, Firefox, Zen) in one click.
- 🗂️ **Zen spaces** — Zen routes one level deeper, listed the way Zen nests it: spaces grouped under the container Zen calls their *Profile*. Send a link to one space, or leave it in whichever space is open.
- 🔀 **Automatic routing rules** — match links by *URL contains*, *host equals*, or *host suffix*. First match wins; reorder by dragging.
- 🪃 **Two fallback modes** when no rule matches:
  - **Silent** — open in your current menu bar selection.
  - **Picker** — prompt for the browser/profile each time.
- 👤 **Profile discovery**
  - Chromium browsers (Chrome, Edge, Brave, Vivaldi, Dia) — from each browser's `Local State`.
  - Gecko browsers (Firefox, Zen) — from `profiles.ini` and **Profile Groups** (selectable profile names).
  - Safari — from `SafariTabs.db`, with a **menu scan** fallback.
  - Zen spaces — from the profile's `zen-sessions.jsonlz4` session file.
  - Dia ignores command-line arguments, so links are handed to it by automation: an existing window of the target profile is reused, otherwise the link is moved into that profile.
  - Zen spaces exist only in a running window, so a space-bound link switches Zen to that space through its Spaces menu and is handed over afterwards. Spaces are picked by name, so two spaces sharing a name are indistinguishable — rename one in Zen.
  - Zen's space settings label a space's container (*Personal*, *Work*, …) its "Profile", so containers are the heading a space is listed under — routing to a space lands in that container too. A container with no space of its own is left out, since a link can only be sent to a space. Running two Zen profiles side by side is a Gecko limitation: links then follow the instance that answers, as they do with Firefox.
- 🧑‍🏫 **Guided onboarding** that requests and live-tracks the required permissions.
- ✨ **Polished UI** — window-style menu bar popover, redesigned Settings, rule editor with live preview, built-in **FAQ** and **About**.
- 🖼️ Native browser icons from installed apps, with Simple Icons SVG fallback.

## Permissions

| Permission | Why it's needed |
| --- | --- |
| **Accessibility** | Drive Safari's *File → New … Window* menu, Dia's profile menu, and Zen's *Spaces* menu, to open links in a specific profile or space. |
| **Full Disk Access** | Read Safari profile names from the protected `SafariTabs.db`. |

On first launch an onboarding window walks you through both. After granting **Accessibility**, **quit and reopen** the app — macOS only applies that permission on a fresh launch.

## Requirements

**To run:**

- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel — ships as a universal binary

**To build from source:**

- Xcode 15+
- An Apple Development signing certificate (a stable code signature keeps the Accessibility grant across rebuilds)

## Build

```bash
brew install xcodegen   # once
xcodegen generate
xcodebuild -scheme BrowserPicker -destination 'platform=macOS' -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/BrowserPicker-*/Build/Products/Debug/BrowserPicker.app
```

Or open `BrowserPicker.xcodeproj` in Xcode and press ⌘R.

> Signing is configured in `project.yml` (`CODE_SIGN_IDENTITY`). Ad-hoc signatures change on every build and break the Accessibility grant, so a real "Apple Development" identity is recommended.

## Setup

1. Launch Browser Picker — the icon appears in the menu bar.
2. Complete the onboarding (grant Accessibility + Full Disk Access).
3. Choose **Set as Default Browser…** from the menu bar.
4. Pick your default browser and profile.
5. Open **Settings → Rules** to add routing rules (e.g. *URL contains `r2o` → Firefox · Work*).

## Configuration

Settings are stored as JSON at:

```
~/Library/Application Support/BrowserPicker/config.json
```

## Project structure

```
BrowserPicker/
├── BrowserPickerApp.swift           # App entry, AppDelegate, URL handling
├── Core/                            # Models, SettingsStore, RuleEngine, URLRouter
├── Browsers/
│   ├── BrowserLauncher.swift        # Chromium/Gecko/Safari/Dia/Zen dispatch
│   ├── SafariLauncher.swift         # AppleScript profile targeting
│   ├── ZenLauncher.swift            # Gecko profile launch + space switching
│   ├── AutomationPermissionService  # PermissionMonitor (Accessibility + FDA)
│   └── ProfileDiscovery/            # Per-browser profile discovery
├── UI/                              # Menu bar, Settings, Rules, Onboarding, FAQ, About
└── Resources/                       # faq.html, browser SVG icons
```

## Test

```bash
# After making Browser Picker the default browser:
open "https://example.com"
```

## Troubleshooting

- **Accessibility shows "not granted" after granting** — quit and reopen the app (use *Quit & Reopen*); macOS applies it only on a fresh launch.
- **Safari profiles missing** — grant Full Disk Access, or open Safari and use *Scan Safari Profiles* in Settings → Browsers.
- **Zen spaces missing** — Zen writes its session file while running; open the profile in Zen once, then use *Refresh Profiles*.
- **App icon looks blank** — quit/reopen; if it persists, log out and back in to clear the macOS icon cache.

## Contact

Developed by **Mert IZCI** — [mertizci@gmail.com](mailto:mertizci@gmail.com).

## License

Browser Picker application code is provided as-is. Browser SVG fallbacks use [Simple Icons](https://simpleicons.org/) (MIT). See `BrowserPicker/Resources/Icons/browsers/ATTRIBUTION.md`.

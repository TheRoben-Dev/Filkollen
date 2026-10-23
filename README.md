# Filkollen

A friendly macOS cleaner, written in SwiftUI. It finds junk, shows you exactly what it found, and moves it to the Trash only after you review it. It also scans for known malware.

- **macOS 13 Ventura or later**, Apple Silicon and Intel
- Direct distribution (Developer ID + notarization). Not sandboxed, so it can't go on the Mac App Store.
- Needs **Full Disk Access** to see most of `~/Library`

## Features

| Module | What it finds | What happens |
|---|---|---|
| System Junk | `~/Library/Caches/*`, `~/Library/Logs/*`, Xcode DerivedData, temp files older than 3 days | Review, then Move to Trash |
| App Leftovers | Support files named after a bundle ID (`com.vendor.app`) whose app isn't installed: Application Support, Caches, Preferences, Containers, Group Containers, Saved State, HTTPStorages, WebKit, Cookies, Logs, LaunchAgents | Review, then Move to Trash |
| Duplicate Photos | Byte-identical images in Pictures, Desktop, Downloads, Documents. Oldest copy is marked **KEEP**. | Review, then Move to Trash |
| Large & Old Files | Files over 500 MB (adjustable) in your home folder, grouped by folder | Review, then Move to Trash |
| Malware Scan | Files whose SHA-256 is in abuse.ch **MalwareBazaar**, plus optional **ClamAV** signature scan | Quarantine (restorable) or Delete Permanently |

Maintenance:

| Page | What it does |
|---|---|
| System Overview | Live disk, memory and CPU load, uptime, model, Trash size with Empty Trash (confirmed), shortcuts to Activity Monitor, Disk Utility, Storage and Software Update |
| Startup Items | Lists your launch agents plus system agents and daemons, flags ones whose app is gone, and removes your own agents (unload + Trash) |
| App Updates | One list of updates from Sparkle appcasts (apps that update themselves), Homebrew formulae and casks (`brew outdated`, upgrade in place), the Mac App Store (via `mas`) and macOS (`softwareupdate`) |

### Menu bar and background mode

A menu bar icon opens a panel with disk, memory and CPU bars, the last junk result, protection and update status, and one-click Smart Scan, Malware Scan, Check for Updates and Empty Trash (two clicks, it's permanent).

When **Keep running in the menu bar** is on (default), closing the window keeps Filkollen running with no Dock icon; the menu bar icon or opening the app again brings the window back. **Open at login** (Settings › General, uses `SMAppService`) starts it hidden in the menu bar. While running it can, on a schedule you pick:
- run a Smart Scan (looks only; nothing is cleaned without your review) and notify you when there's over 500 MB to clean
- refresh the threat database weekly when an Auth-Key is set
- check for app updates daily and notify you

Settings has General, Cleanup (temp file age, large-file size, excluded folders), Protection and Updates tabs.

Safety rails:
- Junk always goes to the Trash. Nothing is deleted without a review sheet.
- `SafetyGuard` refuses anything outside your home folder or temp, top-level folders like `~/Library` itself, iCloud Drive, Keychains and any `.photoslibrary`.
- `com.apple.*` items are never treated as leftovers.
- The Photos library is never scanned for duplicates. Deleting files inside it corrupts it; use Photos' own Duplicates album.
- Malware deletion skips the Trash on purpose (malware in the Trash can still run) and asks for confirmation first.

## Build

```sh
brew install xcodegen
cd Filkollen
xcodegen generate          # creates Filkollen.xcodeproj from project.yml
open Filkollen.xcodeproj
```

In Xcode, set your Team under Signing & Capabilities, then Run (⌘R).

On first launch the onboarding screen explains Full Disk Access, opens the right System Settings pane, and notices automatically when it's granted. A debug build gets its own TCC entry, so grant access to the build from Xcode's DerivedData folder (use "Show Filkollen in Finder").

### Releasing

1. Archive with a **Developer ID Application** certificate (Hardened Runtime is already on).
2. Notarize: `xcrun notarytool submit Filkollen.zip --keychain-profile <profile> --wait`
3. Staple: `xcrun stapler staple Filkollen.app`, then ship as a DMG or ZIP.

## Malware scanning

**MalwareBazaar (built in).** Needs a free abuse.ch Auth-Key (https://auth.abuse.ch/), pasted into the Malware Scan page or Settings. "Update" downloads the authenticated CSV exports from `mb-api.abuse.ch/v2/files/exports/<key>/` (full list + last 48 h; the old `bazaar.abuse.ch/export/txt/` URLs now return 410 Gone) and stores it as a sorted binary table in `~/Library/Application Support/Filkollen/`. Matching is entirely offline, so no file hashes leave the Mac. It scans Downloads, Desktop, Documents, `/Applications`, `~/Applications`, Application Support, LaunchAgents/Daemons, `/Users/Shared` and `/tmp`, hashing only Mach-O binaries, scripts and risky file types (dmg, pkg, zip, exe, macro docs and so on) up to 256 MB.

Tradeoff: exact-hash matching has essentially no false positives, but it only catches files identical to a known sample. Repacked or brand-new variants slip through.

**ClamAV (optional).** If `clamscan` is installed (`brew install clamav`, then run `freshclam` once), Filkollen also runs a signature scan, which catches variants. It's slower and occasionally flags clean files, which is why quarantine is the default action. Bundling libclamav was skipped for v1 because of its size and GPL license.

Quarantined files live in `~/Library/Application Support/Filkollen/Quarantine/`, permissions set to read-only with no execute bit, with a `manifest.json` that makes restore possible.

## Project layout

```
Filkollen/
  App/          FilkollenApp, AppDelegate (menu bar mode + BackgroundScheduler),
                AppModel (cleanup), ProtectionModel (malware), UpdatesModel
  Models/       JunkCategory, JunkItem, Preferences (settings keys, exclusions)
  Services/     FullDiskAccess, CacheScanner, LeftoverScanner, DuplicatePhotoScanner,
                LargeFileScanner, Cleaner, SafetyGuard, FileSizer, Shell
    Protection/ ThreatDatabase, MalwareScanner, ClamAV, Quarantine, Threat
    Updates/    AppUpdate, SparkleChecker, PackageCheckers (Homebrew, mas, softwareupdate)
    System/     SystemInfo, StartupItems, LoginItem, Notifier
  Views/        RootView, MenuBarView, OnboardingView, SmartScanView, CategoryDetailView,
                ReviewSheet, ProtectionView, UpdatesView, SystemOverviewView,
                StartupItemsView, SettingsView, Theme, Components/
  Resources/    Assets (app icon, accent color)
project.yml     XcodeGen spec (macOS 13, no sandbox, hardened runtime)
```

## Known limitations / next steps

- Leftover detection only matches bundle-ID–named entries. Plain names like `~/Library/Application Support/Spotify` are ignored to avoid false positives.
- Duplicate photos are exact matches only. Visually similar shots (resized, re-encoded) would need perceptual hashing (Vision `VNFeaturePrintObservation`).
- System-wide locations (`/Library/Caches`, `/private/var/log`) need admin rights through a privileged helper (SMAppService), not included yet.
- Filkollen itself has no Sparkle auto-update yet.
- Open at login needs a signed build; an unsigned debug build may be refused by `SMAppService`.
- Startup items in `/Library` need admin rights to change, so they're shown but not removable.

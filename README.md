# Filkollen

A friendly macOS cleaner, written in SwiftUI. It finds junk, shows you exactly what it found, and moves it to the Trash only after you review it. It also scans for known malware.

- **macOS 13 Ventura or later**, Apple Silicon and Intel
- Direct distribution (Developer ID + notarization). Not sandboxed, so it can't go on the Mac App Store.
- Needs **Full Disk Access** to see most of `~/Library`

## Features

| Module | What it finds | What happens |
|---|---|---|
| System Junk | `~/Library/Caches/*`, `~/Library/Logs/*`, temp files older than 3 days. Running apps' caches are shown as *In use* and not selected | Review, then Move to Trash |
| App Leftovers | Support files named after a bundle ID whose app isn't installed (Application Support, Caches, Preferences, Containers, Group Containers, Saved State, HTTPStorages, WebKit, Cookies, Logs, LaunchAgents). Optionally plain-named folders, with a confidence badge | Review, then Move to Trash |
| Duplicate Photos | Byte-identical images in Pictures, Desktop, Downloads, Documents. Keeps the copy next to its Live Photo video or RAW original, else the oldest | Review, then Move to Trash |
| Duplicate Files | Identical non-image files of 1 MB or more in Desktop, Downloads, Documents, Movies, Music. Nothing pre-selected | Review, then Move to Trash |
| Large & Old Files | Files over 500 MB, or not opened for 6 months to 2 years (adjustable), grouped by kind. Never pre-selected | Review, then Move to Trash |
| Developer Junk | Xcode DerivedData, Archives, device support, simulator caches, SwiftPM, npm/yarn/pnpm, pip, Cargo, Gradle, CocoaPods, Go | Review, then Move to Trash |
| Old Installers | DMG, PKG and ZIP installers in Downloads for apps you've already installed | Review, then Move to Trash |
| iOS Backups & Firmware | Finder's device backups (name, date) and leftover IPSW files. Never pre-selected | Review, then Move to Trash |
| Browser & Mail Caches | Web caches for Chrome, Edge, Brave, Arc, Firefox and Safari, and Mail's opened-attachment copies. Never history, cookies, passwords or mail. The browser must be closed | Review, then Move to Trash |
| App Uninstaller | Everything an app keeps in your home folder. Apple apps are refused | Review, then Move to Trash; apps in `/Applications` you drag to the Trash in Finder |
| Malware Scan | Files whose SHA-256 is in abuse.ch **MalwareBazaar**, plus optional **ClamAV**. App Trust tab shows who signed each app | Quarantine (restorable) or Delete Permanently after confirmation |

Every cleanup lands in **History**, where Undo and Put Back move items back from the Trash. History can also permanently delete just Filkollen's items from the Trash, leaving everything else there.

Maintenance:

| Page | What it does |
|---|---|
| System Overview | Live disk, memory and CPU load, uptime, model, Trash size with Empty Trash (confirmed), shortcuts to Activity Monitor, Disk Utility, Storage and Software Update |
| Startup Items | Your launch agents plus system agents and daemons: what each runs, its signature, scripts and unusual locations flagged, broken ones marked; removes your own agents (unload + Trash) |
| Time Machine Snapshots | Lists local snapshots and explains them. Nothing is deleted |
| Disk Usage | Treemap of your home folder; click to drill in, right-click to reveal. Look only |
| App Updates | Updates from Sparkle appcasts, Homebrew, the Mac App Store (via `mas`) and macOS (`softwareupdate`) |

### Menu bar and background mode

A menu bar icon opens a panel with disk, memory and CPU bars, the last junk result, protection and update status, and one-click Smart Scan, Malware Scan, Check for Updates and Empty Trash (two clicks, it's permanent).

When **Keep running in the menu bar** is on (default), closing the window keeps Filkollen running with no Dock icon. **Open at login** (Settings › General, uses `SMAppService`) starts it hidden in the menu bar. While running it can, on a schedule you pick:
- run a Smart Scan (looks only; nothing is cleaned without your review) and notify you when there's over 500 MB to clean
- refresh the threat database weekly when an Auth-Key is set
- check for app updates daily and notify you
- check new files in Downloads against the threat database (off by default)

Shortcuts and Spotlight get **Run Smart Scan** and **Scan for Malware**. Both open Filkollen; nothing is cleaned without review. Filkollen is available in English and Swedish.

### Safety rails

The full rules, and why, are in [docs/SAFETY.md](docs/SAFETY.md). In short:
- Junk always goes to the Trash after a review sheet. Only malware may skip the Trash, and only after confirmation.
- `SafetyGuard` refuses anything outside your home folder and per-user temp, resolves symlinks and firmlinks first, and re-checks every item right before it moves.
- Never touched: `com.apple.*` (except two Safari cache folders and Mail's attachment downloads, approved explicitly), Keychains, iCloud Drive and CloudStorage, any Photos library, Mail's data store, the inside of app bundles. There's no "language files" cleaner because removing localizations breaks code signatures.
- No network except MalwareBazaar updates (and Sparkle for Filkollen itself once you configure it). No telemetry.

## Build

```sh
brew install xcodegen
cd Filkollen
xcodegen generate          # creates Filkollen.xcodeproj from project.yml
open Filkollen.xcodeproj
```

In Xcode, set your Team under Signing & Capabilities, then Run (⌘R).

On first launch the onboarding screen explains Full Disk Access, opens the right System Settings pane, and notices automatically when it's granted. A debug build gets its own TCC entry, so grant access to the build from Xcode's DerivedData folder (use "Show Filkollen in Finder").

### Tests and releasing

`xcodebuild test -project Filkollen.xcodeproj -scheme Filkollen -destination 'platform=macOS'` runs the unit tests (CI does the same on every push). Releases are built with `scripts/release.sh`; see [docs/RELEASING.md](docs/RELEASING.md) for signing, notarization and Sparkle setup.

## Malware scanning

**MalwareBazaar (built in).** Needs a free abuse.ch Auth-Key (https://auth.abuse.ch/), pasted into the Malware Scan page or Settings. "Update" downloads the authenticated CSV exports from `mb-api.abuse.ch/v2/files/exports/<key>/` (full list + last 48 h; the old `bazaar.abuse.ch/export/txt/` URLs now return 410 Gone) and stores it as a sorted binary table in `~/Library/Application Support/Filkollen/`. Matching is entirely offline, so no file hashes leave the Mac. It scans Downloads, Desktop, Documents, `/Applications`, `~/Applications`, Application Support, LaunchAgents/Daemons, `/Users/Shared` and `/tmp`, hashing only Mach-O binaries, scripts and risky file types (dmg, pkg, zip, exe, macro docs and so on) up to 256 MB.

Tradeoff: exact-hash matching has essentially no false positives, but it only catches files identical to a known sample. Repacked or brand-new variants slip through.

**ClamAV (optional).** If `clamscan` is installed (`brew install clamav`, then run `freshclam` once), Filkollen also runs a signature scan, which catches variants. It's slower and occasionally flags clean files, which is why quarantine is the default action. Bundling libclamav was skipped for v1 because of its size and GPL license.

Quarantined files live in `~/Library/Application Support/Filkollen/Quarantine/`, permissions set to read-only with no execute bit, with a `manifest.json` (original path, engine, SHA-256) that makes restore possible. The Quarantine tab can export that manifest as a report and delete items older than 30 days.

The local database is integrity-checked on load (whole digests, sorted, checksum), and a download that's suddenly much smaller than the current database is rejected as truncated. ClamAV signatures and the MalwareBazaar list both show their age and warn after a week.

## Project layout and docs

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for modules and data flow, [docs/SAFETY.md](docs/SAFETY.md) for the deletion rules, [docs/PERF.md](docs/PERF.md) for scan timings, [docs/ROADMAP.md](docs/ROADMAP.md) for what's done and left, and [CONTRIBUTING.md](CONTRIBUTING.md) before adding a cleanup category.

## Known limitations / next steps

- System-wide locations (`/Library/Caches`, `/Library/Logs`) need a privileged helper; the design is proposed in [docs/HELPER.md](docs/HELPER.md) and not built.
- Duplicate photos are exact matches only. Visually similar shots would need Vision feature prints.
- Swedish covers fixed text; sentences with numbers in them are still English.
- Open at login and Sparkle need a Developer ID–signed build.
- Startup items in `/Library` need admin rights to change, so they're shown but not removable.

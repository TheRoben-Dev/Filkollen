# Changelog

All notable changes to Filkollen. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Safety
- `SafetyGuard` rewritten: paths are resolved with `realpath`, the Data-volume firmlink is stripped, and comparisons are NFC + case-insensitive. Both a symlink's location and its target are checked.
- Now refused: anything `com.apple.*`, the inside of app bundles, Mail/Messages/Safari data, CloudStorage, Autosave Information, `~/.Trash`, `~/.ssh`, `~/.gnupg`, Filkollen's own data, and direct children of `~/Library`. Temp access is limited to the per-user `T/` folder.
- Scan results are screened through `SafetyGuard`, and every item is re-checked right before it moves; an item whose location changed since the scan is refused.
- Narrow, tested exceptions (approved 2026-10-23): Safari's two web-cache folders, Mail's attachment-download folder, and Finder's per-device iOS backup folders. See `docs/SAFETY.md`.
- Put Back only restores into places `SafetyGuard` allows and never overwrites; quarantine delete refuses manifest entries outside the quarantine folder.

### Added
- Unit test target (`FilkollenTests`) with fixture-based tests for `SafetyGuard`, the Cleaner, every scanner, sizing and the hash cache. CI runs them on every push.
- Caches of running apps are listed but unselected and marked *In use*.
- Done screen lists each item that couldn't be moved and why (permission denied, in use, vanished).
- Sidebar says when Full Disk Access was turned off after being granted.
- `os.Logger` logging per module and Help › Export Diagnostics….
- Honest sizes: hard links counted once, symlinks count as nothing, and APFS clones are excluded from "space you'll get back". The UI says space returns once the Trash is emptied.
- Live scan progress with items scanned and items per second.
- New cleanup categories: **Developer Junk** (Xcode archives, device support, simulator caches, SwiftPM, npm/yarn/pnpm, pip, Cargo, Gradle, CocoaPods, Go), **Old Installers** (DMG/PKG/ZIP in Downloads for apps you've installed), **iOS Backups & Firmware** (never pre-selected), **Browser & Mail Caches** (Chrome, Edge, Brave, Arc, Firefox, Safari, Mail Downloads; never history, cookies, passwords or mail) and **Duplicate Files** (any non-image file of 1 MB or more; nothing pre-selected).
- **Large & Old Files**: also lists files not opened for 6 months to 2 years, grouped by kind, with Quick Look.
- **App Leftovers**: optional plain-name matching (`Application Support/Spotify`) with a confidence badge; low-confidence matches are never pre-selected.
- **Duplicate Photos** keep the copy that sits next to its Live Photo video or RAW original.
- **App Uninstaller**: pick or drop an app, see every support file it keeps in your home folder, review, and move them to the Trash. Apple apps are refused; apps outside your home folder are removed by you in Finder.
- **History** with Undo and Put Back for every cleanup and uninstall, a monthly chart, and a scoped "Empty Filkollen's Items from Trash" that never touches anything else in the Trash.
- **Disk Usage**: a treemap of what takes space in your home folder (look only).
- **Time Machine Snapshots** page explaining local snapshots (informational; nothing is deleted).
- Right-click **Always Ignore** for an item or its folder, and Quick Look on every result row.
- Review sheet: filter, sort, untick items in place, Quick Look and Show in Finder.
- Protection: **App Trust** tab (who signed each app, checked offline), Startup Items show what each agent runs, its signature, and flag scripts and odd locations, an optional **Downloads watcher** (off by default; notifies, never moves files), threat-database integrity checks, stale-database and ClamAV signature-age warnings, and quarantine report export, SHA-256 per item and "delete older than 30 days".
- App Intents: Run Smart Scan and Scan for Malware from Shortcuts and Spotlight (they open the app; nothing is cleaned without review).
- Swedish translation (String Catalog).
- About panel; `scripts/bump-version.sh`, `scripts/release.sh` (Developer ID, notarize, staple, DMG), SwiftLint/SwiftFormat config and an optional pre-commit hook; `docs/RELEASING.md`.
- Sparkle 2 for Filkollen's own updates, dormant until an appcast URL and public key are configured.
- VoiceOver labels on icon buttons and checkboxes; the scan ring respects Reduce Motion.

### Changed
- Smart Scan categories run concurrently; cache folders are measured in parallel.
- Duplicate photos are matched size → first 64 KB → last 64 KB → full SHA-256, with hashes cached between scans.
- Builds cleanly with `SWIFT_STRICT_CONCURRENCY=complete`.
- Filkollen never runs `freshclam` itself (it only tells you to), and code-signature checks never go online, so MalwareBazaar stays the only network destination (plus Sparkle once configured).

### Fixed
- Stop now really stops a scan, and a cancelled scan can't overwrite a newer one.
- Scheduled Smart Scans no longer start while you're reviewing results.
- Large & Old Files grouping when the home folder resolves through `/private`.

## [0.1.0] - 2026-10-23
- First version: System Junk, App Leftovers, Duplicate Photos, Malware Scan (MalwareBazaar + ClamAV), quarantine, menu bar extra, background scans, App Updates, System Overview, Startup Items, Large & Old Files.

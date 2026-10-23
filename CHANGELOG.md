# Changelog

All notable changes to Filkollen. Format based on [Keep a Changelog](https://keepachangelog.com/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

### Safety
- `SafetyGuard` rewritten: paths are resolved with `realpath`, the Data-volume firmlink is stripped, and comparisons are NFC + case-insensitive. Both a symlink's location and its target are checked.
- Now refused: anything `com.apple.*`, the inside of app bundles, Mail/Messages/Safari data, CloudStorage, Autosave Information, `~/.Trash`, `~/.ssh`, `~/.gnupg`, Filkollen's own data, and direct children of `~/Library`. Temp access is limited to the per-user `T/` folder.
- Scan results are screened through `SafetyGuard`, and every item is re-checked right before it moves; an item whose location changed since the scan is refused.

### Added
- Unit test target (`FilkollenTests`) with fixture-based tests for `SafetyGuard`, the Cleaner, every scanner, sizing and the hash cache. CI runs them on every push.
- Caches of running apps are listed but unselected and marked *In use*.
- Done screen lists each item that couldn't be moved and why (permission denied, in use, vanished).
- Sidebar says when Full Disk Access was turned off after being granted.
- `os.Logger` logging per module and Help › Export Diagnostics….
- Honest sizes: hard links counted once, symlinks count as nothing, and APFS clones are excluded from "space you'll get back". The UI says space returns once the Trash is emptied.
- Live scan progress with items scanned and items per second.

### Changed
- Smart Scan categories run concurrently; cache folders are measured in parallel.
- Duplicate photos are matched size → first 64 KB → last 64 KB → full SHA-256, with hashes cached between scans.

### Fixed
- Stop now really stops a scan, and a cancelled scan can't overwrite a newer one.
- Scheduled Smart Scans no longer start while you're reviewing results.
- Large & Old Files grouping when the home folder resolves through `/private`.

## [0.1.0] - 2026-10-23
- First version: System Junk, App Leftovers, Duplicate Photos, Malware Scan (MalwareBazaar + ClamAV), quarantine, menu bar extra, background scans, App Updates, System Overview, Startup Items, Large & Old Files.

# Filkollen audit

Baseline: `7d1b4b9` (PR #2 `feature/menubar-updaters`, stacked on PR #1 `fix/ci-xcode16`). Audited 2026-10-23 before any backlog changes.

About 4,900 lines of Swift in 45 files. One app target, no test target, no SwiftPM dependencies. Built by XcodeGen from `project.yml` (macOS 13.0, Swift 5.9 language mode, Hardened Runtime, sandbox off). CI builds Debug on `macos-15` / Xcode 16 and runs no tests.

## 1. Architecture and data flow

```
FilkollenApp (Window "main", MenuBarExtra, Settings)
 └─ AppDelegate (owns the models, Dock/menu-bar behaviour, BackgroundScheduler)
     ├─ AppModel          @MainActor  cleanup state: phase, results[JunkCategory]
     │    scan() ──Task.detached──▶ CacheScanner / LeftoverScanner /
     │                              DuplicatePhotoScanner / LargeFileScanner
     │                              (sync, FileManager.default, hardcoded ~)
     │         ◀── [JunkItem] ── filtered through Exclusions (Settings)
     │    ReviewSheet ─▶ cleanSelected() ──Task.detached──▶ Cleaner.moveToTrash
     │                                                     └─ SafetyGuard.isAllowed (per item)
     ├─ ProtectionModel   @MainActor  malware state
     │    updateDatabase() ─▶ ThreatDatabase.update (URLSession, abuse.ch Auth-Key)
     │    scan() ──Task.detached──▶ MalwareScanner (walk → HashCache → concurrentPerform SHA-256
     │                              → binary search) + ClamAV (clamscan subprocess)
     │    quarantine / delete ─▶ Quarantine (move + chmod 0400 + manifest.json)
     └─ UpdatesModel      @MainActor  Sparkle appcasts, Homebrew, mas, softwareupdate
          (TaskGroup over sources, Shell.run subprocesses)
```

- Models: `JunkCategory` (4 cases; Smart Scan covers 3), `JunkItem` (URL-identified, `size`, `group`, `isKeeper`), `Threat`, `Quarantine.Entry`, `Pref`/`Exclusions` (UserDefaults keys).
- Views read models through `@EnvironmentObject`. `CategoryResult` totals are recomputed on every access (`reduce` over items).
- Persistent state: UserDefaults (prefs, Auth-Key), `~/Library/Application Support/Filkollen/` (threat table `.bin`, `hash-cache.plist`, `Quarantine/manifest.json`).

## 2. Concurrency model

- All three models are `@MainActor final class … ObservableObject`. Work is pushed off the main actor with `Task.detached` around **synchronous** scanner calls.
- Scanners are value types using `FileManager.default`; they never check `Task.isCancelled`.
- `MalwareScanner.hashAndMatch` uses `DispatchQueue.concurrentPerform` (all cores) with an `NSLock`; `HashCache`, `ThreatDatabase` and `ProgressThrottle` are `@unchecked Sendable` guarded by `NSLock`.
- Progress callbacks hop back with `Task { @MainActor in … }` per message (throttled to ~12/s by `ProgressThrottle`).
- `BackgroundScheduler` uses a 15-minute `Timer` and runs a Smart Scan, DB update and update checks when due.
- Language mode is Swift 5.9 with default (minimal) concurrency checking.

Issues:
- **Cancellation is cosmetic.** `AppModel.cancelScan()` cancels the outer task, but the scanner runs inside `Task.detached`, which doesn't inherit cancellation, and scanners never check it. The scan keeps burning CPU/IO to completion. If a new scan starts before it finishes, the old task still writes `results[category]`, `scanningCategory = nil` and `phase` and can clobber the new scan's state.
- `ProtectionModel.scan()` and `updateDatabase()` can't be cancelled at all; `clamscan` on large trees can run for many minutes.
- Protection and cleanup scans can run at the same time (fine), but `BackgroundScheduler` can kick off a Smart Scan while the user is in the review sheet of a previous one; `scan()` resets `results[c] = nil` under the open sheet. Guarded only by `isScanning`, not by phase `.results`.
- `ProtectionModel.perform` (quarantine/delete) and `Quarantine` do file I/O on the main actor.
- `ThreatDatabase.load()` copies the mapped table into an `Array` under the lock (≈32 MB per million hashes). Fine, but `snapshot()` then copies the array reference; OK because arrays are CoW.

## 3. Test coverage, TODOs, bugs and smells

**Tests: none.** No test target exists. No `TODO`/`FIXME` markers in the code.

### Safety (highest priority)

| # | Finding | Where |
|---|---|---|
| S1 | **`com.apple.*` is not refused by SafetyGuard.** `CacheScanner` lists every child of `~/Library/Caches` and `~/Library/Logs`, including `com.apple.Safari`, `com.apple.bird`-adjacent folders and so on, minus a short skip list. The backlog rule says never touch `com.apple.*`. Only `LeftoverScanner` filters them. | `SafetyGuard`, `CacheScanner` |
| S2 | Checks are **case-sensitive** on a case-insensitive filesystem. `~/library/Keychains/x`, `~/Library/mobile documents/…`, `Foo.PhotosLibrary` and `~/LIBRARY` (protected root) all slip through string comparison. | `SafetyGuard.isAllowed` |
| S3 | **No Unicode normalization.** A home folder or component in NFD vs NFC compares unequal. | `SafetyGuard` |
| S4 | **Temp allowance is too broad.** `tempRoot` is the parent of `NSTemporaryDirectory()` (`/var/folders/xx/yyyy/`), which also contains `C/` (per-user cache dir, used by system daemons) and `0/`. Only `T/` should be allowed. | `SafetyGuard` |
| S5 | Not protected: Mail's store (`~/Library/Mail`), `~/.Trash` itself, app bundle internals (`*.app/…`), `~/Library/CloudStorage` (iCloud/Dropbox/OneDrive File Provider), `~/Library/Photos`, `~/Library/Application Support/MobileSync` (only via future explicit rule). | `SafetyGuard` |
| S6 | Symlinks are resolved, which is good, but a **symlink item itself** (e.g. `~/Library/Caches/x → /etc`) is refused only because its target is outside home. A symlink *to* a protected place inside home (e.g. → `~/Documents`) resolves to a protected root and is refused, so the link can't be removed either. Acceptable (fail closed), noted for tests. | `SafetyGuard` |
| S7 | `resolvingSymlinksInPath()` silently drops `/private` from `/private/var/...`. The current code works by accident because of the extra `"/private" + tempRoot` check. Fragile. | `SafetyGuard` |
| S8 | `Cleaner` re-checks `SafetyGuard` at delete time (good), but between the check and `trashItem` a path component can be swapped for a symlink (TOCTOU). Narrow, but trivially closed by re-resolving and comparing just before the move and refusing if the resolved path changed since scan time. | `Cleaner` |
| S9 | `Quarantine.deletePermanently` and `SystemInfo.emptyTrash` (whole Trash, not just Filkollen's items) have no guard. Emptying the whole Trash is user-confirmed in the UI (menu bar "click again", overview button). | `Quarantine`, `SystemInfo` |
| S10 | `Quarantine.isolate` moves the file before writing the manifest; if the manifest write fails the file sits in quarantine with no record. | `Quarantine` |

### Correctness

| # | Finding | Where |
|---|---|---|
| C1 | Scan cancellation is ineffective and racy (see §2). | `AppModel` |
| C2 | Freed space is reported as the sum of `JunkItem.size`, i.e. allocated size at scan time, without accounting for APFS clones or hard links. Duplicate photos use **logical** `fileSizeKey`. Trashing doesn't free space until the Trash is emptied; the "done" screen says "moved to the Trash", good, but the menu bar and totals say "freed". | `Cleaner`, `DuplicatePhotoScanner` |
| C3 | Directory sizes count hard-linked files once per link. | `FileSizer` |
| C4 | `CacheScanner` doesn't skip caches of **running apps**; trashing a live app's cache can crash or corrupt it. | `CacheScanner` |
| C5 | Errors are swallowed: unreadable folders (`try?`), vanished files and per-item failures only surface as a count ("N item(s) couldn't be moved"). No per-item reasons in the UI. | scanners, `SmartScanView` |
| C6 | `Exclusions.isExcluded` is case-sensitive and doesn't resolve symlinks. | `Preferences.swift` |
| C7 | `DuplicatePhotoScanner` gives unreadable files a random UUID key; correct, but it re-reads the first 64 KB of every same-size file on every scan (no cache). Same-size groups are hashed head-first; there's no last-64 KB tier. | `DuplicatePhotoScanner` |
| C8 | `LeftoverScanner.isInstalled` is O(n·m) over `installed` per entry (`contains(where:)` with prefix checks) and calls LaunchServices per miss. Fine at typical sizes. | `LeftoverScanner` |
| C9 | Full Disk Access is refreshed on `didBecomeActive` (good) but there is no distinct "access was revoked" state; the onboarding just reappears unless it was dismissed earlier, in which case only the sidebar warning shows. | `AppModel`, `RootView` |
| C10 | `ClamAV.searchPaths` covers both Homebrew prefixes already; `clamscan` is used even when `clamd` is running. | `ClamAV` |
| C11 | `ThreatDatabase` has no integrity check on downloads and accepts any 64-hex token on any line, so a malformed export can silently shrink or pollute the table (an empty result throws; a partial one doesn't). | `ThreatDatabase` |

### Smells

- Scanners hardcode `FileManager.default.homeDirectoryForCurrentUser` and read `Pref` directly, so they can't be tested against fixture trees.
- `SafetyGuard` is a static enum with a static `home`; can't be pointed at a test root.
- Two `Process` wrappers (`Shell.run` and `ClamAV.run`).
- No logging at all (`os.Logger` not used). Failures are invisible after the fact.
- `try!` regexes (fine, constant patterns).
- `CategoryResult` recomputes totals on every view access; the review sheet and footers call them repeatedly. Fine at hundreds of items, slow at tens of thousands (Large Files, Duplicates).

## 4. macOS 13 deployment-target check

The compiler enforces availability, and CI builds with `MACOSX_DEPLOYMENT_TARGET = 13.0` with no errors, so nothing calls a 14+ API unguarded. Spot checks:

- `onChange(of:) { value in }` single-parameter form is used (the 13-compatible one). OK.
- No `@Observable`, `ContentUnavailableView`, `symbolEffect`, `containerBackground`, `inspector`, `SettingsLink`. OK.
- `Window`, `MenuBarExtra`, `.windowResizability`, `SMAppService`, `NavigationSplitView`, `.toolbarBackground` are all macOS 13. OK.
- `NSLock.withLock` is back-deployed (`@_alwaysEmitIntoClient`). OK.
- `SMAppService.openSystemSettingsLoginItems()` is macOS 13. OK.

Nothing breaks the deployment target. Runtime-only risk: the `x-apple.systempreferences:` FDA URL works on 13–15.

## 5. Policy conflicts to review

- **Network rule.** The backlog says "no network calls except MalwareBazaar updates, plus Sparkle". PR #2 (requested by Roben in another thread) adds an App Updates page that fetches **other apps'** Sparkle appcasts and runs `brew`/`mas`/`softwareupdate`, which hit the network. It's user-triggered or opt-out scheduled. I've left it as is and flagged it in `SESSION_SUMMARY.md` for a decision.
- **Empty Trash.** PR #2's Empty Trash empties the whole Trash, not "scoped to items Filkollen moved". Phase 2 adds a scoped variant; the existing whole-Trash button stays (user-confirmed) pending review.

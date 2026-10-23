# Architecture

Filkollen is a single SwiftUI app target (macOS 13+, not sandboxed, Hardened Runtime) plus a hosted XCTest bundle. `project.yml` is the source of truth; run `xcodegen generate` and never edit the generated `.xcodeproj`.

## Modules

```
Filkollen/
  App/        FilkollenApp (scenes, menus), AppDelegate (owns models, Dock/menu bar,
              BackgroundScheduler), AppModel (cleanup), ProtectionModel (malware),
              UpdatesModel (other apps' updates)
  Models/     JunkCategory, JunkItem, Preferences (Pref keys, Exclusions)
  Services/   ScanContext, the scanners, FileSizer, ContentHashCache, Cleaner,
              SafetyGuard, FullDiskAccess, Diagnostics, Log, Shell
    Protection/ ThreatDatabase, MalwareScanner, HashCache, ClamAV, Quarantine, Threat
    System/     SystemInfo, StartupItems, LoginItem, Notifier
    Updates/    SparkleChecker, PackageCheckers, AppUpdate
  Views/      RootView (sidebar), SmartScanView, CategoryDetailView, ReviewSheet,
              ProtectionView, MenuBarView, Settings, System pages, Theme, Components/
FilkollenTests/  Fixture (temp folder trees), SafetyGuard / Cleaner / scanner / sizing tests
```

## Cleanup flow

```
AppModel.scan(categories)
  └─ TaskGroup, one child per category
       └─ runScanner: Task.detached { Scanner(context: .live).scan(progress:) }
            └─ screened(): drop anything SafetyGuard refuses, record resolvedPath
  ◀─ results[category] = CategoryResult (minus Settings › Excluded folders)
CategoryDetailView / SmartScanView → ReviewSheet → AppModel.cleanSelected
  └─ Task.detached { Cleaner.moveToTrash(items) }
       └─ per item: exists? → SafetyGuard.evaluate → same resolvedPath as at scan? → trash
  ◀─ CleanupSummary (count, bytes, reclaimable bytes, per-item failures)
```

- **ScanContext** carries everything a scanner reads from the outside: home and temp roots, `FileManager`, clock, running apps, app search roots, LaunchServices lookup, preferences and a cache folder. `.live` is the real Mac; tests build one around a `Fixture`.
- **Cancellation**: `AppModel.cancelScan()` cancels the task and sets the context's `CancellationFlag`, which scanners check through `context.isCancelled` (it works on the worker threads `parallelMap` fans out to, where `Task.isCancelled` doesn't). A generation counter stops a dying scan from writing over a newer one.
- **Sizes**: `FileSizer.measure` returns allocated size and *reclaimable* size (excludes APFS clones and hard links with links elsewhere). The UI shows both, and is clear that space returns only when the Trash is emptied.
- **Duplicates**: size → first 64 KB → last 64 KB → full SHA-256, each tier hashed in parallel, cached in `photo-hash-cache.plist` by device + inode + size + mtime.

## Protection flow

`ProtectionModel.updateDatabase` downloads MalwareBazaar's SHA-256 exports (Auth-Key required) into a sorted binary table. `scan` walks the risky locations, hashes candidates in parallel (with `HashCache`), binary-searches the table, then optionally runs `clamscan`. Threats can be quarantined (moved, `chmod 0400`, manifest) or, after confirmation, deleted permanently.

## Concurrency

Models are `@MainActor ObservableObject`s. Heavy work is synchronous code run inside `Task.detached`, fanning out with `parallelMap` / `DispatchQueue.concurrentPerform` where it helps. Shared mutable helpers (`ProgressThrottle`, `ContentHashCache`, `HashCache`, `ThreatDatabase`, `CancellationFlag`) are `@unchecked Sendable` classes guarded by `NSLock`.

## Logging

`Log.<module>` (`os.Logger`, subsystem = bundle ID, categories app/scan/cleaner/safety/protection/updates). User paths are logged with `privacy: .private`. Help › Export Diagnostics… writes a scrubbed report.

## Adding a cleanup category safely

1. **Decide what it is.** Junk that's safe to regenerate (caches, build products) is pre-selected. Anything the user created or might want back (downloads, backups, large files) is **not** pre-selected.
2. **Add the case** to `JunkCategory` (title, subtitle, symbol, scanning message, gradient, tint). Add it to `smartScan` only if it's junk by the definition above.
3. **Write the scanner** as a struct with `var context: ScanContext = .live`. Read every root from `context` (never `FileManager.default.homeDirectoryForCurrentUser`), check `context.isCancelled` in every loop, report progress through `ProgressThrottle(progress, counting: true)`, and size items with `FileSizer.measure` so `reclaimable` is honest.
4. **Check it against SafetyGuard.** Scan results are screened automatically, so anything the guard refuses simply won't show. If the new module *needs* a location the guard refuses:
   - write down why in `docs/SAFETY.md`,
   - add the narrowest possible explicit allow rule (a specific folder, not a prefix of a protected one),
   - add tests that the allowed path passes **and** that its siblings, parents and look-alikes (case, NFD, symlink, `..`) stay refused,
   - call it out in `docs/SESSION_SUMMARY.md` / the PR for review.
5. **Wire it up** in `AppModel.runScanner` and `CategoryDetailView` (group titles/subtitles). The review sheet and Cleaner need nothing new.
6. **Test it** against a fixture tree: what it finds, what it must ignore, zero-byte and unreadable entries, cancellation.
7. **Document it** in the README feature table, `CHANGELOG.md` and the roadmap.

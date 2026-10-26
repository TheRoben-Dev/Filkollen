# Architecture

Filkollen is a single SwiftUI app target (macOS 13+, not sandboxed, Hardened Runtime) plus a hosted XCTest bundle. `project.yml` is the source of truth; run `xcodegen generate` and never edit the generated `.xcodeproj`.

## Modules

```
Filkollen/
  App/        FilkollenApp (scenes, menus), AppDelegate (owns models, Dock/menu bar,
              BackgroundScheduler), AppModel (cleanup, history), ProtectionModel (malware,
              Downloads watcher), UpdatesModel (other apps' updates), AboutPanel, Intents
  Models/     JunkCategory, JunkItem, Preferences (Pref keys, Exclusions)
  Services/   ScanContext, the scanners (Cache, Leftover, DuplicatePhoto [photos + files],
              LargeFile, Developer, Installer, IOSBackup, Browser), AppUninstaller,
              FileSizer, ContentHashCache (+ parallelMap, Locked), Cleaner, CleanupHistory,
              SafetyGuard, FullDiskAccess, Diagnostics, Log, Shell
    Protection/ ThreatDatabase, MalwareScanner, HashCache, ClamAV, Quarantine, Threat,
                CodeTrust, DownloadsWatcher
    System/     SystemInfo, StartupItems, LoginItem, Notifier, LocalSnapshots, DiskUsage (+ Treemap)
    Updates/    SparkleChecker, PackageCheckers, AppUpdate, SelfUpdater (Sparkle 2 for Filkollen)
  Views/      RootView (sidebar), SmartScanView, CategoryDetailView, ReviewSheet,
              UninstallerView, HistoryView, ProtectionView, AppTrustView, MenuBarView,
              Settings, System pages (incl. DiskUsageView, TimeMachineView), Theme, Components/
  Resources/  Assets, Localizable.xcstrings (en + sv)
FilkollenTests/  Fixture (temp folder trees) and tests for every service above
scripts/      bump-version.sh, release.sh, pre-commit, install-hooks.sh
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
  ◀─ CleanupSummary (count, bytes, reclaimable bytes, per-item failures, history record)
       └─ CleanupHistory.record: original → Trash location, for Undo / Put Back
```

App Uninstaller uses the same path: `AppUninstaller.remnants` → `AppModel.screened` → review → `AppModel.uninstall` → `Cleaner.moveToTrash` → history.

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

## Design system

All styling comes from `Filkollen/DesignSystem/`, namespaced under `DS`. The direction behind it is in `docs/design/DIRECTION.md`; the audit that motivated it is `docs/design/AUDIT.md`.

| File | Tokens |
|---|---|
| `DSColor.swift` | `DS.Color` (background layers, surfaces, text, separator, brand, status), `DS.ProtectionState`, `DS.CategoryFamily`, `JunkCategory.family/.dsTint/.dsSymbol`, `.dsAccent()` |
| `DSType.swift` | `DS.Font` (display, numeric, title, headline, body, callout, caption, badge, path), `Text.dsPath()` |
| `DSLayout.swift` | `DS.Space` (4-pt scale), `DS.Layout` (window, sidebar, inspector, readable widths), `DS.Inset` (padding per container type) |
| `DSShape.swift` | `DS.Radius`, `DS.shape(_:)` (continuous corners), `DS.Elevation` + `.dsElevation()` / `.dsCard()`, `DS.MaterialRole` + `.dsMaterial()` / `.dsGlass()` |
| `DSMotion.swift` | `DS.Motion` (snappy, smooth, gentle), `DS.Duration`, `withMotion`, `.dsAnimation()`, `.dsTransition()`, `.dsRise` / `.dsPop` |
| `DSIcon.swift` | `DS.Icon.TileSize`, shared action symbols, `DSTile` |

Colours that aren't system colours live in `Assets.xcassets/DesignSystem` (namespaced, so `Color("DesignSystem/Champagne")`), each with light, dark and both Increased Contrast variants. Regenerate them with `python3 scripts/design-colors.py Filkollen/Resources/Assets.xcassets/DesignSystem` rather than editing JSON by hand, then copy `Champagne` over `AccentColor`. `DesignTokenTests` fails if a colour drops below WCAG AA (4.5:1 text, 4:1 white on tiles) or Increased Contrast below 7:1.

### Rules for a new screen

1. **No literals.** Colours, fonts, spacing, radii, shadows and animations all come from `DS`. If a token is missing, add it to `DesignSystem/` and the Design Gallery, don't inline a number.
2. **Follow the system.** Use `DS.Color.text*` and `DS.Color.background*`, never `.white.opacity(x)`. The app is dark by default ("Noir": onyx canvas, champagne accent, New York serif for titles and big figures); `DS.Theme.apply()` sets `NSApp.appearance` at launch and Settings offers Match System, so every token still needs a light variant. Page backgrounds are `DSBackdrop`, never a raw colour. Interactive colour is `.tint`, champagne via `.dsAccent()` at each scene root; text on a champagne fill is `DS.Color.textOnAccent`, never white.
3. **Red means danger.** `DS.Color.danger` is only for threats, Delete Permanently and Empty Trash. Routine junk uses its category tint; warnings use `DS.Color.warning`.
4. **Numbers are monospaced.** Every size and count uses a `DS.Font.numeric*` or `display` token.
5. **Depth from `DS.Elevation`.** Cards use `.dsCard()`. Blur only through `.dsMaterial(_:)`/`.dsGlass(in:)`, never behind scrolling content; both fall back to solid under Reduce Transparency.
6. **Motion from `DS.Motion`.** Use `.dsAnimation`, `withMotion` and `.dsTransition`; they turn into crossfades under Reduce Motion. Nothing loops unless work is happening.
7. **Symbols are SF Symbols, hierarchical.** Category and tool tiles are `DSTile` at `.small` (sidebar), `.medium` (rows, cards) or `.large` (headers).
8. **Check it in the gallery and snapshots.** Debug › Design Gallery (⌥⌘G) shows tokens in light and dark. Run a Debug build with `-FKSnapshotDir <folder>` to capture every screen and state on fixture data; add new states to `Debug/SnapshotRunner.swift`.

# Roadmap

Every backlog item, its status at the audit baseline (`7d1b4b9`, PR #2), and the order it's being worked in. Order is impact ÷ effort, with safety work first because everything else builds on it.

Status key: **Done** · **Partial** · **Missing** · **N/A**. Checkboxes are ticked when the item is finished on `claude/project-thread-aiwa78`.

## Work order

### Tier 1: safety and correctness foundation
- [ ] 1. Unit test target in `project.yml`; injectable roots/FileManager/clock for `SafetyGuard` and scanners (P1, Missing)
- [ ] 2. `SafetyGuard` hardening + exhaustive tests: case, NFC/NFD, traversal, symlinks, firmlinks, `T/`-only temp, `com.apple.*`, Mail, Trash, app bundles, CloudStorage (P1, Missing)
- [ ] 3. Resolve-and-recheck at delete time, refuse if the resolved path changed since scan (TOCTOU) (P1, Partial)
- [ ] 4. Partial-success cleanup summary with per-item reasons (P1, Partial)
- [ ] 5. Real scan cancellation, no stale-task clobbering (P2 cancellation, Partial)
- [ ] 6. Skip caches of running apps (P1, Missing)
- [ ] 7. Scanner fixture tests in temp dirs (P1, Missing)
- [ ] 8. CI runs the tests (P7, Partial)
- [ ] 9. Full Disk Access "revoked" state (P1, Partial)
- [ ] 10. `os.Logger` per module + Export Diagnostics (P1, Missing)

### Tier 2: honest numbers and speed
- [ ] 11. APFS-aware sizing: hard links counted once, clone detection, "space you'll get back" (P2, Partial)
- [ ] 12. "Freed only after emptying the Trash" messaging + scoped Empty Trash for Filkollen's items (P2, Partial)
- [ ] 13. Duplicates: size → head → tail → full tiers, hash cache by inode+size+mtime (P2, Partial)
- [ ] 14. Concurrent scanning with bounded TaskGroup and live progress (P2, Partial)
- [ ] 15. `docs/PERF.md` before/after (P2, Missing)

### Tier 3: docs that keep it safe
- [ ] 16. `docs/SAFETY.md`, `docs/ARCHITECTURE.md` (with the "add a category" checklist), `CHANGELOG.md`, `CONTRIBUTING.md` (P8, Missing)

### Tier 4: new cleanup modules (each: category, scanner, SafetyGuard rule, tests, review sheet)
- [ ] 17. Developer junk: Archives, iOS DeviceSupport, CoreSimulator caches, SwiftPM, npm/yarn/pnpm, pip, Cargo, Gradle, CocoaPods, Go (P3, Partial: DerivedData only)
- [ ] 18. Old installers in Downloads (P3, Missing)
- [ ] 19. iOS backups & firmware (P3, Missing)
- [ ] 20. Large & Old Files: age filter, type grouping, Quick Look (P3, Partial: size-only from PR #2)
- [ ] 21. Time Machine local snapshots, informational (P3, Missing)
- [ ] 22. Mail Downloads cache (P3, Missing)
- [ ] 23. Browser caches (P3, Missing as a module; Safari conflicts with the `com.apple.*` rule, needs a decision)
- [ ] 24. Smarter leftovers with confidence (P3, Missing)
- [ ] 25. App Uninstaller (P3, Missing)
- [ ] 26. Duplicates upgrade: Live Photo / RAW+JPEG pairs, similar photos, any-file mode (P3, Missing)

### Tier 5: protection
- [ ] 27. Quarantine browser details, purge, report export (P5, Partial)
- [ ] 28. MalwareBazaar: integrity/format checks, DB age + stale warning (P5, Partial: auto-update when stale is in PR #2)
- [ ] 29. ClamAV: clamd/clamdscan, signature age, freshclam (P5, Partial)
- [ ] 30. Persistence inspector: signatures/Team ID/notarization, cron, shell hooks, profiles, login items (P5, Partial: Startup Items in PR #2)
- [ ] 31. App trust check for `/Applications` (P5, Missing)
- [ ] 32. Downloads watcher, off by default (P5, Missing)
- [ ] 33. YARA rules (P5, Missing)

### Tier 6: app experience
- [ ] 34. Review sheet polish: Quick Look, sort/filter, per-group select, reveal, live totals (P6, Missing)
- [ ] 35. Ignore list: right-click "Always ignore" (P6, Partial: excluded folders in Settings)
- [ ] 36. Undo/history with Put Back (P6, Missing)
- [ ] 37. Stats dashboard (Swift Charts) (P6, Missing)
- [ ] 38. Disk usage treemap (P6, Missing)
- [ ] 39. App Intents (P6, Missing)
- [ ] 40. Accessibility pass (P6, Missing)
- [ ] 41. Localization en + sv, String Catalog (P6, Missing)
- [ ] 42. Visual polish pass (P6, Partial)
- [ ] 43. Swift 6 strict-concurrency readiness (P1, Missing; done late because it touches everything)

### Tier 7: release and system level
- [ ] 44. Version automation + About window (P7, Missing)
- [ ] 45. SwiftLint/SwiftFormat + pre-commit hook (P7, Missing)
- [ ] 46. `scripts/release.sh` (P7, Missing)
- [ ] 47. Sparkle 2 for Filkollen itself (P7, Missing; PR #2's `SparkleChecker` only reads *other* apps' feeds)
- [ ] 48. Privileged helper (`SMAppService.daemon` + XPC) and its UI (P4, Missing)

## Backlog mapping

| Phase | Item | Status | Notes |
|---|---|---|---|
| 1 | Test target + injection | Missing | No test target |
| 1 | Exhaustive SafetyGuard tests | Missing | See AUDIT S1–S7 |
| 1 | Resolve symlinks / recheck at delete | Partial | Resolves and rechecks; no TOCTOU compare |
| 1 | Scanner fixture tests | Missing | |
| 1 | Error handling, partial-success summary | Partial | Failure count only |
| 1 | Skip running apps' caches | Missing | |
| 1 | FDA re-check on activate, revoked state | Partial | Re-check exists; no revoked state |
| 1 | Swift 6 strict concurrency | Missing | |
| 1 | os.Logger + Export diagnostics | Missing | |
| 2 | Correct freed space, APFS clones | Partial | Allocated size used; clones/hard links ignored |
| 2 | Trash messaging + scoped Empty Trash | Partial | Whole-Trash empty in PR #2 |
| 2 | Concurrent scanning, cancellation, progress | Partial | Malware hashing parallel; cleanup serial; no cancellation |
| 2 | Tiered duplicate matching + cache | Partial | size→head→full; no tail tier, no cache |
| 2 | PERF.md | Missing | |
| 3 | Large & Old Files | Partial | PR #2: size only, grouped by folder |
| 3 | App Uninstaller | Missing | |
| 3 | Developer junk | Partial | DerivedData only |
| 3 | Browser caches | Missing | Safari is `com.apple.Safari`: needs a decision |
| 3 | iOS backups & firmware | Missing | |
| 3 | Old installers | Missing | |
| 3 | Mail downloads | Missing | |
| 3 | Time Machine snapshots | Missing | |
| 3 | Smarter leftovers | Missing | |
| 3 | Duplicates upgrade | Missing | |
| 4 | Privileged helper | Missing | |
| 4 | Helper UI | Missing | |
| 5 | Scheduled MalwareBazaar updates | Partial | PR #2 auto-updates when >7 days old |
| 5 | Downloads watcher | Missing | |
| 5 | Persistence inspector | Partial | PR #2 Startup Items (launchd only, no signatures) |
| 5 | App trust check | Missing | |
| 5 | ClamAV improvements | Partial | Both Homebrew prefixes already searched |
| 5 | YARA | Missing | |
| 5 | Quarantine improvements | Partial | List + restore with collision check exist |
| 6 | Menu bar extra | **Done** | PR #2 |
| 6 | Scheduled Smart Scans + notification | **Done** | PR #2; never auto-deletes |
| 6 | Undo/history | Missing | |
| 6 | Stats dashboard | Missing | |
| 6 | Ignore list | Partial | Settings › Cleanup excluded folders (PR #2) |
| 6 | Disk usage view | Missing | |
| 6 | Review sheet polish | Missing | |
| 6 | App Intents | Missing | |
| 6 | Localization | Missing | |
| 6 | Accessibility | Missing | |
| 6 | Visual polish | Partial | |
| 7 | Sparkle 2 | Missing | |
| 7 | release.sh | Missing | |
| 7 | GitHub Actions tests/release | Partial | Build only |
| 7 | SwiftLint/SwiftFormat | Missing | |
| 7 | Version automation + About | Missing | |
| 8 | README updates | Partial | Ongoing |
| 8 | ARCHITECTURE.md | Missing | |
| 8 | SAFETY.md | Missing | |
| 8 | CONTRIBUTING.md, CHANGELOG.md | Missing | |

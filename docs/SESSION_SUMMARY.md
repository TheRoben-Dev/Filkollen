# Session summary (2026-10-23)

Work on `claude/project-thread-aiwa78`, stacked on PR #2 (`feature/menubar-updaters` at `479b962`). Every push was pulled, built and tested on Roben's Mac (M1 Max, macOS 27.0.1, Xcode 27.1); the app there was relaunched from each green build.

## Completed

**Phase 0.** `docs/AUDIT.md` (findings S1–S10, C1–C11) and `docs/ROADMAP.md` (48 items, now ticked). Baseline build confirmed before any change.

**Phase 1, safety and correctness.**
- `FilkollenTests` target with an injectable `ScanContext` and a `Fixture` that builds throwaway home/temp trees.
- `SafetyGuard` rewritten as an injectable struct: `realpath`, firmlink stripping, NFC + case folding, both ends of symlinks, `T/`-only temp, and a long list of refused places. Exhaustive tests.
- Delete-time re-check with a TOCTOU compare against the scan's resolved path.
- Partial-success summary with a reason per item; running apps' caches marked *In use*; Full Disk Access "revoked" state; `os.Logger` per module and Help › Export Diagnostics….
- Builds with `SWIFT_STRICT_CONCURRENCY=complete` with 0 warnings (11 fixed).

**Phase 2, honest numbers and speed.** Allocated vs reclaimable sizes (hard links, APFS clones), "space returns when you empty the Trash" messaging, concurrent category scans with real cancellation, tiered duplicate hashing with a cache, `docs/PERF.md`.

**Phase 3, modules.** Large & Old Files, App Uninstaller, Developer Junk, Browser & Mail Caches, iOS Backups & Firmware, Old Installers, Time Machine snapshots (informational), smarter leftovers with confidence, Duplicate Files mode, Live Photo / RAW-aware duplicate keeper.

**Phase 5, protection.** Quarantine SHA-256, missing-item flag, report export, delete-older-than-30-days, tamper-safe delete. Threat-DB integrity check and truncated-download guard. Stale-DB and ClamAV signature-age warnings. Offline code-signature checks (`CodeTrust`) for an App Trust tab and for Startup Items (with script and odd-location flags). Optional Downloads watcher.

**Phase 6, app experience.** History with Undo / Put Back, scoped "Empty Filkollen's Items from Trash", monthly chart, review-sheet filter/sort/untick/Quick Look, right-click Always Ignore, Disk Usage treemap, App Intents, VoiceOver labels and Reduce Motion, Swedish String Catalog (193 strings).

**Phase 7, release.** Version keys from `project.yml`, About panel, `scripts/bump-version.sh`, `scripts/release.sh` (Developer ID → notarize → staple → DMG), SwiftLint/SwiftFormat config, optional pre-commit hook, CI lint step (advisory), Sparkle 2 dormant until configured, `docs/RELEASING.md`.

**Phase 8, docs.** `docs/SAFETY.md`, `docs/ARCHITECTURE.md`, `docs/PERF.md`, `docs/RELEASING.md`, `docs/HELPER.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, README.

## Partial

- **Duplicates:** no Vision "similar photos" matching. Exact matches only.
- **ClamAV:** signature age shown, but no `clamd`/`clamdscan` support.
- **Persistence inspector:** launchd only; cron, shell startup files and configuration profiles aren't covered.
- **Swedish:** fixed text only; sentences with interpolated numbers stay English.
- **Visual polish:** no dedicated pass beyond accessibility and the new pages following the existing style.

## Skipped, and why

- **Privileged helper (Phase 4):** design and allowlist proposal in `docs/HELPER.md`, waiting for your review. It's the one change that lets Filkollen delete outside your home folder, and it can't be verified without a Developer ID–signed build.
- **YARA:** needs libyara or a `yara` binary plus a maintained rule source; little value before the helper exists.
- **Unavailable simulators cleanup:** `xcrun simctl delete unavailable` deletes directly, bypassing the Trash, which breaks the Trash-only rule. Developer Junk lists simulator caches instead.
- **`brew cleanup`:** same problem (deletes directly); Homebrew's download cache is listed under Developer Junk instead.
- **Running `freshclam` from the app:** it would add a network destination. The app tells you to run it.

## Decisions to review

1. **SafetyGuard exceptions** (all exact folders, whole items only, with tests for neighbours):
   - `~/Library/Caches/com.apple.Safari` and `~/Library/Containers/com.apple.Safari/Data/Library/Caches` (you approved "Allow both, narrowly").
   - `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` (same approval).
   - `~/Library/Application Support/MobileSync/Backup/<device>`: exactly one level below, never pre-selected. Confirmed by Roben 2026-10-23.
2. **Helper allowlist** in `docs/HELPER.md`: decided 2026-10-23 to keep it as a design doc and build it later, once signing is set up and the allowlist is reviewed.
3. **PR #2 vs the no-network rule:** App Updates reads other apps' appcasts and runs `brew`/`mas`/`softwareupdate`. That's more network than "MalwareBazaar + Sparkle". Roben chose to keep it (2026-10-23).
4. **PR #2's whole-Trash Empty Trash** (System Overview, menu bar) deletes things Filkollen didn't put there. History now has a scoped version. Roben chose to keep both (2026-10-23).
5. **Sparkle 2** is a new package dependency (resolved to 2.10.0). It does nothing until `FILKOLLEN_APPCAST_URL` and `FILKOLLEN_SPARKLE_PUBLIC_KEY` are set.
6. **Defaults:** plain-name leftovers off, Downloads watcher off, Duplicate Files and Large & Old Files never pre-selected, Duplicate Photos copies pre-selected (as before).
7. **App Uninstaller** can't move apps in `/Applications` (SafetyGuard); it removes support files and sends you to Finder for the app itself.

## Known issues

- Pages weren't checked visually on the Mac during this session: screen access was declined, so verification was by build, tests and launch only. Worth a click-through of App Uninstaller, History, Disk Usage, App Trust and the review sheet.
- Builds on the Mac are ad-hoc signed, so Open at login, Sparkle and a future helper are untested end to end. macOS may ask for Full Disk Access again after each rebuild.
- Disk Usage measures the whole home folder on first open; with a large `~/Library` that takes a while (spinner, cancellable by leaving the page).
- CI's Xcode (16.4) is older than the Mac's (27.1); CI is the check that the project still builds on older toolchains.

## Next steps

1. Review the decisions above, especially the MobileSync exception and the helper allowlist.
2. Click through the new pages once.
3. Merge order: PR #1 → PR #2 → this PR.
4. Set up Developer ID signing, then try `scripts/release.sh` with `SKIP_NOTARIZE=1`, then for real.
5. If the helper allowlist is approved: build it per `docs/HELPER.md`.

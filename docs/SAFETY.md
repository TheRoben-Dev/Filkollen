# What Filkollen refuses to touch, and why

Filkollen's job is to delete things, so the rules for what it may never delete matter more than any feature. They're enforced in one place, `SafetyGuard` (`Filkollen/Services/SafetyGuard.swift`), which every cleanup goes through twice: once when scan results are screened, and again right before each item is moved to the Trash. Every rule below has a test in `FilkollenTests/SafetyGuardTests.swift`.

## How a path is judged

1. **Canonicalize.** The path is resolved with `realpath` (every symlink, including the last component), the `/System/Volumes/Data` firmlink prefix is stripped, and the result is compared in Unicode NFC, case-folded. APFS is normally case- and normalization-insensitive, so `~/library/keychains` and `~/Library/Keychains` are the same folder and must get the same answer.
2. **Both ends of a symlink.** The item's own location (its parent resolved, its name kept) and its target are both checked. Either being protected refuses it. Removing a link is harmless, but failing closed keeps the rules simple.
3. **Unresolvable means no.** A relative path, a non-file URL, or a missing tail containing `.` or `..` (whose meaning depends on folders that don't exist yet) is refused.
4. **Re-checked at delete time.** The Cleaner re-evaluates each item immediately before moving it, and refuses it if it now resolves somewhere other than where the scan saw it. That closes the window where a folder is swapped for a symlink between scan and clean.

## Where Filkollen may work

- Inside your home folder.
- Inside your per-user temp folder (`/var/folders/…/T/`). Its siblings `C/` and `0/` belong to system daemons and are refused.

Everything else (`/`, `/System`, `/Library`, `/Applications`, other users, other volumes) is refused. System-wide cleanup will need the privileged helper planned for Phase 4, which will carry its own allowlist.

## Never removed, even though they're in your home folder

| What | Why |
|---|---|
| Your home folder, `~/Library`, and top-level folders (Desktop, Documents, Downloads, Pictures, Movies, Music, Public, Applications) | Removing the folder itself would break macOS or lose everything inside. Their *contents* can still be cleaned by modules that target them. |
| Any direct child of `~/Library` (`Caches`, `Logs`, `Fonts`, …) | These are system-defined containers. Only things *inside* them are candidates. |
| `~/Library/Caches`, `Logs`, `Application Support`, `Preferences`, `Containers`, `Group Containers`, `Saved Application State`, `HTTPStorages`, `WebKit`, `Cookies`, `LaunchAgents`, `Developer`, `Developer/Xcode`, `Developer/Xcode/DerivedData` | Same: the folder stays, entries inside may go. |
| Anything named `com.apple.*`, `group.com.apple.*` or `TEAMID.com.apple.*`, at any depth | macOS's own data. Even "just caches" here can hold state that breaks Safari, iCloud, Photos or system services when removed. |
| `~/Library/Keychains` | Passwords and certificates. |
| `~/Library/Mobile Documents` (iCloud Drive) and `~/Library/CloudStorage` (Dropbox, OneDrive, Google Drive…) | Deleting here deletes from the cloud and every other device. |
| Any `.photoslibrary` / `.photolibrary`, at any depth | Removing files inside a Photos library corrupts it. Use Photos' own Duplicates album. |
| `~/Library/Mail`, `Messages`, `Safari`, `Photos`, `Accounts`, `Calendars`, `IdentityServices`, `Sharing`, `Suggestions`, `Biome`, `Daemon Containers`, `PersonalizationPortrait` | App data stores, not caches. |
| `~/Library/Application Support/AddressBook`, `CallHistoryDB`, `Knowledge`, `MobileSync` | Contacts, call history, Screen Time data, iPhone backups. iOS backups will only become cleanable through an explicit, separately reviewed rule. |
| `~/Library/Autosave Information` | Unsaved documents. |
| `~/Library/Application Support/Filkollen` | Filkollen's own data, including the malware quarantine. |
| `~/.Trash`, `~/.ssh`, `~/.gnupg` | Trash can't be trashed; the others are credentials. |
| Anything *inside* an `.app` bundle | Picking apart a bundle breaks its code signature. A whole app may be removed (App Uninstaller), never parts of it. This is also why there's no "remove language files" cleaner. |

## Narrow exceptions

Each exception allows whole items only (an exact folder, or exactly one level below one), never anything inside them, and has its own tests.

| Allowed | Module | Why it's safe enough |
|---|---|---|
| `~/Library/Caches/com.apple.Safari` and `~/Library/Containers/com.apple.Safari/Data/Library/Caches` (exact folders) | Browser & Mail Caches | Safari's web cache, rebuilt as you browse. Approved by Roben 2026-10-23. Only offered while Safari is closed; the Cleaner refuses if it's running. History, cookies, passwords and everything else under `com.apple.Safari` stay refused. |
| `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` (exact folder) | Browser & Mail Caches | Copies of attachments you opened; originals stay in the mailbox. Approved by Roben 2026-10-23. Mail must be closed. The mailbox store (`~/Library/Mail`) and everything else in Mail's container stay refused. |
| `~/Library/Application Support/MobileSync/Backup/<device>` | iOS Backups & Firmware | Finder's per-device backup folders. Listed with device name and date, never pre-selected, moved to the Trash whole. |

Finder aliases are ordinary files and are judged as the file they are. Trashing an alias never touches what it points to.

## Behavioural rules

- **Junk always goes to the Trash**, after a review sheet. Nothing found by a cleanup module is ever deleted directly.
- **Only malware may skip the Trash**, and only after an explicit confirmation, because malware sitting in the Trash can still be launched. Quarantine (restorable, `chmod 0400`) is the default.
- **Running apps' caches** are listed but unselected and marked *In use*. Select All skips them.
- **Large & Old Files** are your files, not junk, and are never pre-selected.
- **Duplicates** always keep one copy (the oldest), which can't be selected by group or Select All.
- **Background scans only look.** Scheduled scans notify; nothing is cleaned without your review.
- **No network** except MalwareBazaar updates (and Sparkle for Filkollen itself, once added). No telemetry. *Exception under review:* the App Updates page added in PR #2 reads other apps' update feeds and runs `brew`/`mas`/`softwareupdate`; see `docs/SESSION_SUMMARY.md`.

## Changing these rules

Loosening any rule needs a stated reason, a new explicit allow rule that is as narrow as possible, and tests for both the allowed path and its neighbours that must stay refused. See the checklist in `docs/ARCHITECTURE.md`.

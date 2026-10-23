# Privileged helper: design proposal (not built yet)

Status: **proposal for review.** Nothing here is implemented. The helper is the only way Filkollen would ever delete outside your home folder, so its allowlist needs your sign-off before any code exists, and it can only be tested with a Developer ID–signed build (SMAppService daemons and the XPC signature checks don't work with the ad-hoc builds used during development).

## Goal

Clean a few system-wide locations that are junk by any reasonable definition and that a normal user process can't touch, without widening what the app itself may do. `SafetyGuard` in the app stays exactly as it is.

## Shape

- **Target:** `FilkollenHelper`, a command-line tool embedded at `Contents/Library/LaunchDaemons/` with its launchd plist, registered with `SMAppService.daemon(plistName:)` (macOS 13+). The user approves it once in System Settings › General › Login Items; Settings › Protection gets an on/off switch and shows its status.
- **Transport:** NSXPCConnection on a Mach service. The helper accepts a connection only when the client satisfies a code-signing requirement pinned to Filkollen's bundle ID **and** team ID (`anchor apple generic and identifier "dev.theroben.Filkollen" and certificate leaf[subject.OU] = "<TEAM>"`), checked with the audit token (`setCodeSigningRequirement` on macOS 13). Anything else is rejected before a method runs.
- **Protocol:** deliberately tiny.
  ```swift
  @objc protocol HelperProtocol {
      func version(reply: @escaping (String) -> Void)
      /// Lists candidates in the allowlisted roots. No paths come from the app.
      func scan(_ root: HelperRoot, reply: @escaping ([HelperItem]) -> Void)
      /// Removes items by the IDs `scan` returned, re-validating each one.
      func remove(_ ids: [UUID], reply: @escaping ([UUID: String]) -> Void)
  }
  ```
  The app never sends a path to delete. It sends IDs from a scan the helper did itself, and the helper re-runs every check on each item at removal time (same TOCTOU rule as the app: resolve again, refuse if anything changed).
- **Where removed items go:** root has no Trash of yours, so the helper moves items into a root-owned holding folder (`/Library/Application Support/Filkollen/Removed/<date>/`) and the app offers Put Back from History for 7 days, after which the helper deletes the folder. This keeps the "nothing disappears without a way back" rule.

## Proposed allowlist (first version)

| Root | What may be removed | Never |
|---|---|---|
| `/Library/Caches/` | Direct children whose name is a non-Apple bundle ID or vendor folder | `com.apple.*`, anything Apple-signed, `/Library/Caches` itself |
| `/Library/Logs/DiagnosticReports/` | Crash and hang reports (`.ips`, `.crash`, `.diag`, `.spin`) older than 7 days | Anything else |
| `/Library/Application Support/<vendor>` | Only as part of an App Uninstaller run, when the folder matches the app being removed by bundle ID | Shared vendor folders, `Apple`, anything not tied to the chosen app |
| `/Library/LaunchAgents/`, `/Library/LaunchDaemons/` | Only as part of an App Uninstaller run, when the plist's `Label` is the app's bundle ID or a helper of it; unloaded first with `launchctl bootout` | `com.apple.*`, anything whose label doesn't match |

Always refused, whatever a future allowlist says: `/System`, `/usr`, `/bin`, `/sbin`, `/private/var/db`, `/private/var/folders` of other users, other users' home folders, `/Applications` (removing apps stays a Finder action), Keychains, anything `com.apple.*`, anything inside a bundle, and any path that resolves through a symlink to somewhere else.

## Tests

The allowlist is a pure function (`HelperPolicy.evaluate(path, root, context) -> Decision`) shared as source between the app's test target and the helper, so it gets the same fixture-based tests as `SafetyGuard`: allowed paths, their siblings and parents, case/NFD/`..`/symlink look-alikes, Apple-named entries, and the uninstall-only roots without an uninstall context.

## Open questions for you

1. Is the allowlist above the right first set, or should it be even smaller (for example, only DiagnosticReports)?
2. Is a 7-day holding folder acceptable instead of the Trash?
3. Should the helper exist at all in the first public release, or wait until the core app has been used for a while?

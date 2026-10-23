import Foundation

enum Cleaner {
    struct Outcome: Sendable {
        var trashed: Set<URL> = []
        /// Where each item ended up in the Trash, for Put Back.
        var trashLocations: [URL: URL] = [:]
        /// Size of what was moved to the Trash. Disk space only comes back once the Trash is emptied.
        var trashedBytes: Int64 = 0
        /// The part of `trashedBytes` that emptying the Trash actually frees (APFS clones excluded).
        var reclaimableBytes: Int64 = 0
        /// Items that were already gone when we got to them (an app cleaned up after itself).
        var alreadyGone = 0
        var failures: [Failure] = []

        var isPartial: Bool { !failures.isEmpty && !trashed.isEmpty }
    }

    struct Failure: Sendable, Hashable {
        let url: URL
        let reason: String
    }

    /// Moves an item to the Trash; returns its new location. Injected so tests never touch the real Trash.
    typealias Trasher = @Sendable (URL) throws -> URL?

    static let systemTrash: Trasher = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    /// Moves items to the user's Trash so everything stays recoverable.
    ///
    /// Each item is re-checked by `SafetyGuard` right before it moves, and refused
    /// if its resolved location differs from what the scan saw: a folder swapped
    /// for a symlink between scan and clean must not redirect the move.
    static func moveToTrash(
        _ items: [JunkItem],
        safety: SafetyGuard = .shared,
        fileManager fm: FileManager = .default,
        isRunning: (String) -> Bool = RunningApps.isRunning,
        trash: Trasher = systemTrash
    ) -> Outcome {
        var outcome = Outcome()
        for item in items {
            if Task.isCancelled { break }
            // lstat semantics: a dangling symlink still exists and can be removed.
            guard (try? fm.attributesOfItem(atPath: item.url.path)) != nil else {
                outcome.trashed.insert(item.url)
                outcome.alreadyGone += 1
                continue
            }
            if let app = item.requiresClosed.first(where: isRunning) {
                outcome.failures.append(.init(url: item.url, reason: "Quit \(RunningApps.displayName(for: app)) first"))
                continue
            }
            switch safety.evaluate(item.url) {
            case .refused(let reason):
                outcome.failures.append(.init(url: item.url, reason: "Protected: \(reason)"))
                Log.cleaner.notice("Refused \(item.url.path, privacy: .private): \(reason, privacy: .public)")
            case .allowed(let resolved):
                if let scanned = item.resolvedPath,
                   SafetyGuard.fold(scanned) != SafetyGuard.fold(resolved) {
                    outcome.failures.append(.init(url: item.url, reason: "Its location changed since the scan"))
                    Log.cleaner.error("Location changed since scan: \(item.url.path, privacy: .private)")
                    continue
                }
                do {
                    let dest = try trash(item.url)
                    outcome.trashed.insert(item.url)
                    if let dest { outcome.trashLocations[item.url] = dest }
                    outcome.trashedBytes += item.size
                    outcome.reclaimableBytes += item.reclaimableSize
                } catch {
                    outcome.failures.append(.init(url: item.url, reason: Self.describe(error)))
                    Log.cleaner.error("Trash failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        Log.cleaner.info("Trashed \(outcome.trashed.count) items, \(outcome.failures.count) failed")
        return outcome
    }

    /// Short, user-facing reason for a failed move.
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        switch (ns.domain, ns.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError), (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return "Permission denied"
        case (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSCocoaErrorDomain, NSFileReadNoSuchFileError):
            return "It disappeared before it could be moved"
        case (NSPOSIXErrorDomain, Int(EBUSY)):
            return "In use"
        default:
            if let posix = ns.userInfo[NSUnderlyingErrorKey] as? NSError, posix.domain == NSPOSIXErrorDomain {
                if posix.code == Int(EBUSY) { return "In use" }
                if posix.code == Int(EACCES) || posix.code == Int(EPERM) { return "Locked or permission denied" }
            }
            return ns.localizedDescription
        }
    }
}

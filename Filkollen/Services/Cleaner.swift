import Foundation

enum Cleaner {
    struct Outcome: Sendable {
        var trashed: Set<URL> = []
        var freedBytes: Int64 = 0
        var failures: [Failure] = []
    }

    struct Failure: Sendable {
        let url: URL
        let reason: String
    }

    /// Moves items to the user's Trash so everything stays recoverable.
    static func moveToTrash(_ items: [JunkItem]) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        for item in items {
            guard SafetyGuard.isAllowed(item.url) else {
                outcome.failures.append(.init(url: item.url, reason: "Protected location"))
                continue
            }
            guard fm.fileExists(atPath: item.url.path) else {
                // Already gone (e.g. an app cleaned its own cache) — count it as done.
                outcome.trashed.insert(item.url)
                continue
            }
            do {
                try fm.trashItem(at: item.url, resultingItemURL: nil)
                outcome.trashed.insert(item.url)
                outcome.freedBytes += item.size
            } catch {
                outcome.failures.append(.init(url: item.url, reason: error.localizedDescription))
            }
        }
        return outcome
    }
}

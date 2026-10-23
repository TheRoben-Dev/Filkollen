import Foundation

enum FileSizer {
    /// What an item takes on disk, and how much of that deleting it would give back.
    struct Measurement: Equatable, Sendable {
        var allocated: Int64 = 0
        /// Excludes APFS clones (blocks shared with another file) and hard-linked
        /// files whose other links live outside the item. Freed only once the Trash is emptied.
        var reclaimable: Int64 = 0
    }

    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey, .isSymbolicLinkKey,
        .linkCountKey, .mayShareFileContentKey,
    ]

    /// On-disk size of a file, or the recursive size of a directory/package.
    static func allocatedSize(of url: URL) -> Int64 { measure(url).allocated }

    /// Measures a file or folder. Hard links are counted once; a symlink counts
    /// as nothing, because trashing it doesn't touch what it points to.
    static func measure(_ url: URL, fileManager fm: FileManager = .default) -> Measurement {
        guard let top = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]),
              top.isSymbolicLink != true else { return Measurement() }

        var tally = Tally()
        if top.isDirectory == true {
            guard let enumerator = fm.enumerator(
                at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
            ) else { return Measurement() }
            for case let file as URL in enumerator {
                if Task.isCancelled { break }
                tally.add(file)
            }
        } else {
            tally.add(url)
        }
        return tally.result
    }

    /// Allocated size of one regular file (0 for anything else).
    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    private struct Tally {
        private var m = Measurement()
        /// Hard-linked files seen so far, keyed by file identity.
        private var links: [AnyHashable: (seen: Int, total: Int, size: Int64, shared: Bool)] = [:]

        mutating func add(_ file: URL) {
            guard let v = try? file.resourceValues(forKeys: FileSizer.keys), v.isRegularFile == true else { return }
            let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            let shared = v.mayShareFileContent == true
            let linkCount = v.linkCount ?? 1
            if linkCount > 1,
               let id = (try? file.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject {
                let key = AnyHashable(id)
                if var entry = links[key] {
                    entry.seen += 1
                    links[key] = entry
                    return
                }
                links[key] = (1, linkCount, size, shared)
                m.allocated += size
                return
            }
            m.allocated += size
            if !shared { m.reclaimable += size }
        }

        var result: Measurement {
            var out = m
            // A hard-linked file is only freed if every one of its links goes too.
            for entry in links.values where entry.seen >= entry.total && !entry.shared {
                out.reclaimable += entry.size
            }
            return out
        }
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// Rate-limits progress callbacks so scanners don't flood the main thread,
/// and counts items so the status line can show a live rate.
final class ProgressThrottle: @unchecked Sendable {
    private let handler: @Sendable (String) -> Void
    private let counting: Bool
    private var last = Date.distantPast
    private let started = Date()
    private var count = 0
    private let lock = NSLock()

    /// `counting` prefixes messages with "1,234 items · 850/s".
    init(_ handler: @escaping @Sendable (String) -> Void, counting: Bool = false) {
        self.handler = handler
        self.counting = counting
    }

    /// Safe to call from many threads at once (the malware scan hashes in parallel).
    func report(_ message: @autoclosure () -> String) {
        let now = Date()
        let snapshot: Int? = lock.withLock {
            count += 1
            guard now.timeIntervalSince(last) > 0.08 else { return nil }
            last = now
            return count
        }
        guard let n = snapshot else { return }
        if counting {
            let rate = Double(n) / max(0.001, now.timeIntervalSince(started))
            handler("\(n.formatted()) items · \(Int(rate).formatted())/s · \(message())")
        } else {
            handler(message())
        }
    }
}

extension URL {
    /// `~/Library/Caches/foo` style path for display.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

import Foundation

/// Remembers each file's SHA-256 keyed by path, size and modification time, so
/// repeat scans only read files that changed. Also remembers files that turned
/// out not to be worth hashing, so they aren't opened again.
final class HashCache: @unchecked Sendable {
    struct Entry: Codable {
        let size: Int64
        let modified: Double
        /// nil: checked and not a candidate (not Mach-O, script or risky type).
        let digest: ThreatDatabase.Digest?
    }

    private let lock = NSLock()
    private var entries: [String: Entry]
    private var dirty = false

    private static var url: URL {
        ThreatDatabase.supportDirectory.appendingPathComponent("hash-cache.plist")
    }

    init() {
        let data = try? Data(contentsOf: Self.url)
        entries = data.flatMap { try? PropertyListDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    func lookup(_ path: String, size: Int64, modified: Double) -> Entry? {
        lock.withLock {
            guard let e = entries[path], e.size == size, e.modified == modified else { return nil }
            return e
        }
    }

    func store(_ path: String, _ entry: Entry) {
        lock.withLock {
            entries[path] = entry
            dirty = true
        }
    }

    /// Drops entries for files that no longer exist under the scanned roots, then saves.
    func save(keeping seen: Set<String>) {
        lock.withLock {
            let before = entries.count
            entries = entries.filter { seen.contains($0.key) }
            guard dirty || entries.count != before else { return }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(entries) {
                try? data.write(to: Self.url, options: .atomic)
            }
            dirty = false
        }
    }
}

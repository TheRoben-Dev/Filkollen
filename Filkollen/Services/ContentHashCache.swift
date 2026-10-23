import CryptoKit
import Darwin
import Foundation

/// Identifies a file's content for caching: same inode, size and modification
/// time means the bytes haven't changed, even if the file was renamed or moved.
struct FileIdentity: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modified: Double

    init?(_ url: URL) {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        device = st.st_dev
        inode = st.st_ino
        size = Int64(st.st_size)
        modified = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1e9
    }

    var key: String { "\(device):\(inode)" }
}

/// Partial and full SHA-256 hashes for duplicate detection, persisted between
/// scans so a re-scan only reads files that changed.
final class ContentHashCache: @unchecked Sendable {
    enum Kind: Sendable { case head, tail, full }

    struct Entry: Codable {
        var size: Int64
        var modified: Double
        var head: String?
        var tail: String?
        var full: String?
    }

    /// Bytes read for the head and tail tiers.
    static let chunk = 65_536

    private let url: URL?
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var dirty = false
    private(set) var hits = 0
    private(set) var misses = 0

    /// `url` nil keeps the cache in memory only.
    init(url: URL?) {
        self.url = url
        let data = url.flatMap { try? Data(contentsOf: $0) }
        entries = data.flatMap { try? PropertyListDecoder().decode([String: Entry].self, from: $0) } ?? [:]
    }

    /// The hash of the requested kind, computing (and remembering) it if needed. nil if unreadable.
    func hash(_ kind: Kind, of file: URL, identity: FileIdentity) -> String? {
        let cached: String? = lock.withLock {
            guard let e = entries[identity.key], e.size == identity.size, e.modified == identity.modified else { return nil }
            switch kind {
            case .head: return e.head
            case .tail: return e.tail
            case .full: return e.full
            }
        }
        if let cached {
            lock.withLock { hits += 1 }
            return cached
        }
        guard let digest = Self.compute(kind, of: file, size: identity.size) else { return nil }
        lock.withLock {
            misses += 1
            var e = entries[identity.key]
            if e == nil || e?.size != identity.size || e?.modified != identity.modified {
                e = Entry(size: identity.size, modified: identity.modified)
            }
            switch kind {
            case .head: e?.head = digest
            case .tail: e?.tail = digest
            case .full: e?.full = digest
            }
            entries[identity.key] = e
            dirty = true
        }
        return digest
    }

    /// Writes the cache, dropping entries for files not seen in this scan.
    func save(keeping seen: Set<String>) {
        lock.withLock {
            let before = entries.count
            entries = entries.filter { seen.contains($0.key) }
            guard let url, dirty || entries.count != before else { return }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            if let data = try? encoder.encode(entries) { try? data.write(to: url, options: .atomic) }
            dirty = false
        }
    }

    static func compute(_ kind: Kind, of url: URL, size: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining: Int
        switch kind {
        case .head:
            remaining = chunk
        case .tail:
            let offset = max(0, size - Int64(chunk))
            guard (try? handle.seek(toOffset: UInt64(offset))) != nil else { return nil }
            remaining = chunk
        case .full:
            remaining = .max
        }
        while remaining > 0 {
            if Task.isCancelled { return nil }
            guard let data = try? handle.read(upToCount: min(1 << 20, remaining)), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Runs `body` over `items` on all cores and collects the results in order.
func parallelMap<T: Sendable, R: Sendable>(_ items: [T], _ body: @Sendable (T) -> R) -> [R] {
    guard items.count > 1 else { return items.map(body) }
    let results = Locked([R?](repeating: nil, count: items.count))
    let workers = min(items.count, ProcessInfo.processInfo.activeProcessorCount)
    DispatchQueue.concurrentPerform(iterations: workers) { worker in
        var i = worker
        while i < items.count {
            let r = body(items[i])
            results.withLock { $0[i] = r }
            i += workers
        }
    }
    return results.withLock { $0.map { $0! } }
}

/// A value shared between threads, only touched under its lock.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withLock<R>(_ body: (inout Value) -> R) -> R {
        lock.lock(); defer { lock.unlock() }
        return body(&value)
    }
}

import Foundation

/// Offline SHA-256 blocklist built from abuse.ch MalwareBazaar's public exports.
///
/// Hashes are downloaded in bulk and matched locally, so nothing about the
/// user's files ever leaves the Mac. Stored as a sorted array of 32-byte
/// digests (~32 MB per million samples) and looked up with binary search.
final class ThreatDatabase: @unchecked Sendable {
    struct Digest: Comparable, Hashable {
        var a, b, c, d: UInt64

        init(_ a: UInt64, _ b: UInt64, _ c: UInt64, _ d: UInt64) {
            (self.a, self.b, self.c, self.d) = (a, b, c, d)
        }

        init?(hex: Substring) {
            guard hex.count == 64 else { return nil }
            var words: [UInt64] = []
            var idx = hex.startIndex
            for _ in 0..<4 {
                let end = hex.index(idx, offsetBy: 16)
                guard let w = UInt64(hex[idx..<end], radix: 16) else { return nil }
                words.append(w)
                idx = end
            }
            self.init(words[0], words[1], words[2], words[3])
        }

        init(bytes: some Sequence<UInt8>) {
            var words = [UInt64](repeating: 0, count: 4)
            for (i, byte) in bytes.prefix(32).enumerated() {
                words[i / 8] = (words[i / 8] << 8) | UInt64(byte)
            }
            self.init(words[0], words[1], words[2], words[3])
        }

        static func < (l: Digest, r: Digest) -> Bool { (l.a, l.b, l.c, l.d) < (r.a, r.b, r.c, r.d) }
    }

    enum Source {
        /// Every SHA-256 MalwareBazaar has ever seen (zip, updated daily).
        static let full = URL(string: "https://bazaar.abuse.ch/export/txt/sha256/full/")!
        /// Samples added in the last 48 hours (plain text).
        static let recent = URL(string: "https://bazaar.abuse.ch/export/txt/sha256/recent/")!
    }

    static let shared = ThreatDatabase()

    private let lock = NSLock()
    private var digests: [Digest] = []

    var storeURL: URL { Self.supportDirectory.appendingPathComponent("malwarebazaar-sha256.bin") }

    static var supportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Filkollen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    var lastUpdated: Date? {
        (try? storeURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return digests.isEmpty ? storedCount : digests.count
    }

    private var storedCount: Int {
        let size = (try? storeURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size / MemoryLayout<Digest>.stride
    }

    // MARK: Lookup

    func load() throws {
        lock.lock(); defer { lock.unlock() }
        guard digests.isEmpty else { return }
        let data = try Data(contentsOf: storeURL, options: .alwaysMapped)
        digests = data.withUnsafeBytes { Array($0.bindMemory(to: Digest.self)) }
    }

    /// Frees the ~tens of MB the table uses once a scan is finished.
    func unload() {
        lock.lock(); defer { lock.unlock() }
        digests = []
    }

    func contains(_ digest: Digest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        var lo = 0, hi = digests.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if digests[mid] == digest { return true }
            if digests[mid] < digest { lo = mid + 1 } else { hi = mid - 1 }
        }
        return false
    }

    // MARK: Update

    /// Downloads the full export plus the last 48 hours and rebuilds the local table.
    func update(progress: @escaping @Sendable (String) -> Void) async throws -> Int {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("filkollen-db-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress("Downloading MalwareBazaar hash list…")
        let (zipFile, _) = try await URLSession.shared.download(from: Source.full)
        let zipURL = work.appendingPathComponent("full.zip")
        try fm.moveItem(at: zipFile, to: zipURL)

        progress("Unpacking…")
        try Self.unzip(zipURL, to: work)

        progress("Fetching latest samples…")
        let (recentData, _) = try await URLSession.shared.data(from: Source.recent)

        progress("Building local database…")
        var set = Set<Digest>()
        let texts = (try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil))
            .filter { $0.pathExtension == "txt" }
        for file in texts {
            Self.parse(try String(contentsOf: file, encoding: .utf8), into: &set)
        }
        Self.parse(String(decoding: recentData, as: UTF8.self), into: &set)
        guard !set.isEmpty else { throw CocoaError(.fileReadCorruptFile) }

        let sorted = set.sorted()
        let data = sorted.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: storeURL, options: .atomic)

        lock.withLock { digests = sorted }
        return sorted.count
    }

    private static func parse(_ text: String, into set: inout Set<Digest>) {
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"),
                  let d = Digest(hex: Substring(trimmed.lowercased())) else { continue }
            set.insert(d)
        }
    }

    private static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw CocoaError(.fileReadCorruptFile) }
    }
}

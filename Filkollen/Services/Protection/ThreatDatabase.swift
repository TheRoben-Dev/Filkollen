import CryptoKit
import Foundation

/// Offline SHA-256 blocklist built from abuse.ch MalwareBazaar's public exports.
///
/// Hashes are downloaded in bulk and matched locally, so nothing about the
/// user's files ever leaves the Mac. Stored as a sorted array of 32-byte
/// digests (~32 MB per million samples) and looked up with binary search.
final class ThreatDatabase: @unchecked Sendable {
    struct Digest: Comparable, Hashable, Codable, Sendable {
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

    /// MalwareBazaar's authenticated exports (the old bazaar.abuse.ch/export/txt/ URLs now
    /// answer 410 Gone). The Auth-Key is part of the path, per https://bazaar.abuse.ch/export/.
    enum Source {
        static func base(_ key: String) -> URL {
            let safe = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? key
            return URL(string: "https://mb-api.abuse.ch/v2/files/exports/\(safe)/")!
        }
        /// Every sample, regenerated hourly. Tried in order; abuse.ch may serve it zipped.
        static let fullNames = ["full.csv.zip", "full.csv"]
        /// Samples from the last 48 hours, regenerated every 5 minutes.
        static let recentName = "recent.csv"
    }

    static let shared = ThreatDatabase()

    private let lock = NSLock()
    private var digests: [Digest] = []

    let storeURL: URL
    /// Count, SHA-256 and build date of `storeURL`, written with it.
    var sidecarURL: URL { storeURL.deletingPathExtension().appendingPathExtension("json") }

    init(storeURL: URL = ThreatDatabase.supportDirectory.appendingPathComponent("malwarebazaar-sha256.bin")) {
        self.storeURL = storeURL
    }

    struct Sidecar: Codable, Equatable {
        var count: Int
        var sha256: String
        var built: Date
    }

    enum IntegrityError: LocalizedError, Equatable {
        case truncated, unsorted, empty, checksumMismatch

        var errorDescription: String? {
            switch self {
            case .truncated, .unsorted, .empty, .checksumMismatch:
                return "The local threat database is damaged. Update it to download a fresh copy."
            }
        }
    }

    /// The table must be whole 32-byte digests, strictly ascending (binary search
    /// depends on it), and match the checksum written alongside it.
    static func validate(_ data: Data, sidecar: Sidecar?) -> IntegrityError? {
        guard !data.isEmpty else { return .empty }
        guard data.count % MemoryLayout<Digest>.stride == 0 else { return .truncated }
        let sorted = data.withUnsafeBytes { raw -> Bool in
            let table = raw.bindMemory(to: Digest.self)
            for i in table.indices.dropFirst() where !(table[i - 1] < table[i]) { return false }
            return true
        }
        guard sorted else { return .unsorted }
        if let sidecar {
            guard sidecar.count == data.count / MemoryLayout<Digest>.stride,
                  sidecar.sha256 == Self.hex(SHA256.hash(data: data)) else { return .checksumMismatch }
        }
        return nil
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    private func readSidecar() -> Sidecar? {
        guard let data = try? Data(contentsOf: sidecarURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Sidecar.self, from: data)
    }

    /// Writes a sorted table and its sidecar.
    func store(_ sorted: [Digest], now: Date = Date()) throws {
        let data = sorted.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: storeURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let sidecar = Sidecar(count: sorted.count, sha256: Self.hex(SHA256.hash(data: data)), built: now)
        try encoder.encode(sidecar).write(to: sidecarURL, options: .atomic)
    }

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

    /// Loads and checks the table. Throws `IntegrityError` if it's damaged; a
    /// missing sidecar (databases built before it existed) only skips the checksum.
    func load() throws {
        lock.lock(); defer { lock.unlock() }
        guard digests.isEmpty else { return }
        let data = try Data(contentsOf: storeURL, options: .alwaysMapped)
        if let problem = Self.validate(data, sidecar: readSidecar()) {
            Log.protection.error("Threat database failed its integrity check: \(String(describing: problem), privacy: .public)")
            throw problem
        }
        digests = data.withUnsafeBytes { Array($0.bindMemory(to: Digest.self)) }
    }

    /// Frees the ~tens of MB the table uses once a scan is finished.
    func unload() {
        lock.lock(); defer { lock.unlock() }
        digests = []
    }

    func contains(_ digest: Digest) -> Bool {
        Self.contains(digest, in: snapshot())
    }

    /// The loaded table, for lock-free lookups from many threads during a scan.
    func snapshot() -> [Digest] {
        lock.withLock { digests }
    }

    static func contains(_ digest: Digest, in table: [Digest]) -> Bool {
        var lo = 0, hi = table.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if table[mid] == digest { return true }
            if table[mid] < digest { lo = mid + 1 } else { hi = mid - 1 }
        }
        return false
    }

    // MARK: Update

    enum UpdateError: LocalizedError {
        case authRequired
        case keyRejected(Int, String)
        case http(Int, String)
        case unexpectedContent(String)
        case empty
        case shrank(old: Int, new: Int)

        var errorDescription: String? {
            switch self {
            case .authRequired:
                return "MalwareBazaar needs a free abuse.ch Auth-Key. Add it in Settings › Protection (get one at auth.abuse.ch)."
            case .keyRejected(let code, let message):
                return message.isEmpty
                    ? "abuse.ch rejected the Auth-Key (HTTP \(code))."
                    : "abuse.ch rejected the Auth-Key: \(message)"
            case .http(let code, let message):
                return "abuse.ch answered with HTTP \(code)" + (message.isEmpty ? "." : ": \(message)")
            case .unexpectedContent(let snippet):
                return "abuse.ch said: \"\(snippet)\""
            case .empty:
                return "The downloaded hash list was empty."
            case .shrank(let old, let new):
                return "The download had only \(new.formatted()) hashes, far fewer than the \(old.formatted()) you have. It was probably cut short, so the current database was kept."
            }
        }
    }

    /// abuse.ch Auth-Key (free at auth.abuse.ch). Required for exports; also sent as a header.
    static var authKey: String? {
        let key = UserDefaults.standard.string(forKey: "abuseChAuthKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (key?.isEmpty ?? true) ? nil : key
    }

    /// Downloads the full export plus the last 48 hours and rebuilds the local table.
    func update(progress: @escaping @Sendable (String) -> Void) async throws -> Int {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("filkollen-db-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        guard let key = Self.authKey else { throw UpdateError.authRequired }
        let base = Source.base(key)
        var set = Set<Digest>()

        progress("Downloading MalwareBazaar hash list…")
        var fullFile: URL?
        for name in Source.fullNames {
            do {
                let dest = work.appendingPathComponent("full.download")
                try fm.moveItem(at: try await Self.download(base.appendingPathComponent(name)), to: dest)
                fullFile = dest
                break
            } catch UpdateError.http(404, _), UpdateError.http(410, _) {
                continue
            }
        }
        if let fullFile {
            if try Self.isZip(fullFile) {
                progress("Unpacking…")
                let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
                try Self.unzip(fullFile, to: unpacked)
                let files = fm.enumerator(at: unpacked, includingPropertiesForKeys: nil)?
                    .compactMap { $0 as? URL }
                    .filter { ["csv", "txt"].contains($0.pathExtension.lowercased()) } ?? []
                for file in files {
                    Self.parse(String(decoding: try Data(contentsOf: file), as: UTF8.self), into: &set)
                }
            } else {
                try Self.parseOrThrow(try Data(contentsOf: fullFile), into: &set)
            }
        }

        progress("Fetching latest samples…")
        let recentFile = try await Self.download(base.appendingPathComponent(Source.recentName))
        try Self.parseOrThrow(try Data(contentsOf: recentFile), into: &set)

        progress("Building local database…")
        guard !set.isEmpty else { throw UpdateError.empty }

        // A full export that's suddenly much smaller is a truncated download, not good news.
        let previous = storedCount
        if fullFile != nil, previous > 10_000, set.count < previous / 2 {
            throw UpdateError.shrank(old: previous, new: set.count)
        }
        let sorted = set.sorted()
        try store(sorted)

        lock.withLock { digests = sorted }
        return sorted.count
    }

    private static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Filkollen/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let key = authKey
        if let key { request.setValue(key, forHTTPHeaderField: "Auth-Key") }

        let (file, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse {
            let code = http.statusCode
            if !(200..<300).contains(code) {
                // abuse.ch explains rejections in the body, e.g. "Email address not confirmed".
                let body = (try? Data(contentsOf: file)).map { String(decoding: $0.prefix(300), as: UTF8.self) } ?? ""
                let message = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: key ?? "\u{0}", with: "…")
                switch code {
                case 401, 403: throw UpdateError.keyRejected(code, message)
                default: throw UpdateError.http(code, message)
                }
            }
        }
        return file
    }

    private static func isZip(_ file: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try handle.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) // "PK\u{3}\u{4}"
    }

    /// Parses a plain-text export, or explains what came back instead (HTML, JSON error…).
    private static func parseOrThrow(_ data: Data, into set: inout Set<Digest>) throws {
        let text = String(decoding: data, as: UTF8.self)
        let before = set.count
        parse(text, into: &set)
        guard set.count == before else { return }

        // Only comments and no hashes is a valid (if quiet) "recent" export.
        let meaningful = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !meaningful.isEmpty else { return }
        throw UpdateError.unexpectedContent(String(meaningful[0].prefix(120)))
    }

    /// Accepts both plain hash lists and MalwareBazaar's CSV export: every 64-hex-char
    /// field on a line is a SHA-256 (MD5/SHA-1/SHA3-384 columns have other lengths).
    private static func parse(_ text: String, into set: inout Set<Digest>) {
        let quotes = CharacterSet(charactersIn: "\" ").union(.whitespaces)
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            for field in line.split(separator: ",") {
                let token = field.trimmingCharacters(in: quotes).lowercased()
                guard token.count == 64, let d = Digest(hex: Substring(token)) else { continue }
                set.insert(d)
            }
        }
    }

    private static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, dir.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw UpdateError.unexpectedContent("archive could not be unpacked")
        }
    }
}

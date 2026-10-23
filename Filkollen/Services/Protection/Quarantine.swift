import CryptoKit
import Foundation

/// Moves threats into a locked-down folder so they can't run, while keeping
/// enough metadata to restore them if it was a false positive.
///
/// Every function takes the quarantine folder so tests can use a throwaway one;
/// the app always uses `directory`.
enum Quarantine {
    struct Entry: Codable, Identifiable, Hashable, Sendable {
        let id: UUID
        let originalPath: String
        let storedPath: String
        let engine: Threat.Engine
        let identifier: String
        let size: Int64
        let date: Date
        let originalPermissions: Int
        /// SHA-256 of the file as quarantined; nil for entries made before it was recorded.
        var sha256: String? = nil

        var name: String { (originalPath as NSString).lastPathComponent }
        /// The stored copy is gone (removed by hand, or a damaged folder).
        var isMissing: Bool { !FileManager.default.fileExists(atPath: storedPath) }
    }

    static var directory: URL {
        let dir = ThreatDatabase.supportDirectory.appendingPathComponent("Quarantine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func manifestURL(_ dir: URL) -> URL { dir.appendingPathComponent("manifest.json") }

    static func entries(in dir: URL = directory) -> [Entry] {
        guard let data = try? Data(contentsOf: manifestURL(dir)),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private static func save(_ entries: [Entry], in dir: URL) throws {
        try JSONEncoder().encode(entries).write(to: manifestURL(dir), options: .atomic)
    }

    @discardableResult
    static func isolate(_ threat: Threat, in dir: URL = directory, now: Date = Date()) throws -> Entry {
        let fm = FileManager.default
        let id = UUID()
        let slot = dir.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        let dest = slot.appendingPathComponent(threat.url.lastPathComponent)

        let perms = (try? fm.attributesOfItem(atPath: threat.url.path)[.posixPermissions] as? Int) ?? 0o644
        let digest = sha256(of: threat.url)
        try fm.moveItem(at: threat.url, to: dest)
        // Read-only, no execute bit: it can't be launched from here.
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: dest.path)

        let entry = Entry(
            id: id, originalPath: threat.url.path, storedPath: dest.path,
            engine: threat.engine, identifier: threat.identifier, size: threat.size,
            date: now, originalPermissions: perms, sha256: digest
        )
        try save(entries(in: dir) + [entry], in: dir)
        Log.protection.notice("Quarantined \(threat.url.path, privacy: .private) (\(threat.engine.rawValue, privacy: .public))")
        return entry
    }

    static func restore(_ entry: Entry, in dir: URL = directory) throws {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: entry.originalPath)
        guard !fm.fileExists(atPath: original.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: original.path])
        }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: entry.originalPermissions], ofItemAtPath: entry.storedPath)
        try fm.moveItem(atPath: entry.storedPath, toPath: original.path)
        try? fm.removeItem(at: URL(fileURLWithPath: entry.storedPath).deletingLastPathComponent())
        try save(entries(in: dir).filter { $0.id != entry.id }, in: dir)
        Log.protection.notice("Restored \(original.path, privacy: .private) from quarantine")
    }

    /// Permanently removes a quarantined file. Not recoverable.
    static func delete(_ entry: Entry, in dir: URL = directory) throws {
        let slot = URL(fileURLWithPath: entry.storedPath).deletingLastPathComponent()
        // Only ever remove a slot inside the quarantine folder, whatever the manifest says.
        guard slot.standardizedFileURL.deletingLastPathComponent().path == dir.standardizedFileURL.path else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: slot.path])
        }
        if FileManager.default.fileExists(atPath: slot.path) {
            try FileManager.default.removeItem(at: slot)
        }
        try save(entries(in: dir).filter { $0.id != entry.id }, in: dir)
    }

    /// Entries quarantined before `date`, for "Delete items older than…".
    static func entries(olderThan date: Date, in dir: URL = directory) -> [Entry] {
        entries(in: dir).filter { $0.date < date }
    }

    /// Writes the manifest (what was found, where, when, by which engine, and
    /// its hash) as JSON. The quarantined files themselves are not included.
    static func exportReport(to url: URL, in dir: URL = directory) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries(in: dir)).write(to: url, options: .atomic)
    }

    /// Permanently deletes a detected threat in place, skipping the Trash
    /// (malware sitting in the Trash can still be launched).
    static func deletePermanently(_ threat: Threat) throws {
        try FileManager.default.removeItem(at: threat.url)
        Log.protection.notice("Deleted a threat permanently (\(threat.engine.rawValue, privacy: .public))")
    }

    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

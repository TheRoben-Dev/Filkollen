import Foundation

/// Moves threats into a locked-down folder so they can't run, while keeping
/// enough metadata to restore them if it was a false positive.
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

        var name: String { (originalPath as NSString).lastPathComponent }
    }

    static var directory: URL {
        let dir = ThreatDatabase.supportDirectory.appendingPathComponent("Quarantine", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var manifestURL: URL { directory.appendingPathComponent("manifest.json") }

    static func entries() -> [Entry] {
        guard let data = try? Data(contentsOf: manifestURL),
              let list = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return list.sorted { $0.date > $1.date }
    }

    private static func save(_ entries: [Entry]) throws {
        try JSONEncoder().encode(entries).write(to: manifestURL, options: .atomic)
    }

    @discardableResult
    static func isolate(_ threat: Threat) throws -> Entry {
        let fm = FileManager.default
        let id = UUID()
        let slot = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: slot, withIntermediateDirectories: true)
        let dest = slot.appendingPathComponent(threat.url.lastPathComponent)

        let perms = (try? fm.attributesOfItem(atPath: threat.url.path)[.posixPermissions] as? Int) ?? 0o644
        try fm.moveItem(at: threat.url, to: dest)
        // Read-only, no execute bit: it can't be launched from here.
        try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: dest.path)

        let entry = Entry(
            id: id, originalPath: threat.url.path, storedPath: dest.path,
            engine: threat.engine, identifier: threat.identifier, size: threat.size,
            date: Date(), originalPermissions: perms
        )
        try save(entries() + [entry])
        return entry
    }

    static func restore(_ entry: Entry) throws {
        let fm = FileManager.default
        let original = URL(fileURLWithPath: entry.originalPath)
        guard !fm.fileExists(atPath: original.path) else {
            throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: original.path])
        }
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: entry.originalPermissions], ofItemAtPath: entry.storedPath)
        try fm.moveItem(atPath: entry.storedPath, toPath: original.path)
        try? fm.removeItem(at: URL(fileURLWithPath: entry.storedPath).deletingLastPathComponent())
        try save(entries().filter { $0.id != entry.id })
    }

    /// Permanently removes a quarantined file. Not recoverable.
    static func delete(_ entry: Entry) throws {
        let slot = URL(fileURLWithPath: entry.storedPath).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: slot.path) {
            try FileManager.default.removeItem(at: slot)
        }
        try save(entries().filter { $0.id != entry.id })
    }

    /// Permanently deletes a detected threat in place, skipping the Trash
    /// (malware sitting in the Trash can still be launched).
    static func deletePermanently(_ threat: Threat) throws {
        try FileManager.default.removeItem(at: threat.url)
    }
}

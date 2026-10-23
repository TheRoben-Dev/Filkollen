import Foundation

/// What each cleanup moved to the Trash, and where it went, so it can be put back.
/// Stored as JSON in Filkollen's support folder; the newest 200 cleanups are kept.
struct CleanupHistory: Sendable {
    struct Item: Codable, Hashable, Sendable {
        let original: String
        let trashed: String
        let size: Int64
        var restored = false
        /// Deleted from the Trash by "Empty Filkollen's Items"; optional so older history still loads.
        var emptied: Bool? = nil
    }

    struct Record: Codable, Identifiable, Hashable, Sendable {
        let id: UUID
        let date: Date
        /// "Smart Scan", a category title, or "Uninstalled Foo".
        let source: String
        var items: [Item]
        let bytes: Int64
        let reclaimable: Int64

        var restorable: [Item] { items.filter { !$0.restored && $0.emptied != true } }
    }

    enum PutBackError: LocalizedError, Equatable {
        case goneFromTrash, originalExists, refused(String)

        var errorDescription: String? {
            switch self {
            case .goneFromTrash: return "It's no longer in the Trash (the Trash may have been emptied)."
            case .originalExists: return "Something with the same name is already back in its place."
            case .refused(let reason): return "Filkollen won't put it there: \(reason)"
            }
        }
    }

    static let limit = 200

    let url: URL
    var safety: SafetyGuard = .shared

    static let live = CleanupHistory(url: ThreatDatabase.supportDirectory.appendingPathComponent("cleanup-history.json"))

    func records() -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ((try? decoder.decode([Record].self, from: data)) ?? []).sorted { $0.date > $1.date }
    }

    private func save(_ records: [Record]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(Array(records.sorted { $0.date > $1.date }.prefix(Self.limit))).write(to: url, options: .atomic)
        } catch {
            Log.cleaner.error("Couldn't save cleanup history: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Records a cleanup. Items without a known Trash location can't be put back and aren't listed.
    @discardableResult
    func record(_ outcome: Cleaner.Outcome, items: [JunkItem], source: String, now: Date = Date()) -> Record? {
        let sizes = Dictionary(items.map { ($0.url, $0.size) }, uniquingKeysWith: { a, _ in a })
        let entries = outcome.trashLocations.map { original, trashed in
            Item(original: original.path, trashed: trashed.path, size: sizes[original] ?? 0)
        }.sorted { $0.original < $1.original }
        guard !entries.isEmpty else { return nil }
        let record = Record(id: UUID(), date: now, source: source, items: entries,
                            bytes: outcome.trashedBytes, reclaimable: outcome.reclaimableBytes)
        save(records() + [record])
        return record
    }

    /// Moves items back from the Trash to where they were. Returns a reason for each one that couldn't go back.
    func putBack(_ recordID: UUID, only: Set<String>? = nil, fileManager fm: FileManager = .default) -> [String: PutBackError] {
        var all = records()
        guard let index = all.firstIndex(where: { $0.id == recordID }) else { return [:] }
        var failures: [String: PutBackError] = [:]
        for i in all[index].items.indices where !all[index].items[i].restored && all[index].items[i].emptied != true {
            let item = all[index].items[i]
            if let only, !only.contains(item.original) { continue }
            let original = URL(fileURLWithPath: item.original)
            guard (try? fm.attributesOfItem(atPath: item.trashed)) != nil else { failures[item.original] = .goneFromTrash; continue }
            guard (try? fm.attributesOfItem(atPath: item.original)) == nil else { failures[item.original] = .originalExists; continue }
            // Only back into places Filkollen may work in (it took it from there).
            if case .refused(let reason) = safety.evaluate(original) { failures[item.original] = .refused(reason); continue }
            do {
                try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(atPath: item.trashed, toPath: item.original)
                all[index].items[i].restored = true
            } catch {
                failures[item.original] = .refused(Cleaner.describe(error))
            }
        }
        save(all)
        Log.cleaner.info("Put back \(all[index].items.filter(\.restored).count) items, \(failures.count) couldn't go back")
        return failures
    }

    /// What "Empty Filkollen's Items" would delete: things Filkollen moved that are
    /// still sitting directly in the Trash. Nothing else in the Trash is touched.
    func itemsInTrash(home: URL, fileManager fm: FileManager = .default) -> [Item] {
        let trash = SafetyGuard.fold(SafetyGuard.canonicalPath(home.appendingPathComponent(".Trash").path) ?? "")
        guard !trash.isEmpty else { return [] }
        return records().flatMap(\.restorable).filter { item in
            guard (try? fm.attributesOfItem(atPath: item.trashed)) != nil else { return false }
            // Its parent, resolved, must be the Trash itself.
            let parent = URL(fileURLWithPath: item.trashed).deletingLastPathComponent().path
            return SafetyGuard.fold(SafetyGuard.canonicalPath(parent) ?? "") == trash
        }
    }

    /// Permanently deletes `itemsInTrash`. Returns bytes freed and how many failed.
    func emptyFromTrash(home: URL, fileManager fm: FileManager = .default) -> (freed: Int64, failed: Int) {
        let targets = Set(itemsInTrash(home: home, fileManager: fm).map(\.trashed))
        var all = records()
        var freed: Int64 = 0, failed = 0
        for r in all.indices {
            for i in all[r].items.indices where targets.contains(all[r].items[i].trashed) {
                do {
                    try fm.removeItem(atPath: all[r].items[i].trashed)
                    all[r].items[i].emptied = true
                    freed += all[r].items[i].size
                } catch {
                    failed += 1
                }
            }
        }
        save(all)
        Log.cleaner.notice("Emptied \(targets.count - failed) of Filkollen's items from the Trash")
        return (freed, failed)
    }

    /// Lifetime totals, for the stats line.
    func totals() -> (cleanups: Int, items: Int, bytes: Int64) {
        let all = records()
        return (all.count, all.reduce(0) { $0 + $1.items.count }, all.reduce(0) { $0 + $1.bytes })
    }

    func clear() { try? FileManager.default.removeItem(at: url) }
}

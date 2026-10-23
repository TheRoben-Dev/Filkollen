import Foundation

struct JunkItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    /// Allocated (on-disk) size.
    let size: Int64
    let category: JunkCategory
    /// Human-friendly grouping, e.g. "Safari Cache", "com.spotify.client", or a duplicate group id.
    let group: String
    /// Short explanation shown in the review list.
    var detail: String = ""
    var isSelected: Bool = true
    /// In a duplicate group, the copy we keep. Never trashed by default.
    var isKeeper: Bool = false
    var modified: Date? = nil
    /// Name of a running app that's probably using this item. Shown as a warning; never pre-selected.
    var inUseBy: String? = nil
    /// Canonical location when scanned. The Cleaner refuses the item if it resolves elsewhere later.
    var resolvedPath: String? = nil

    /// What emptying the Trash would actually give back, when it's less than `size`
    /// (APFS clones, hard links). nil means all of `size`.
    var reclaimable: Int64? = nil
    enum Confidence: Sendable { case high, low }
    /// How sure a guess-based scanner is that this belongs to a removed app; nil = not a guess.
    var confidence: Confidence? = nil
    /// Bundle IDs of apps that must be closed before this may be cleaned. The Cleaner enforces it.
    var requiresClosed: [String] = []

    var name: String { url.lastPathComponent }
    var reclaimableSize: Int64 { reclaimable ?? size }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

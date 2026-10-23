import Foundation

struct JunkItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
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
    /// Canonical location when scanned. The Cleaner refuses the item if it resolves elsewhere later.
    var resolvedPath: String? = nil

    var name: String { url.lastPathComponent }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

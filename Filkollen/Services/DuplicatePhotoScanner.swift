import CryptoKit
import Foundation

/// Finds byte-identical image files. Size → quick head hash → full SHA-256,
/// so most files are never fully read.
///
/// The Photos library package is skipped on purpose: deleting files inside it
/// corrupts the library. Photos has its own duplicate detection for that.
struct DuplicatePhotoScanner {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }
    private var home: URL { context.home }

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf",
    ]

    var roots: [URL] {
        ["Pictures", "Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0) }
    }

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress)

        // 1. Collect candidate images grouped by exact size.
        var bySize: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                if Task.isCancelled { return [] }
                // Not always registered as a package (no Photos app, external drive), so skip by name too.
                if url.pathExtension.lowercased() == "photoslibrary" { enumerator.skipDescendants(); continue }
                guard Self.imageExtensions.contains(url.pathExtension.lowercased()),
                      let v = try? url.resourceValues(forKeys: Set(keys)),
                      v.isRegularFile == true, let size = v.fileSize, size > 0 else { continue }
                throttle.report(url.abbreviatedPath)
                bySize[Int64(size), default: []].append(url)
            }
        }

        // 2. Narrow down with a cheap hash of the first 64 KB, then confirm with a full hash.
        var items: [JunkItem] = []
        for (size, urls) in bySize where urls.count > 1 {
            if Task.isCancelled { return [] }
            let byHead = Dictionary(grouping: urls) { Self.hash($0, limit: 65_536) ?? UUID().uuidString }
            for (_, headGroup) in byHead where headGroup.count > 1 {
                let byFull = Dictionary(grouping: headGroup) { url -> String in
                    throttle.report("Comparing \(url.lastPathComponent)")
                    return Self.hash(url, limit: nil) ?? UUID().uuidString
                }
                for (digest, group) in byFull where group.count > 1 {
                    items += makeGroup(group, size: size, digest: digest)
                }
            }
        }
        return items.sorted { $0.group != $1.group ? $0.group < $1.group : ($0.isKeeper && !$1.isKeeper) }
    }

    private static let groupKeys: Set<URLResourceKey> = [
        .creationDateKey, .totalFileAllocatedSizeKey, .fileContentIdentifierKey, .mayShareFileContentKey, .linkCountKey,
    ]

    /// Keeps the oldest copy (most likely the original), marks the rest for removal.
    /// A copy that's an APFS clone of the kept one shares its blocks, so trashing it
    /// gives back almost nothing; it's still listed, but counted as 0 reclaimable.
    private func makeGroup(_ urls: [URL], size: Int64, digest: String) -> [JunkItem] {
        let dated = urls.map { url -> (url: URL, created: Date, values: URLResourceValues?) in
            let values = try? url.resourceValues(forKeys: Self.groupKeys)
            return (url, values?.creationDate ?? .distantFuture, values)
        }.sorted { ($0.created, $0.url.path.count) < ($1.created, $1.url.path.count) }
        let keeperContent = dated.first?.values?.fileContentIdentifier

        return dated.enumerated().map { index, entry in
            let v = entry.values
            let isClone = index != 0 && keeperContent != nil && v?.fileContentIdentifier == keeperContent
            let shares = v?.mayShareFileContent == true || (v?.linkCount ?? 1) > 1
            let folder = entry.url.deletingLastPathComponent().abbreviatedPath
            return JunkItem(
                url: entry.url,
                size: v?.totalFileAllocatedSize.map(Int64.init) ?? size,
                category: .duplicatePhotos,
                group: String(digest.prefix(16)),
                detail: isClone ? "\(folder) · clone of the kept copy, frees almost no space" : folder,
                isSelected: index != 0,
                isKeeper: index == 0,
                modified: entry.created,
                reclaimable: index != 0 && (isClone || shares) ? 0 : nil
            )
        }
    }

    static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? .max
        while remaining > 0 {
            let chunk = min(1 << 20, remaining)
            guard let data = try? handle.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

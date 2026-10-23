import Foundation

/// Finds byte-identical image files. Size → head hash → tail hash → full
/// SHA-256, so most files are never fully read.
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

        // 2. Same size → same first 64 KB → same last 64 KB → same full SHA-256.
        //    Most files drop out after reading 64 KB; hashes are cached by inode,
        //    size and modification time, so a re-scan reads only what changed.
        let cache = ContentHashCache(url: context.cacheDirectory?.appendingPathComponent("photo-hash-cache.plist"))
        var seen = Set<String>()
        var items: [JunkItem] = []
        let candidates = bySize.filter { $0.value.count > 1 }
        var compared = 0
        for (size, urls) in candidates {
            if Task.isCancelled { return [] }
            let files = urls.compactMap { url in FileIdentity(url).map { (url, $0) } }
            seen.formUnion(files.map(\.1.key))
            compared += files.count
            throttle.report("Comparing \(compared.formatted()) photos…")

            var groups = [files]
            let tiers: [ContentHashCache.Kind] = size <= Int64(ContentHashCache.chunk) ? [.head] : [.head, .tail, .full]
            for tier in tiers {
                groups = groups.flatMap { group -> [[(URL, FileIdentity)]] in
                    let hashes = parallelMap(group) { cache.hash(tier, of: $0.0, identity: $0.1) }
                    var byHash: [String: [(URL, FileIdentity)]] = [:]
                    for (file, hash) in zip(group, hashes) {
                        guard let hash else { continue } // unreadable: can't prove it's a duplicate
                        byHash[hash, default: []].append(file)
                    }
                    return byHash.values.filter { $0.count > 1 }
                }
                if groups.isEmpty || Task.isCancelled { break }
            }
            if Task.isCancelled { return [] }
            for group in groups {
                let digest = cache.hash(tiers.last!, of: group[0].0, identity: group[0].1) ?? UUID().uuidString
                items += makeGroup(group.map(\.0), size: size, digest: digest)
            }
        }
        cache.save(keeping: seen)
        Log.scan.info("Duplicates: \(candidates.count) size groups, hash cache \(cache.hits) hits / \(cache.misses) misses")
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

}

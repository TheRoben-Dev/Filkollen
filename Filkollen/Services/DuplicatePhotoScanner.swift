import Foundation

/// Finds byte-identical files. Size → head hash → tail hash → full SHA-256,
/// so most files are never fully read. In `.photos` mode it looks at images;
/// in `.files` mode at everything else of at least `minFileBytes`.
///
/// The Photos library package is skipped on purpose: deleting files inside it
/// corrupts the library. Photos has its own duplicate detection for that.
struct DuplicatePhotoScanner {
    enum Mode: Sendable { case photos, files }

    var context: ScanContext = .live
    var mode: Mode = .photos
    /// Smallest file `.files` mode compares; tiny duplicates aren't worth the review.
    var minFileBytes: Int64 = 1_048_576
    private var fm: FileManager { context.fileManager }
    private var home: URL { context.home }
    private var category: JunkCategory { mode == .photos ? .duplicatePhotos : .duplicateFiles }

    /// A Live Photo's video or a RAW original sitting next to an image.
    static let companionExtensions: Set<String> = ["mov", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf"]

    /// Folders full of identical files by design (dependencies, build output).
    static let skippedFolders: Set<String> = ["node_modules", "deriveddata", "pods", ".build", "vendor", "site-packages"]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp",
        "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf",
    ]

    var roots: [URL] {
        let folders = mode == .photos
            ? ["Pictures", "Desktop", "Downloads", "Documents"]
            : ["Desktop", "Downloads", "Documents", "Movies", "Music"]
        return folders.map { home.appendingPathComponent($0) }
    }

    private func isCandidate(_ ext: String, size: Int) -> Bool {
        switch mode {
        case .photos: return Self.imageExtensions.contains(ext)
        case .files: return !Self.imageExtensions.contains(ext) && Int64(size) >= minFileBytes
        }
    }

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress)

        // 1. Collect candidate images grouped by exact size.
        var bySize: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey]
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                if context.isCancelled { return [] }
                // Not always registered as a package (no Photos app, external drive), so skip by name too.
                let ext = url.pathExtension.lowercased()
                if ext == "photoslibrary" || ext == "photolibrary" { enumerator.skipDescendants(); continue }
                guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                if v.isDirectory == true {
                    if Self.skippedFolders.contains(url.lastPathComponent.lowercased()) { enumerator.skipDescendants() }
                    continue
                }
                guard v.isRegularFile == true, let size = v.fileSize, size > 0, isCandidate(ext, size: size) else { continue }
                throttle.report(url.abbreviatedPath)
                bySize[Int64(size), default: []].append(url)
            }
        }

        // 2. Same size → same first 64 KB → same last 64 KB → same full SHA-256.
        //    Most files drop out after reading 64 KB; hashes are cached by inode,
        //    size and modification time, so a re-scan reads only what changed.
        let cacheName = mode == .photos ? "photo-hash-cache.plist" : "file-hash-cache.plist"
        let cache = ContentHashCache(url: context.cacheDirectory?.appendingPathComponent(cacheName))
        var seen = Set<String>()
        var items: [JunkItem] = []
        let candidates = bySize.filter { $0.value.count > 1 }
        var compared = 0
        for (size, urls) in candidates {
            if context.isCancelled { return [] }
            let files = urls.compactMap { url in FileIdentity(url).map { (url, $0) } }
            seen.formUnion(files.map(\.1.key))
            compared += files.count
            throttle.report("Comparing \(compared.formatted()) \(mode == .photos ? "photos" : "files")…")

            var groups = [files]
            let tiers: [ContentHashCache.Kind] = size <= Int64(ContentHashCache.chunk) ? [.head] : [.head, .tail, .full]
            for tier in tiers {
                groups = groups.flatMap { group -> [[(URL, FileIdentity)]] in
                    let hashes = parallelMap(group) { [context] file in
                        context.isCancelled ? nil : cache.hash(tier, of: file.0, identity: file.1)
                    }
                    var byHash: [String: [(URL, FileIdentity)]] = [:]
                    for (file, hash) in zip(group, hashes) {
                        guard let hash else { continue } // unreadable: can't prove it's a duplicate
                        byHash[hash, default: []].append(file)
                    }
                    return byHash.values.filter { $0.count > 1 }
                }
                if groups.isEmpty || context.isCancelled { break }
            }
            if context.isCancelled { return [] }
            for group in groups {
                let digest = cache.hash(tiers.last!, of: group[0].0, identity: group[0].1) ?? UUID().uuidString
                items += makeGroup(group.map(\.0), size: size, digest: digest)
            }
        }
        cache.save(keeping: seen)
        Log.scan.info("Duplicates (\(category.rawValue, privacy: .public)): \(candidates.count) size groups, hash cache \(cache.hits) hits / \(cache.misses) misses")
        return items.sorted { $0.group != $1.group ? $0.group < $1.group : ($0.isKeeper && !$1.isKeeper) }
    }

    private static let groupKeys: Set<URLResourceKey> = [
        .creationDateKey, .totalFileAllocatedSizeKey, .fileContentIdentifierKey, .mayShareFileContentKey, .linkCountKey,
    ]

    /// The Live Photo video or RAW file next to an image, if any ("IMG_1.HEIC" → "IMG_1.MOV").
    func companion(of url: URL) -> URL? {
        guard mode == .photos else { return nil }
        let base = url.deletingPathExtension().lastPathComponent.lowercased()
        let own = url.pathExtension.lowercased()
        let siblings = (try? fm.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return siblings.first { name in
            let ext = (name as NSString).pathExtension.lowercased()
            return ext != own && Self.companionExtensions.contains(ext)
                && (name as NSString).deletingPathExtension.lowercased() == base
        }.map { url.deletingLastPathComponent().appendingPathComponent($0) }
    }

    /// Keeps one copy and marks the rest for removal: a copy with its Live Photo
    /// video or RAW original beside it first (it's the one in its original place),
    /// then the oldest. A copy that's an APFS clone of the kept one shares its
    /// blocks, so trashing it gives back almost nothing; it's still listed, but
    /// counted as 0 reclaimable. Photo copies are pre-selected; other files aren't.
    private func makeGroup(_ urls: [URL], size: Int64, digest: String) -> [JunkItem] {
        let dated = urls.map { url -> (url: URL, created: Date, values: URLResourceValues?, companion: URL?) in
            let values = try? url.resourceValues(forKeys: Self.groupKeys)
            return (url, values?.creationDate ?? .distantFuture, values, companion(of: url))
        }.sorted {
            let a = $0.companion == nil ? 1 : 0, b = $1.companion == nil ? 1 : 0
            return (a, $0.created, $0.url.path.count) < (b, $1.created, $1.url.path.count)
        }
        let keeperContent = dated.first?.values?.fileContentIdentifier

        return dated.enumerated().map { index, entry in
            let v = entry.values
            let isClone = index != 0 && keeperContent != nil && v?.fileContentIdentifier == keeperContent
            let shares = v?.mayShareFileContent == true || (v?.linkCount ?? 1) > 1
            var detail = entry.url.deletingLastPathComponent().abbreviatedPath
            if let companion = entry.companion {
                let kind = companion.pathExtension.lowercased() == "mov" ? "Live Photo video" : "RAW original"
                detail += index == 0 ? " · kept with its \(kind)" : " · its \(kind) (\(companion.lastPathComponent)) stays"
            }
            if isClone { detail += " · clone of the kept copy, frees almost no space" }
            return JunkItem(
                url: entry.url,
                size: v?.totalFileAllocatedSize.map(Int64.init) ?? size,
                category: category,
                group: String(digest.prefix(16)),
                detail: detail,
                isSelected: index != 0 && mode == .photos,
                isKeeper: index == 0,
                modified: entry.created,
                reclaimable: index != 0 && (isClone || shares) ? 0 : nil
            )
        }
    }

}

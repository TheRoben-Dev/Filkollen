import Foundation

/// Big files in your home folder that might not be worth keeping. Never
/// pre-selected: these are your files, not junk.
struct LargeFileScanner {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }
    private var home: URL { context.home }

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        let minSize = context.largeFileMinBytes
        let keys: [URLResourceKey] = [
            .isRegularFileKey, .totalFileAllocatedSizeKey, .contentAccessDateKey, .contentModificationDateKey,
            .mayShareFileContentKey, .linkCountKey,
        ]
        let keySet = Set(keys)
        let skipTopLevel: Set<String> = ["Library", ".Trash"]
        var items: [JunkItem] = []

        guard let enumerator = fm.enumerator(
            at: home, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        // The enumerator may hand back /private/var/... for /var/..., so the top-level
        // folder comes from the walk itself rather than from comparing path components.
        var currentTop = "Home"
        for case let url as URL in enumerator {
            if context.isCancelled { return [] }
            if enumerator.level == 1 {
                if skipTopLevel.contains(url.lastPathComponent) { enumerator.skipDescendants(); continue }
                currentTop = url.lastPathComponent
            }
            throttle.report(url.abbreviatedPath)
            guard let v = try? url.resourceValues(forKeys: keySet), v.isRegularFile == true,
                  let size = v.totalFileAllocatedSize.map(Int64.init), size >= minSize else { continue }

            let lastUsed = v.contentAccessDate ?? v.contentModificationDate
            let top = enumerator.level == 1 ? "Home" : currentTop
            items.append(JunkItem(
                url: url,
                size: size,
                category: .largeFiles,
                group: top,
                detail: lastUsed.map { "Last opened \($0.formatted(.relative(presentation: .named)))" } ?? url.abbreviatedPath,
                isSelected: false,
                modified: lastUsed,
                // A clone or an extra hard link gives nothing back when deleted.
                reclaimable: v.mayShareFileContent == true || (v.linkCount ?? 1) > 1 ? 0 : nil
            ))
        }
        return items.sorted { $0.size > $1.size }
    }
}

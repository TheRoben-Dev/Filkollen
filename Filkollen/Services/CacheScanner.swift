import AppKit

/// Finds user-level caches, logs, old temp files and developer build junk.
struct CacheScanner {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    /// Cache folders that are either tiny-but-important or known to break things when removed.
    /// (`com.apple.*` is refused by SafetyGuard anyway.)
    private let skipNames: Set<String> = [
        "CloudKit", "FamilyCircle", "Filkollen", "dev.theroben.Filkollen",
    ]

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress)
        var items: [JunkItem] = []

        items += children(of: context.library("Caches"), group: "User Caches", throttle: throttle)
        items += children(of: context.library("Logs"), group: "User Logs", throttle: throttle)
        items += children(
            of: context.library("Developer/Xcode/DerivedData"),
            group: "Xcode Derived Data", throttle: throttle
        )
        if Task.isCancelled { return [] }
        items += oldTempFiles(throttle: throttle)

        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    private func children(
        of dir: URL, group: String, throttle: ProgressThrottle
    ) -> [JunkItem] {
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            Log.scan.notice("Can't list \(dir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        return entries.compactMap { url in
            guard !Task.isCancelled,
                  !skipNames.contains(url.lastPathComponent),
                  fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.abbreviatedPath)
            let friendly = AppNames.friendlyName(for: url.lastPathComponent)
            return JunkItem(
                url: url,
                size: FileSizer.allocatedSize(of: url),
                category: .systemJunk,
                group: group,
                detail: friendly ?? url.abbreviatedPath,
                modified: FileSizer.modificationDate(url)
            )
        }
    }

    private func oldTempFiles(throttle: ProgressThrottle) -> [JunkItem] {
        guard let entries = try? fm.contentsOfDirectory(
            at: context.temp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = context.now().addingTimeInterval(-context.tempMinAge)
        return entries.compactMap { url in
            guard !Task.isCancelled,
                  let date = FileSizer.modificationDate(url), date < cutoff,
                  fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.lastPathComponent)
            return JunkItem(
                url: url,
                size: FileSizer.allocatedSize(of: url),
                category: .systemJunk,
                group: "Temporary Files",
                detail: "Untouched since \(date.formatted(date: .abbreviated, time: .omitted))",
                modified: date
            )
        }
    }
}

enum AppNames {
    /// Turns "com.spotify.client" into "Spotify" when the app is installed.
    static func friendlyName(for bundleIDLike: String) -> String? {
        guard bundleIDLike.contains("."),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIDLike) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

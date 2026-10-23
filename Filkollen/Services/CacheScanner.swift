import AppKit

/// Finds user-level caches, logs, old temp files and developer build junk.
struct CacheScanner: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    /// Cache folders that are either tiny-but-important or known to break things when removed.
    /// (`com.apple.*` is refused by SafetyGuard anyway.)
    private let skipNames: Set<String> = [
        "CloudKit", "FamilyCircle", "Filkollen", "dev.theroben.Filkollen",
    ]

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let skipNames = self.skipNames.union(DeveloperScanner.claimedCacheNames)
        let throttle = ProgressThrottle(progress, counting: true)
        let running = context.runningApps()
        var items: [JunkItem] = []

        items += children(of: context.library("Caches"), group: "User Caches", skip: skipNames, running: running, throttle: throttle)
        items += children(of: context.library("Logs"), group: "User Logs", skip: self.skipNames, running: running, throttle: throttle)
        items += children(
            of: context.library("Developer/Xcode/DerivedData"),
            group: "Xcode Derived Data", skip: [], running: [], throttle: throttle
        )
        if context.isCancelled { return [] }
        items += oldTempFiles(throttle: throttle)

        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    private func children(
        of dir: URL, group: String, skip skipNames: Set<String>, running: [ScanContext.RunningApp], throttle: ProgressThrottle
    ) -> [JunkItem] {
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        } catch {
            Log.scan.notice("Can't list \(dir.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }

        // Measuring is the slow part (a full walk per folder), so folders are measured in parallel.
        return parallelMap(entries) { url -> JunkItem? in
            guard !context.isCancelled,
                  !skipNames.contains(url.lastPathComponent),
                  fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.abbreviatedPath)
            let friendly = AppNames.friendlyName(for: url.lastPathComponent)
            let measured = FileSizer.measure(url, fileManager: fm)
            // A running app may be writing to its cache right now; let the user decide.
            if let owner = RunningApps.owner(of: url.lastPathComponent, in: running) {
                return JunkItem(
                    url: url,
                    size: measured.allocated,
                    category: .systemJunk,
                    group: group,
                    detail: "\(owner.name.isEmpty ? owner.bundleID : owner.name) is running. Quit it first to clean this safely.",
                    isSelected: false,
                    modified: FileSizer.modificationDate(url),
                    inUseBy: owner.name.isEmpty ? owner.bundleID : owner.name,
                    reclaimable: measured.reclaimable
                )
            }
            return JunkItem(
                url: url,
                size: measured.allocated,
                category: .systemJunk,
                group: group,
                detail: friendly ?? url.abbreviatedPath,
                modified: FileSizer.modificationDate(url),
                reclaimable: measured.reclaimable
            )
        }.compactMap { $0 }
    }

    private func oldTempFiles(throttle: ProgressThrottle) -> [JunkItem] {
        guard let entries = try? fm.contentsOfDirectory(
            at: context.temp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = context.now().addingTimeInterval(-context.tempMinAge)
        return entries.compactMap { url in
            guard !context.isCancelled,
                  let date = FileSizer.modificationDate(url), date < cutoff,
                  fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.lastPathComponent)
            let measured = FileSizer.measure(url, fileManager: fm)
            return JunkItem(
                url: url,
                size: measured.allocated,
                category: .systemJunk,
                group: "Temporary Files",
                detail: "Untouched since \(date.formatted(date: .abbreviated, time: .omitted))",
                modified: date,
                reclaimable: measured.reclaimable
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

import AppKit

/// Finds user-level caches, logs, old temp files and developer build junk.
struct CacheScanner {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Cache folders that are either tiny-but-important or known to break things when removed.
    private let skipNames: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.akd", "com.apple.HomeKit",
        "FamilyCircle", "com.apple.nsurlsessiond", "com.apple.ap.adprivacyd",
        "com.apple.containermanagerd", "Filkollen", "dev.theroben.Filkollen",
    ]

    /// Temp files younger than this are probably in use.
    private let tempMinAge: TimeInterval = 3 * 24 * 3600

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress)
        var items: [JunkItem] = []

        items += children(of: home.appendingPathComponent("Library/Caches"), group: "User Caches", throttle: throttle)
        items += children(of: home.appendingPathComponent("Library/Logs"), group: "User Logs", throttle: throttle)
        items += children(
            of: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
            group: "Xcode Derived Data", throttle: throttle
        )
        items += oldTempFiles(throttle: throttle)

        return items.filter { $0.size > 0 }.sorted { $0.size > $1.size }
    }

    private func children(of dir: URL, group: String, throttle: ProgressThrottle) -> [JunkItem] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            guard !skipNames.contains(url.lastPathComponent),
                  fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.abbreviatedPath)
            return JunkItem(
                url: url,
                size: FileSizer.allocatedSize(of: url),
                category: .systemJunk,
                group: group,
                detail: AppNames.friendlyName(for: url.lastPathComponent) ?? url.abbreviatedPath,
                modified: FileSizer.modificationDate(url)
            )
        }
    }

    private func oldTempFiles(throttle: ProgressThrottle) -> [JunkItem] {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        guard let entries = try? fm.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-tempMinAge)
        return entries.compactMap { url in
            guard let date = FileSizer.modificationDate(url), date < cutoff,
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

import AppKit

/// Finds support files whose owning app (identified by bundle ID) is no longer installed.
///
/// Only entries that look like reverse-DNS bundle IDs are considered, which keeps
/// false positives low: plain-named folders like "Spotify" are left alone in v1.
struct LeftoverScanner {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    private let locations: [(path: String, label: String)] = [
        ("Library/Application Support", "Application Support"),
        ("Library/Caches", "Caches"),
        ("Library/Preferences", "Preferences"),
        ("Library/Containers", "Containers"),
        ("Library/Group Containers", "Group Containers"),
        ("Library/Saved Application State", "Saved State"),
        ("Library/HTTPStorages", "HTTP Storage"),
        ("Library/WebKit", "WebKit Data"),
        ("Library/Cookies", "Cookies"),
        ("Library/Logs", "Logs"),
        ("Library/LaunchAgents", "Launch Agents"),
    ]

    private static let bundleIDPattern = try! NSRegularExpression(
        pattern: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9_-]+){2,}$"
    )

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress)
        throttle.report("Indexing installed apps…")
        let installed = installedBundleIDs()
        var items: [JunkItem] = []

        for location in locations {
            if Task.isCancelled { return [] }
            let dir = context.home.appendingPathComponent(location.path)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                if Task.isCancelled { return [] }
                throttle.report(url.abbreviatedPath)
                guard let bundleID = Self.bundleID(from: url.lastPathComponent),
                      !isInstalled(bundleID, installed: installed),
                      fm.isDeletableFile(atPath: url.path) else { continue }

                let size = FileSizer.allocatedSize(of: url)
                guard size > 0 else { continue }
                items.append(JunkItem(
                    url: url,
                    size: size,
                    category: .appLeftovers,
                    group: bundleID,
                    detail: location.label,
                    modified: FileSizer.modificationDate(url)
                ))
            }
        }
        return items.sorted { ($0.group, $1.size) < ($1.group, $0.size) }
    }

    // MARK: Bundle ID extraction

    static func bundleID(from name: String) -> String? {
        var id = name
        for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) {
            id = String(id.dropLast(suffix.count))
        }
        // Group containers: "ABCDE12345.com.foo.bar" or "group.com.foo.bar"
        if id.hasPrefix("group.") { id = String(id.dropFirst(6)) }
        let parts = id.split(separator: ".")
        if let first = parts.first, first.count == 10, first.allSatisfy({ $0.isUppercase || $0.isNumber }),
           parts.count > 2 {
            id = parts.dropFirst().joined(separator: ".")
        }

        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("apple.") || lower.hasPrefix("systemgroup.") {
            return nil
        }
        // Global/shared preference files that aren't owned by a single app.
        if lower.hasPrefix(".global") || lower.hasPrefix("loginwindow") || lower.hasPrefix("pbs") {
            return nil
        }
        let range = NSRange(id.startIndex..., in: id)
        guard bundleIDPattern.firstMatch(in: id, range: range) != nil else { return nil }
        return id
    }

    // MARK: Installed apps

    private func isInstalled(_ bundleID: String, installed: Set<String>) -> Bool {
        let id = bundleID.lowercased()
        if installed.contains(id) { return true }
        // Helpers / extensions ("com.foo.app.helper") and shared prefixes ("com.foo" for "com.foo.app").
        if installed.contains(where: { id.hasPrefix($0 + ".") || $0.hasPrefix(id + ".") }) { return true }
        // Same vendor + product root, e.g. com.microsoft.teams2 vs com.microsoft.teams
        // is intentionally *not* matched; LaunchServices is the final word:
        return context.isRegisteredApp(bundleID)
    }

    private func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for root in context.appRoots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 3 { enumerator.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id.lowercased()) }
            }
        }
        for app in context.runningApps() {
            ids.insert(app.bundleID.lowercased())
        }
        return ids
    }
}

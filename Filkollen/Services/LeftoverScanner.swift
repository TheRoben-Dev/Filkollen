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
        let throttle = ProgressThrottle(progress, counting: true)
        throttle.report("Indexing installed apps…")
        let (installed, installedNames) = installedApps()
        var items: [JunkItem] = []

        for location in locations {
            if context.isCancelled { return [] }
            let dir = context.home.appendingPathComponent(location.path)
            guard let entries = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }

            for url in entries {
                if context.isCancelled { return [] }
                throttle.report(url.abbreviatedPath)
                guard let bundleID = Self.bundleID(from: url.lastPathComponent),
                      !isInstalled(bundleID, installed: installed),
                      fm.isDeletableFile(atPath: url.path) else { continue }

                let measured = FileSizer.measure(url, fileManager: fm)
                guard measured.allocated > 0 else { continue }
                items.append(JunkItem(
                    url: url,
                    size: measured.allocated,
                    category: .appLeftovers,
                    group: bundleID,
                    detail: location.label,
                    modified: FileSizer.modificationDate(url),
                    reclaimable: measured.reclaimable
                ))
            }
        }
        if context.plainNameLeftovers {
            items += plainNameLeftovers(knownGone: items, installedNames: installedNames, throttle: throttle)
        }
        return items.sorted { ($0.group, $1.size) < ($1.group, $0.size) }
    }

    // MARK: Plain-name leftovers

    /// Folders like "Application Support/Spotify" that aren't named by bundle ID.
    /// High confidence when the name matches an app whose bundle-ID leftovers
    /// were also found (so it's known to be gone); low otherwise. Low-confidence
    /// items are never pre-selected.
    private func plainNameLeftovers(knownGone: [JunkItem], installedNames: Set<String>, throttle: ProgressThrottle) -> [JunkItem] {
        let goneNames = Set(knownGone.flatMap { Self.nameTokens(ofBundleID: $0.group) })
        var items: [JunkItem] = []
        for location in Self.plainNameLocations {
            let dir = context.home.appendingPathComponent(location.path)
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in entries {
                if context.isCancelled { return [] }
                let name = url.lastPathComponent
                let key = Self.normalizedName(name)
                guard Self.bundleID(from: name) == nil, !name.contains("."),
                      key.count >= 3, !Self.sharedFolderNames.contains(key),
                      !installedNames.contains(key), fm.isDeletableFile(atPath: url.path) else { continue }
                throttle.report(url.abbreviatedPath)
                let measured = FileSizer.measure(url, fileManager: fm)
                guard measured.allocated > 0 else { continue }
                let high = goneNames.contains(key)
                items.append(JunkItem(
                    url: url,
                    size: measured.allocated,
                    category: .appLeftovers,
                    group: name,
                    detail: location.label + (high ? " · matches a removed app" : " · no installed app by this name; check before removing"),
                    isSelected: high,
                    modified: FileSizer.modificationDate(url),
                    reclaimable: measured.reclaimable,
                    confidence: high ? .high : .low
                ))
            }
        }
        return items
    }

    private static let plainNameLocations: [(path: String, label: String)] = [
        ("Library/Application Support", "Application Support"),
        ("Library/Caches", "Caches"),
        ("Library/Logs", "Logs"),
    ]

    /// Plain-named folders shared by many apps or owned by macOS; never guessed at.
    static let sharedFolderNames: Set<String> = [
        "crashreporter", "diagnosticreports", "cloudkit", "familycircle", "knowledge", "addressbook",
        "callhistorydb", "callhistorytransactions", "icloud", "syncservices", "dock", "mobilesync",
        "fileprovider", "animoji", "diskimages", "google", "microsoft", "mozilla", "adobe", "jetbrains",
        "apple", "filkollen", "homebrew", "geod", "identityservices", "accounts", "metadata",
        "networkserviceproxy", "quicklook", "spotlight", "siri", "assistant", "audio", "ubiquity",
        "videoconference", "webkit", "default", "temp", "tmp", "cache", "caches", "logs", "plugins",
    ]

    /// "Visual Studio Code" → "visualstudiocode"
    static func normalizedName(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// "com.spotify.client" → ["spotify"]; generic words are dropped.
    static func nameTokens(ofBundleID id: String) -> [String] {
        let generic: Set<String> = ["app", "mac", "macos", "osx", "client", "desktop", "helper", "agent", "com", "org", "net", "io"]
        return id.lowercased().split(separator: ".").dropFirst().map(String.init)
            .map(normalizedName).filter { $0.count >= 3 && !generic.contains($0) }
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

    /// Installed bundle IDs, plus normalized names (display name, executable,
    /// bundle-ID words) used to rule out plain-name leftovers.
    private func installedApps() -> (ids: Set<String>, names: Set<String>) {
        var ids = Set<String>()
        var names = Set<String>()
        for root in context.appRoots {
            guard let enumerator = fm.enumerator(
                at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 3 { enumerator.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                names.insert(Self.normalizedName(url.deletingPathExtension().lastPathComponent))
                guard let bundle = Bundle(url: url) else { continue }
                if let id = bundle.bundleIdentifier {
                    ids.insert(id.lowercased())
                    names.formUnion(Self.nameTokens(ofBundleID: id))
                }
                if let exe = bundle.infoDictionary?["CFBundleExecutable"] as? String { names.insert(Self.normalizedName(exe)) }
                if let display = bundle.infoDictionary?["CFBundleName"] as? String { names.insert(Self.normalizedName(display)) }
            }
        }
        for app in context.runningApps() {
            ids.insert(app.bundleID.lowercased())
            names.insert(Self.normalizedName(app.name))
            names.formUnion(Self.nameTokens(ofBundleID: app.bundleID))
            if let exe = app.executable { names.insert(Self.normalizedName(exe)) }
        }
        return (ids, names)
    }
}

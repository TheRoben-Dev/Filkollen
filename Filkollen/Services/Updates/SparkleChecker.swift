import Foundation

/// Most apps outside the App Store update themselves with Sparkle and publish
/// an "appcast" feed (SUFeedURL in Info.plist). Reading it tells us whether a
/// newer version exists without touching the app.
enum SparkleChecker {
    struct InstalledApp: Sendable {
        let url: URL
        let name: String
        let shortVersion: String
        let build: String
        let feed: URL
    }

    static func check() async -> [AppUpdate] {
        let apps = installedApps()
        return await withTaskGroup(of: AppUpdate?.self) { group in
            for app in apps { group.addTask { await check(app) } }
            var updates: [AppUpdate] = []
            for await update in group { if let update { updates.append(update) } }
            return updates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    static func installedApps() -> [InstalledApp] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var apps: [InstalledApp] = []
        for root in roots {
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 2 { e.skipDescendants(); continue }
                guard url.pathExtension == "app", let bundle = Bundle(url: url),
                      let info = bundle.infoDictionary,
                      let feedString = info["SUFeedURL"] as? String,
                      let feed = URL(string: feedString.trimmingCharacters(in: .whitespaces)),
                      feed.scheme == "https" || feed.scheme == "http" else { continue }
                apps.append(InstalledApp(
                    url: url,
                    name: fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""),
                    shortVersion: info["CFBundleShortVersionString"] as? String ?? "",
                    build: info["CFBundleVersion"] as? String ?? "",
                    feed: feed
                ))
            }
        }
        return apps
    }

    private static func check(_ app: InstalledApp) async -> AppUpdate? {
        var request = URLRequest(url: app.feed, timeoutInterval: 15)
        request.setValue("Filkollen/1.0 Sparkle-compatible", forHTTPHeaderField: "User-Agent")
        guard let response = try? await URLSession.shared.data(for: request) else { return nil }
        let data = response.0
        let items = AppcastParser.parse(data)
            .filter { $0.minimumSystem.map { ProcessInfo.processInfo.isOperatingSystemAtLeast(parse(os: $0)) } ?? true }

        // Prefer comparing marketing versions; fall back to build numbers.
        if let best = items.max(by: { order($0, $1) }) {
            let newer: Bool
            if let short = best.shortVersion, !app.shortVersion.isEmpty {
                newer = VersionCompare.isNewer(short, than: app.shortVersion)
            } else if let build = best.version, !app.build.isEmpty {
                newer = VersionCompare.isNewer(build, than: app.build)
            } else {
                newer = false
            }
            guard newer else { return nil }
            return AppUpdate(
                name: app.name,
                installed: app.shortVersion.isEmpty ? app.build : app.shortVersion,
                available: best.shortVersion ?? best.version ?? "?",
                source: .apps,
                appURL: app.url,
                infoURL: best.notesURL ?? best.downloadURL
            )
        }
        return nil
    }

    private static func order(_ a: AppcastParser.Item, _ b: AppcastParser.Item) -> Bool {
        let va = a.version ?? a.shortVersion ?? "", vb = b.version ?? b.shortVersion ?? ""
        return vb.compare(va, options: .numeric) == .orderedDescending
    }

    private static func parse(os: String) -> OperatingSystemVersion {
        let p = os.split(separator: ".").compactMap { Int($0) }
        return OperatingSystemVersion(majorVersion: p.first ?? 0, minorVersion: p.count > 1 ? p[1] : 0, patchVersion: p.count > 2 ? p[2] : 0)
    }
}

/// Minimal Sparkle appcast reader: handles versions given as enclosure
/// attributes (Sparkle 1) or as elements (Sparkle 2).
final class AppcastParser: NSObject, XMLParserDelegate {
    struct Item {
        var version: String?
        var shortVersion: String?
        var minimumSystem: String?
        var downloadURL: URL?
        var notesURL: URL?
    }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" { current = Item() }
        guard current != nil else { return }
        if name == "enclosure" {
            current?.version = current?.version ?? attributes["sparkle:version"]
            current?.shortVersion = current?.shortVersion ?? attributes["sparkle:shortVersionString"]
            if let u = attributes["url"] { current?.downloadURL = URL(string: u) }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item":
            if let current { items.append(current) }
            current = nil
        case "sparkle:version" where !value.isEmpty: current?.version = value
        case "sparkle:shortVersionString" where !value.isEmpty: current?.shortVersion = value
        case "sparkle:minimumSystemVersion" where !value.isEmpty: current?.minimumSystem = value
        case "sparkle:releaseNotesLink", "link":
            if current?.notesURL == nil, let u = URL(string: value), u.scheme?.hasPrefix("http") == true {
                current?.notesURL = u
            }
        default: break
        }
        text = ""
    }
}

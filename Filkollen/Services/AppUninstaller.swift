import AppKit

/// Finds everything an app left in your home folder so it can be removed with
/// the app. Apple's own apps are refused. Apps in /Applications are outside
/// what SafetyGuard allows without the privileged helper, so for those
/// Filkollen removes the support files and you drag the app to the Trash.
struct AppUninstaller: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    struct App: Identifiable, Hashable, Sendable {
        var id: URL { url }
        let url: URL
        let name: String
        let bundleID: String
        let executable: String?
        let version: String?
        /// Inside the home folder, so Filkollen can move the bundle itself.
        let canTrashBundle: Bool
    }

    enum Refusal: Error, LocalizedError, Equatable {
        case notAnApp, apple, systemProtected

        var errorDescription: String? {
            switch self {
            case .notAnApp: return "That isn't an app."
            case .apple: return "Apple's own apps are part of macOS and can't be uninstalled here."
            case .systemProtected: return "This app is protected by macOS and can't be removed."
            }
        }
    }

    /// Every removable app in the app folders, alphabetically.
    func installedApps() -> [App] {
        var apps: [App] = []
        for root in context.appRoots where !root.path.hasPrefix("/System") {
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in entries where url.pathExtension == "app" {
                if let app = try? app(at: url) { apps.append(app) }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func app(at url: URL) throws -> App {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else {
            throw Refusal.notAnApp
        }
        if id.lowercased().hasPrefix("com.apple.") { throw Refusal.apple }
        if url.path.hasPrefix("/System/") { throw Refusal.systemProtected }
        let info = bundle.infoDictionary ?? [:]
        let home = SafetyGuard.fold(SafetyGuard.canonicalPath(context.home.path) ?? context.home.path)
        let path = SafetyGuard.fold(SafetyGuard.canonicalPath(url.path) ?? url.path)
        return App(
            url: url,
            name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            bundleID: id,
            executable: info["CFBundleExecutable"] as? String,
            version: info["CFBundleShortVersionString"] as? String,
            canTrashBundle: path.hasPrefix(home + "/")
        )
    }

    private static let locations: [(path: String, label: String)] = [
        ("Library/Application Support", "Application Support"),
        ("Library/Caches", "Caches"),
        ("Library/Preferences", "Preferences"),
        ("Library/Preferences/ByHost", "Preferences"),
        ("Library/Containers", "Container"),
        ("Library/Group Containers", "Group Container"),
        ("Library/Saved Application State", "Saved State"),
        ("Library/HTTPStorages", "HTTP Storage"),
        ("Library/WebKit", "WebKit Data"),
        ("Library/Cookies", "Cookies"),
        ("Library/Logs", "Logs"),
        ("Library/LaunchAgents", "Launch Agent"),
        ("Library/Application Scripts", "Scripts"),
    ]

    /// Where apps commonly keep folders named after themselves rather than their bundle ID.
    private static let plainNameLocations: Set<String> = [
        "Library/Application Support", "Library/Caches", "Library/Logs",
    ]

    /// The app (when Filkollen may move it) plus its support files.
    func remnants(of app: App) -> [JunkItem] {
        let id = app.bundleID.lowercased()
        // Plain-name folders ("Application Support/Spotify") match only the app's own
        // name, never a shared vendor or system folder name.
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent].map { $0.lowercased() })
            .filter { !LeftoverScanner.sharedFolderNames.contains(LeftoverScanner.normalizedName($0)) }
        var items: [JunkItem] = []

        if app.canTrashBundle {
            let m = FileSizer.measure(app.url, fileManager: fm)
            items.append(JunkItem(url: app.url, size: m.allocated, category: .appLeftovers, group: app.name,
                                  detail: "The app itself", reclaimable: m.reclaimable, requiresClosed: [app.bundleID]))
        }

        for location in Self.locations {
            if context.isCancelled { return [] }
            let dir = context.home.appendingPathComponent(location.path)
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let plainNames = Self.plainNameLocations.contains(location.path)
            for url in entries where Self.belongs(url.lastPathComponent, to: id, names: names, plainNames: plainNames) {
                if location.label == "Launch Agent", !launchAgent(url, belongsTo: id) { continue }
                let m = FileSizer.measure(url, fileManager: fm)
                items.append(JunkItem(
                    url: url, size: m.allocated, category: .appLeftovers, group: app.name,
                    detail: location.label, modified: FileSizer.modificationDate(url),
                    reclaimable: m.reclaimable, requiresClosed: [app.bundleID]
                ))
            }
        }
        return items
    }

    /// `com.vendor.app`, `com.vendor.app.helper`, `com.vendor.app.plist`, `TEAMID.com.vendor.app`,
    /// `group.com.vendor.app`, `com.vendor.app.<UUID>.plist` (ByHost), or the app's exact name.
    static func belongs(_ entry: String, to bundleID: String, names: Set<String>, plainNames: Bool) -> Bool {
        let e = entry.lowercased()
        var base = e
        for suffix in [".plist", ".savedstate", ".binarycookies"] where base.hasSuffix(suffix) {
            base = String(base.dropLast(suffix.count))
        }
        let stripped = LeftoverScanner.bundleID(from: entry)?.lowercased()
        for candidate in [base, stripped].compactMap({ $0 }) {
            if candidate == bundleID || candidate.hasPrefix(bundleID + ".") { return true }
        }
        return plainNames && names.contains(e)
    }

    /// A launch agent belongs to the app when its label is the bundle ID or one of
    /// its helpers. A file named like the app but labelled for something else is left alone.
    private func launchAgent(_ plist: URL, belongsTo id: String) -> Bool {
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let label = (dict["Label"] as? String)?.lowercased() else {
            return false
        }
        return label == id || label.hasPrefix(id + ".")
    }
}

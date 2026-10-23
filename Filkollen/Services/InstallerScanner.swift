import Foundation

/// Disk images, packages and archives in Downloads that have done their job:
/// the app they install is already in /Applications, or they've sat unopened
/// for a long time.
struct InstallerScanner: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "zip", "xip"]

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        let installed = installedAppNames()
        let cutoff = context.now().addingTimeInterval(-context.installerMinAge)
        let downloads = context.home.appendingPathComponent("Downloads")
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentAccessDateKey, .contentModificationDateKey, .creationDateKey]

        guard let enumerator = fm.enumerator(
            at: downloads, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }

        var items: [JunkItem] = []
        for case let url as URL in enumerator {
            if context.isCancelled { return [] }
            // Downloads and one level of subfolders; deeper is probably a project, not a download.
            if enumerator.level > 2 { enumerator.skipDescendants(); continue }
            guard Self.extensions.contains(url.pathExtension.lowercased()),
                  let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            throttle.report(url.abbreviatedPath)

            let lastUsed = [v.contentAccessDate, v.contentModificationDate, v.creationDate].compactMap { $0 }.max()
            let app = Self.matchingApp(for: url.deletingPathExtension().lastPathComponent, installed: installed)
            let isOld = lastUsed.map { $0 < cutoff } ?? false
            guard app != nil || isOld else { continue }

            let measured = FileSizer.measure(url, fileManager: fm)
            let age = lastUsed.map { "last opened \($0.formatted(.relative(presentation: .named)))" } ?? ""
            items.append(JunkItem(
                url: url,
                size: measured.allocated,
                category: .oldInstallers,
                group: app != nil ? "Already installed" : "Old downloads",
                detail: app.map { "\($0) is installed" + (age.isEmpty ? "" : ", \(age)") } ?? age.capitalizedFirst,
                // An installer for an app you have is safe to drop; an old archive might be the only copy of something.
                isSelected: app != nil && url.pathExtension.lowercased() != "zip",
                modified: lastUsed,
                reclaimable: measured.reclaimable
            ))
        }
        return items.sorted { $0.size > $1.size }
    }

    /// Display names of installed apps, normalized for matching.
    private func installedAppNames() -> [String: String] {
        var names: [String: String] = [:]
        for root in context.appRoots {
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in entries where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let key = Self.normalize(name)
                if key.count >= 3 { names[key] = name }
            }
        }
        return names
    }

    /// "Firefox 131.0.2" → "firefox", "GoogleChrome" → "googlechrome", "VSCode-darwin-universal" → "vscodedarwinuniversal"
    static func normalize(_ name: String) -> String {
        var base = name.lowercased()
        // Drop a trailing version / build / arch part: "foo-1.2.3", "foo_v2", "foo (1)".
        if let r = base.range(of: #"(?<=[a-z])[\s._\-(]*v?\d[\w.\-() ]*$"#, options: .regularExpression) {
            base.removeSubrange(r)
        }
        return base.filter { $0.isLetter || $0.isNumber }
    }

    /// The installed app this installer is for, if any. Requires the app's name
    /// (4+ characters) to match the start of the installer's name.
    static func matchingApp(for installerName: String, installed: [String: String]) -> String? {
        let key = normalize(installerName)
        guard !key.isEmpty else { return nil }
        if let exact = installed[key] { return exact }
        let candidates = installed.filter { $0.key.count >= 4 && key.hasPrefix($0.key) }
        return candidates.max { $0.key.count < $1.key.count }?.value
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

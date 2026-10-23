import Foundation

/// Browser caches (and Mail's attachment copies) only: never history, cookies, passwords, extensions or
/// profiles. Only folders on an explicit per-browser list are reported, and
/// each item requires its browser to be closed, which the Cleaner checks
/// again at clean time.
struct BrowserScanner: Sendable {
    var context: ScanContext = .live
    private var fm: FileManager { context.fileManager }

    struct Browser: Sendable {
        let name: String
        let bundleIDs: [String]
        /// Whole folders under ~/Library/Caches.
        let cacheFolders: [String]
        /// Chromium "User Data" folder under ~/Library/Application Support, if any.
        var chromiumUserData: String? = nil
        /// Firefox-style profiles folder under ~/Library/Caches whose profiles hold cache folders.
        var firefoxProfiles: String? = nil
        /// Other whole cache folders, relative to ~/Library.
        var libraryFolders: [String] = []
        var explanation = "Cached web content. The browser downloads it again as you browse; nothing you saved is affected."
    }

    /// Per-profile Chromium folders that are pure caches.
    static let chromiumCacheNames = ["Cache", "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache"]
    /// Chromium top-level (shared) cache folders inside User Data.
    static let chromiumSharedCacheNames = ["GrShaderCache", "ShaderCache", "GraphiteDawnCache", "component_crx_cache"]
    static let firefoxCacheNames = ["cache2", "startupCache", "thumbnails", "jumpListCache"]

    static let browsers: [Browser] = [
        Browser(name: "Google Chrome", bundleIDs: ["com.google.Chrome"],
                cacheFolders: ["Google/Chrome"], chromiumUserData: "Google/Chrome"),
        Browser(name: "Microsoft Edge", bundleIDs: ["com.microsoft.edgemac"],
                cacheFolders: ["Microsoft Edge"], chromiumUserData: "Microsoft Edge"),
        Browser(name: "Brave", bundleIDs: ["com.brave.Browser"],
                cacheFolders: ["BraveSoftware/Brave-Browser"], chromiumUserData: "BraveSoftware/Brave-Browser"),
        Browser(name: "Arc", bundleIDs: ["company.thebrowser.Browser"],
                cacheFolders: ["Arc"], chromiumUserData: "Arc/User Data"),
        Browser(name: "Firefox", bundleIDs: ["org.mozilla.firefox"],
                cacheFolders: [], firefoxProfiles: "Firefox/Profiles"),
        // The two Apple entries rely on exact-folder SafetyGuard exceptions (see docs/SAFETY.md).
        Browser(name: "Safari", bundleIDs: ["com.apple.Safari"],
                cacheFolders: ["com.apple.Safari"],
                libraryFolders: ["Containers/com.apple.Safari/Data/Library/Caches"]),
        Browser(name: "Mail Downloads", bundleIDs: ["com.apple.mail"],
                cacheFolders: [],
                libraryFolders: ["Containers/com.apple.mail/Data/Library/Mail Downloads"],
                explanation: "Copies of attachments you opened from Mail. The originals stay in your mailboxes; Mail makes a new copy when you open one again."),
    ]

    /// Top-level ~/Library/Caches entries this module reports, so System Junk skips them.
    static let claimedCacheNames: Set<String> = ["Google", "Microsoft Edge", "BraveSoftware", "Arc", "Firefox", "com.apple.Safari"]

    func scan(progress: @escaping @Sendable (String) -> Void) -> [JunkItem] {
        let throttle = ProgressThrottle(progress, counting: true)
        let running = Set(context.runningApps().map { $0.bundleID.lowercased() })
        var targets: [(URL, Browser)] = []

        for browser in Self.browsers {
            for folder in browser.cacheFolders {
                targets.append((context.library("Caches/\(folder)"), browser))
            }
            for folder in browser.libraryFolders {
                targets.append((context.library(folder), browser))
            }
            if let userData = browser.chromiumUserData {
                let root = context.library("Application Support/\(userData)")
                for name in Self.chromiumSharedCacheNames { targets.append((root.appendingPathComponent(name), browser)) }
                for profile in chromiumProfiles(in: root) {
                    for name in Self.chromiumCacheNames { targets.append((profile.appendingPathComponent(name), browser)) }
                }
            }
            if let profiles = browser.firefoxProfiles {
                let root = context.library("Caches/\(profiles)")
                for profile in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [] {
                    for name in Self.firefoxCacheNames { targets.append((profile.appendingPathComponent(name), browser)) }
                }
            }
        }

        let items = parallelMap(targets) { [context] target -> JunkItem? in
            let (url, browser) = target
            guard !context.isCancelled, fm.fileExists(atPath: url.path), fm.isDeletableFile(atPath: url.path) else { return nil }
            throttle.report(url.abbreviatedPath)
            let measured = FileSizer.measure(url, fileManager: fm)
            guard measured.allocated > 0 else { return nil }
            let isRunning = browser.bundleIDs.contains { running.contains($0.lowercased()) }
            let profile = Self.profileLabel(for: url, browser: browser)
            return JunkItem(
                url: url,
                size: measured.allocated,
                category: .browserCaches,
                group: browser.name,
                detail: isRunning
                    ? "\(browser.name) is open. Quit it to clean its cache."
                    : profile + browser.explanation,
                isSelected: !isRunning,
                modified: FileSizer.modificationDate(url),
                inUseBy: isRunning ? browser.name : nil,
                reclaimable: measured.reclaimable,
                requiresClosed: browser.bundleIDs
            )
        }.compactMap { $0 }

        if context.isCancelled { return [] }
        return items.sorted { $0.size > $1.size }
    }

    /// "Default", "Profile 1", "Guest Profile"…: folders with a Preferences file.
    private func chromiumProfiles(in root: URL) -> [URL] {
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return entries.filter { fm.fileExists(atPath: $0.appendingPathComponent("Preferences").path) }
    }

    private static func profileLabel(for url: URL, browser: Browser) -> String {
        let parent = url.deletingLastPathComponent().lastPathComponent
        if browser.chromiumUserData != nil, chromiumCacheNames.contains(url.lastPathComponent) { return "\(parent) profile · " }
        if browser.firefoxProfiles != nil, firefoxCacheNames.contains(url.lastPathComponent) {
            return "\(parent.split(separator: ".").last.map(String.init) ?? parent) profile · "
        }
        return ""
    }
}

import Foundation

/// Last line of defence: decides whether a path is ever allowed to be trashed,
/// no matter what a scanner returned.
enum SafetyGuard {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    /// Exact directories that must never be removed themselves (their *contents* may be).
    private static let protectedRoots: Set<String> = [
        "/", home,
        "\(home)/Library", "\(home)/Library/Caches", "\(home)/Library/Logs",
        "\(home)/Library/Application Support", "\(home)/Library/Preferences",
        "\(home)/Library/Containers", "\(home)/Library/Group Containers",
        "\(home)/Pictures", "\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads",
        "\(home)/Library/Mobile Documents",
    ]

    static func isAllowed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if protectedRoots.contains(path) { return false }
        if path.contains(".photoslibrary") { return false }
        if path.hasPrefix("\(home)/Library/Mobile Documents") { return false } // iCloud Drive
        if path.hasPrefix("\(home)/Library/Keychains") { return false }

        let tempRoot = (NSTemporaryDirectory() as NSString).deletingLastPathComponent
        return path.hasPrefix(home + "/") || path.hasPrefix(tempRoot + "/") || path.hasPrefix("/private" + tempRoot + "/")
    }
}

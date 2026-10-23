import AppKit

/// Detects and helps the user grant Full Disk Access.
///
/// There is no public API to query FDA, so we probe files that TCC only lets
/// FDA-enabled processes open. Opening (not just stat-ing) is the reliable signal.
enum FullDiskAccess {
    private static var probePaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari/Bookmarks.plist",
            "\(home)/Library/Safari/CloudTabs.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
    }

    static var isGranted: Bool {
        for path in probePaths where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 {
                close(fd)
                return true
            }
            if errno == EPERM || errno == EACCES {
                return false
            }
        }
        return false
    }

    /// Opens System Settings › Privacy & Security › Full Disk Access.
    static func openSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Shows the app bundle in Finder so it can be dragged into the FDA list.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

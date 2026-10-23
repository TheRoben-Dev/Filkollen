import Darwin
import Foundation

/// Last line of defence: decides whether a path is ever allowed to be trashed,
/// no matter what a scanner returned.
///
/// Paths are compared after full symlink resolution (`realpath`), with the Data
/// volume firmlink stripped, in Unicode NFC and case-folded, because APFS is
/// normally case-insensitive and normalization-insensitive. Anything that can't
/// be canonicalized is refused. See docs/SAFETY.md for the reasoning behind
/// every rule; changes here need a matching test in SafetyGuardTests.
struct SafetyGuard: Sendable {
    enum Decision: Equatable, Sendable {
        /// Allowed; carries the canonical path the decision was made on.
        case allowed(String)
        case refused(String)

        var isAllowed: Bool { if case .allowed = self { return true } else { return false } }
    }

    /// Canonical, case-folded home and temp folders.
    private let home: String
    private let temp: String

    static let shared = SafetyGuard(
        home: FileManager.default.homeDirectoryForCurrentUser,
        temp: URL(fileURLWithPath: NSTemporaryDirectory())
    )

    /// `temp` is the per-user `…/T/` folder, not its parent: the sibling `C/`
    /// and `0/` folders belong to system daemons.
    init(home: URL, temp: URL) {
        self.home = Self.fold(Self.canonicalPath(home.path) ?? home.path)
        self.temp = Self.fold(Self.canonicalPath(temp.path) ?? temp.path)
    }

    static func isAllowed(_ url: URL) -> Bool { shared.isAllowed(url) }
    func isAllowed(_ url: URL) -> Bool { evaluate(url).isAllowed }

    /// Folders directly under `~/Library` that hold irreplaceable or system data.
    /// Nothing inside them is ever trashed.
    private static let protectedLibraryFolders: [String] = [
        "keychains", "mobile documents", "cloudstorage", "mail", "messages", "safari",
        "photos", "accounts", "calendars", "identityservices", "sharing", "suggestions",
        "biome", "daemon containers", "autosave information", "personalizationportrait",
        "application support/filkollen", "application support/mobilesync",
        "application support/addressbook", "application support/callhistorydb",
        "application support/knowledge",
    ]

    /// Narrow exceptions inside otherwise protected folders: exactly one level
    /// below `parent` is allowed (whole items only, never their insides).
    /// Each one is listed in docs/SAFETY.md and tested.
    private static let exactChildExceptions: [String] = [
        // Whole iPhone/iPad backups (one folder per device), for the iOS Backups module.
        "library/application support/mobilesync/backup",
    ]

    /// Folders directly under home that hold credentials.
    private static let protectedHomeFolders: [String] = [".trash", ".ssh", ".gnupg"]

    /// Exact folders that must never be removed themselves (their contents may be).
    private static let protectedRootsInHome: [String] = [
        "", "library", "library/caches", "library/logs", "library/application support",
        "library/preferences", "library/containers", "library/group containers",
        "library/saved application state", "library/httpstorages", "library/webkit",
        "library/cookies", "library/launchagents", "library/developer",
        "library/developer/xcode", "library/developer/xcode/deriveddata",
        "pictures", "desktop", "documents", "downloads", "movies", "music", "public", "applications",
    ]

    func evaluate(_ url: URL) -> Decision {
        guard url.isFileURL else { return .refused("Not a file") }
        // Check both where the item lives and, if it's a symlink, what it points
        // to. Removing a link is harmless, but failing closed keeps the rules simple.
        guard let target = Self.canonicalPath(url.path),
              let location = Self.canonicalLocation(url.path) else {
            return .refused("Path can't be resolved")
        }
        for path in Set([target, location]) {
            if let reason = refusal(for: Self.fold(path)) { return .refused(reason) }
        }
        return .allowed(location)
    }

    private func refusal(for p: String) -> String? {
        let inHome = p.hasPrefix(home + "/")
        let inTemp = p.hasPrefix(temp + "/")
        guard inHome || inTemp else { return p == home ? "Your home folder" : "Outside your home folder" }

        let components = p.split(separator: "/")
        for (index, c) in components.enumerated() {
            if c.hasSuffix(".photoslibrary") || c.hasSuffix(".photolibrary") { return "Inside a Photos library" }
            if c.hasPrefix("com.apple.") || c.hasPrefix("group.com.apple.") || c.contains(".com.apple.") {
                return "Belongs to macOS (com.apple.*)"
            }
            // An app bundle may be removed whole, but never picked apart.
            if c.hasSuffix(".app"), index < components.count - 1 { return "Inside an app bundle" }
        }

        guard inHome else { return nil }
        let relative = String(p.dropFirst(home.count + 1))
        if Self.protectedRootsInHome.contains(relative) { return "Protected folder" }
        let parts = relative.split(separator: "/")
        // Direct children of ~/Library are system-defined folders.
        if parts.count == 2, parts[0] == "library" { return "Protected folder" }
        for parent in Self.exactChildExceptions where relative.hasPrefix(parent + "/") {
            let rest = relative.dropFirst(parent.count + 1)
            return rest.contains("/") ? "Inside a protected item" : nil
        }
        for folder in Self.protectedHomeFolders where relative == folder || relative.hasPrefix(folder + "/") {
            return "Protected folder"
        }
        for folder in Self.protectedLibraryFolders {
            let full = "library/" + folder
            if relative == full || relative.hasPrefix(full + "/") { return "Protected data (\(folder))" }
        }
        return nil
    }

    // MARK: Canonicalization

    /// NFC + case-folded, for comparison only.
    static func fold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The fully resolved path, following every symlink including the last
    /// component. Resolves the longest existing prefix with `realpath` and
    /// appends the rest; a missing tail containing `.` or `..` is refused
    /// because its meaning depends on symlinks that don't exist yet.
    static func canonicalPath(_ raw: String) -> String? {
        guard raw.hasPrefix("/") else { return nil }
        if let resolved = realPath(raw) { return stripFirmlink(resolved) }

        let trimmed = raw.hasSuffix("/") && raw.count > 1 ? String(raw.dropLast()) : raw
        let name = (trimmed as NSString).lastPathComponent
        let parent = (trimmed as NSString).deletingLastPathComponent
        guard !name.isEmpty, name != ".", name != "..", parent != trimmed,
              let base = canonicalPath(parent) else { return nil }
        return base == "/" ? "/" + name : base + "/" + name
    }

    /// Where the item itself lives: the parent resolved, the last component kept
    /// as is, so a symlink's own location is checked rather than its target.
    static func canonicalLocation(_ raw: String) -> String? {
        guard raw.hasPrefix("/") else { return nil }
        let trimmed = raw.hasSuffix("/") && raw.count > 1 ? String(raw.dropLast()) : raw
        if trimmed == "/" { return "/" }
        let name = (trimmed as NSString).lastPathComponent
        guard name != ".", name != ".." else { return canonicalPath(trimmed) }
        guard let base = canonicalPath((trimmed as NSString).deletingLastPathComponent) else { return nil }
        return base == "/" ? "/" + name : base + "/" + name
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// `/System/Volumes/Data/Users/x` is the same folder as `/Users/x` (a firmlink, not a symlink).
    private static func stripFirmlink(_ path: String) -> String {
        let prefix = "/System/Volumes/Data"
        guard path.lowercased().hasPrefix(prefix.lowercased() + "/") else { return path }
        return String(path.dropFirst(prefix.count))
    }
}

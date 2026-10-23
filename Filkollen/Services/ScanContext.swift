import AppKit

/// Everything a scanner needs from the outside world. `.live` reads the real
/// home folder, preferences and running apps; tests build one around a fixture.
struct ScanContext: @unchecked Sendable {
    struct RunningApp: Sendable, Hashable {
        let bundleID: String
        let name: String
        let executable: String?
    }

    var home: URL
    var temp: URL
    var fileManager: FileManager = .default
    var now: @Sendable () -> Date = { Date() }
    /// Apps running right now; their caches are left unselected.
    var runningApps: @Sendable () -> [RunningApp] = { [] }
    /// Folders searched for installed `.app` bundles.
    var appRoots: [URL] = []
    /// Last-resort "is this bundle ID installed anywhere?" check (LaunchServices).
    var isRegisteredApp: @Sendable (String) -> Bool = { _ in false }

    /// Temp files younger than this are probably in use.
    var tempMinAge: TimeInterval = 3 * 24 * 3600
    /// Large & Old Files threshold.
    var largeFileMinBytes: Int64 = 500 * 1_048_576
    /// Where scanners may keep caches between runs; nil keeps them in memory.
    var cacheDirectory: URL? = nil

    static var live: ScanContext {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ScanContext(
            home: home,
            temp: URL(fileURLWithPath: NSTemporaryDirectory()),
            runningApps: { RunningApps.current() },
            appRoots: [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                URL(fileURLWithPath: "/Library/Application Support"), // helper apps live here sometimes
                home.appendingPathComponent("Applications"),
            ],
            isRegisteredApp: { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil },
            tempMinAge: TimeInterval(max(1, Pref.defaults.integer(forKey: Pref.tempMinAgeDays))) * 24 * 3600,
            largeFileMinBytes: Int64(max(50, Pref.defaults.integer(forKey: Pref.largeFileMB))) * 1_048_576,
            cacheDirectory: ThreatDatabase.supportDirectory
        )
    }

    func library(_ relative: String) -> URL {
        home.appendingPathComponent("Library").appendingPathComponent(relative)
    }
}

enum RunningApps {
    static func current() -> [ScanContext.RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard let id = app.bundleIdentifier else { return nil }
            return .init(bundleID: id, name: app.localizedName ?? "", executable: app.executableURL?.lastPathComponent)
        }
    }

    /// The running app that most likely owns a cache folder named `name`, if any.
    /// Matches bundle IDs (`com.vendor.app`, `com.vendor.app.helper`), app or
    /// executable names (`Firefox`), and vendor folders (`Google` for `com.google.Chrome`).
    static func owner(of name: String, in apps: [ScanContext.RunningApp]) -> ScanContext.RunningApp? {
        let n = name.lowercased()
        return apps.first { app in
            let id = app.bundleID.lowercased()
            if n == id || n.hasPrefix(id + ".") { return true }
            if !app.name.isEmpty, n == app.name.lowercased() { return true }
            if let exe = app.executable?.lowercased(), n == exe { return true }
            let parts = id.split(separator: ".")
            if parts.count >= 3, !id.hasPrefix("com.apple."), n == parts[1] { return true }
            return false
        }
    }
}

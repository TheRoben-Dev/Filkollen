import Foundation

/// UserDefaults keys shared by @AppStorage views and background code.
enum Pref {
    // General
    static let showMenuBarIcon = "showMenuBarIcon"
    static let keepRunningInMenuBar = "keepRunningInMenuBar"
    static let alwaysStartHidden = "alwaysStartHidden"
    static let notificationsEnabled = "notificationsEnabled"

    // Background work
    static let autoScanHours = "autoScanHours"            // 0 = off
    static let autoUpdateThreatDB = "autoUpdateThreatDB"
    static let autoCheckUpdates = "autoCheckUpdates"
    static let lastAutoScan = "lastAutoScan"
    static let lastUpdateCheck = "lastUpdateCheck"

    // Cleanup
    static let tempMinAgeDays = "tempMinAgeDays"
    static let largeFileMB = "largeFileMB"
    static let excludedPaths = "excludedPaths"            // one path per line

    // Updates
    static let checkSparkle = "checkSparkle"
    static let checkHomebrew = "checkHomebrew"
    static let checkAppStore = "checkAppStore"
    static let checkMacOS = "checkMacOS"
    static let brewUpdateFirst = "brewUpdateFirst"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            showMenuBarIcon: true,
            keepRunningInMenuBar: true,
            alwaysStartHidden: false,
            notificationsEnabled: true,
            autoScanHours: 24,
            autoUpdateThreatDB: true,
            autoCheckUpdates: true,
            tempMinAgeDays: 3,
            largeFileMB: 500,
            excludedPaths: "",
            checkSparkle: true,
            checkHomebrew: true,
            checkAppStore: true,
            checkMacOS: true,
            brewUpdateFirst: true,
        ])
    }

    static var defaults: UserDefaults { .standard }
}

/// User-chosen folders that scanners must never report or clean.
enum Exclusions {
    static var paths: [String] {
        (Pref.defaults.string(forKey: Pref.excludedPaths) ?? "")
            .split(whereSeparator: \.isNewline)
            .map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
    }

    static func isExcluded(_ url: URL, in list: [String] = paths) -> Bool {
        let path = url.standardizedFileURL.path
        return list.contains { path == $0 || path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}

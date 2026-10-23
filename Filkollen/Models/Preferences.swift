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
    static let oldFileMonths = "oldFileMonths"            // 0 = size only
    static let leftoverPlainNames = "leftoverPlainNames"
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
            oldFileMonths: 12,
            leftoverPlainNames: false,
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

    /// Appends a path (shown with ~) unless it's already covered.
    static func add(_ url: URL) {
        guard !isExcluded(url) else { return }
        let current = Pref.defaults.string(forKey: Pref.excludedPaths) ?? ""
        let line = url.standardizedFileURL.abbreviatedPath
        Pref.defaults.set(current.isEmpty ? line : current + "\n" + line, forKey: Pref.excludedPaths)
    }

    static func isExcluded(_ url: URL, in list: [String] = paths) -> Bool {
        // Case-insensitive like APFS, and NFC so decomposed names match too.
        let path = SafetyGuard.fold(url.standardizedFileURL.path)
        return list.contains {
            let entry = SafetyGuard.fold($0)
            return path == entry || path.hasPrefix(entry.hasSuffix("/") ? entry : entry + "/")
        }
    }
}

import AppIntents

/// Shortcuts and Spotlight actions. They start scans and open Filkollen to the
/// results; nothing is ever cleaned or quarantined without the review in the app.
struct SmartScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Smart Scan"
    static let description = IntentDescription("Scans for system junk, app leftovers, duplicate photos and browser caches, then shows the results in Filkollen. Nothing is cleaned until you review it.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared else { return .result() }
        app.showMainWindow()
        app.model.section = .smartScan
        if !app.model.isScanning { app.model.startSmartScan() }
        return .result()
    }
}

struct MalwareScanIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan for Malware"
    static let description = IntentDescription("Checks downloads, apps and launch items against the local threat database. Findings wait for you in Filkollen.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared else { return .result() }
        app.showMainWindow()
        app.model.section = .protection
        app.protection.scan()
        return .result()
    }
}

struct FilkollenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SmartScanIntent(), phrases: ["Run a Smart Scan in \(.applicationName)", "Look for junk with \(.applicationName)"])
        AppShortcut(intent: MalwareScanIntent(), phrases: ["Scan for malware with \(.applicationName)"])
    }
}

import AppKit
import OSLog
import UniformTypeIdentifiers

/// Builds a plain-text report for bug reports: app and system versions, a few
/// non-sensitive settings, and Filkollen's own recent log entries. Paths are
/// logged `.private` (redacted) and the home folder and user name are scrubbed
/// from whatever remains.
enum Diagnostics {
    static func report(since interval: TimeInterval = 3600) -> String {
        var lines: [String] = []
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        lines.append("Filkollen \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))")
        lines.append("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion), \(machine)")
        lines.append("Full Disk Access: \(FullDiskAccess.isGranted ? "granted" : "not granted")")
        let db = ThreatDatabase.shared
        lines.append("Threat database: \(db.count) hashes, updated \(db.lastUpdated.map { $0.formatted() } ?? "never")")
        lines.append("ClamAV: \(ClamAV.isInstalled ? "installed" : "not installed")")
        lines.append("Excluded folders: \(Exclusions.paths.count)")
        lines.append("")
        lines.append("Log (last \(Int(interval / 60)) min):")
        lines += recentLog(since: interval)
        return scrub(lines.joined(separator: "\n"))
    }

    static func recentLog(since interval: TimeInterval) -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let start = store.position(date: Date().addingTimeInterval(-interval))
            let predicate = NSPredicate(format: "subsystem == %@", Log.subsystem)
            return try store.getEntries(at: start, matching: predicate)
                .compactMap { $0 as? OSLogEntryLog }
                .map { "\($0.date.formatted(date: .omitted, time: .standard)) [\($0.category)] \(level($0.level)) \($0.composedMessage)" }
        } catch {
            return ["(log unavailable: \(error.localizedDescription))"]
        }
    }

    /// Replaces the home path and user name, in case a message carried one.
    static func scrub(_ text: String, home: String = NSHomeDirectory(), user: String = NSUserName()) -> String {
        var out = text.replacingOccurrences(of: home, with: "~")
        if user.count >= 3 { out = out.replacingOccurrences(of: user, with: "<user>") }
        return out
    }

    private static func level(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .error, .fault: return "ERROR"
        case .notice: return "NOTE"
        default: return "info"
        }
    }

    private static var machine: String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.machine", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    /// Asks where to save the report and writes it there.
    @MainActor
    static func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Filkollen Diagnostics \(Date().formatted(.iso8601.year().month().day())).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = report()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            Log.app.error("Diagnostics export failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

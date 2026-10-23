import OSLog

/// One logger per module. User paths are logged `.private`, so they're redacted
/// in exported diagnostics unless a debugger is attached.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "dev.theroben.Filkollen"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let scan = Logger(subsystem: subsystem, category: "scan")
    static let cleaner = Logger(subsystem: subsystem, category: "cleaner")
    static let safety = Logger(subsystem: subsystem, category: "safety")
    static let protection = Logger(subsystem: subsystem, category: "protection")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}

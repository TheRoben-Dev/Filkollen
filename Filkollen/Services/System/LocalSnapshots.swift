import AppKit

/// Time Machine local snapshots on the startup disk. Informational only:
/// macOS removes them by itself when space runs low, and deleting them from
/// here would need admin rights.
enum LocalSnapshots {
    struct Snapshot: Identifiable, Hashable, Sendable {
        var id: String { name }
        let name: String
        let date: Date?
    }

    static func list() async -> [Snapshot] {
        guard let tmutil = Shell.find("tmutil") else { return [] }
        let output = await Shell.run(tmutil, ["listlocalsnapshots", "/"])
        return parse(output.text)
    }

    /// Lines look like `com.apple.TimeMachine.2026-10-23-101500.local`.
    static func parse(_ text: String) -> [Snapshot] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("com.apple.TimeMachine.") else { return nil }
            let stamp = line.dropFirst("com.apple.TimeMachine.".count).replacingOccurrences(of: ".local", with: "")
            return Snapshot(name: line, date: formatter.date(from: stamp))
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    static func openTimeMachineSettings() {
        let urls = ["x-apple.systempreferences:com.apple.Time-Machine-Settings.extension",
                    "x-apple.systempreferences:com.apple.prefs.backup"]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}

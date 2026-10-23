import SwiftUI
import UniformTypeIdentifiers

/// State for the Protection (malware) section. Separate from junk cleaning
/// because findings are quarantined or deleted, never just trashed.
@MainActor
final class ProtectionModel: ObservableObject {
    enum Phase: Equatable {
        case idle, updating, scanning, finished
    }

    @Published var phase: Phase = .idle
    @Published var status = ""
    @Published var threats: [Threat] = []
    @Published var filesChecked = 0
    @Published var quarantined: [Quarantine.Entry] = Quarantine.entries()
    @Published var databaseCount = ThreatDatabase.shared.count
    @Published var databaseUpdated = ThreatDatabase.shared.lastUpdated
    @Published var errorMessage: String?
    @AppStorage("useClamAV") var useClamAV = true

    var clamAVInstalled: Bool { ClamAV.isInstalled }
    @Published var clamSignaturesDate = ClamAV.signaturesDate()
    var isBusy: Bool { phase == .updating || phase == .scanning }

    /// Database older than a week is considered stale.
    var databaseIsStale: Bool { Self.isStale(databaseUpdated) }
    var clamSignaturesAreStale: Bool { Self.isStale(clamSignaturesDate) }

    nonisolated static func isStale(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return true }
        return date < now.addingTimeInterval(-7 * 24 * 3600)
    }

    func updateDatabase() {
        guard !isBusy else { return }
        phase = .updating
        errorMessage = nil
        Task {
            do {
                let count = try await ThreatDatabase.shared.update { msg in
                    Task { @MainActor in self.status = msg }
                }
                ThreatDatabase.shared.unload()
                databaseCount = count
                databaseUpdated = ThreatDatabase.shared.lastUpdated
            } catch {
                errorMessage = "Couldn't update the threat database: \(error.localizedDescription)"
            }
            status = ""
            phase = threats.isEmpty ? .idle : .finished
        }
    }

    func scan() {
        guard !isBusy else { return }
        clamSignaturesDate = ClamAV.signaturesDate()
        phase = .scanning
        threats = []
        errorMessage = nil
        let clam = useClamAV
        let progress: @Sendable (String) -> Void = { [weak self] msg in
            Task { @MainActor in self?.status = msg }
        }
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                MalwareScanner().scan(useClamAV: clam, progress: progress)
            }.value
            threats = result.threats
            filesChecked = result.filesChecked
            if let e = result.clamError { errorMessage = "ClamAV: \(e)" }
            if let e = result.databaseError { errorMessage = [errorMessage, e].compactMap { $0 }.joined(separator: "\n") }
            status = ""
            phase = .finished
        }
    }

    // MARK: Actions

    func quarantine(_ threats: [Threat]) {
        perform(threats) { try Quarantine.isolate($0) }
    }

    func deletePermanently(_ threats: [Threat]) {
        perform(threats) { try Quarantine.deletePermanently($0) }
    }

    private func perform(_ list: [Threat], _ action: (Threat) throws -> Void) {
        var failed: [String] = []
        for threat in list {
            do {
                try action(threat)
                threats.removeAll { $0.id == threat.id }
            } catch {
                failed.append("\(threat.name): \(error.localizedDescription)")
            }
        }
        quarantined = Quarantine.entries()
        if !failed.isEmpty { errorMessage = failed.joined(separator: "\n") }
    }

    func restore(_ entry: Quarantine.Entry) {
        run { try Quarantine.restore(entry) }
    }

    func deleteQuarantined(_ entries: [Quarantine.Entry]) {
        run { for e in entries { try Quarantine.delete(e) } }
    }

    /// Quarantined more than `days` ago.
    func quarantined(olderThanDays days: Int) -> [Quarantine.Entry] {
        Quarantine.entries(olderThan: Date().addingTimeInterval(-Double(days) * 86_400))
    }

    func exportQuarantineReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Filkollen Quarantine \(Date().formatted(.iso8601.year().month().day())).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try Quarantine.exportReport(to: url) }
    }

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
        quarantined = Quarantine.entries()
    }
}

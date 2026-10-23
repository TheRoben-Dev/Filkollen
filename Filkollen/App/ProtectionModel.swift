import SwiftUI

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
    var isBusy: Bool { phase == .updating || phase == .scanning }

    /// Database older than a week is considered stale.
    var databaseIsStale: Bool {
        guard let date = databaseUpdated else { return true }
        return date < Date().addingTimeInterval(-7 * 24 * 3600)
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

    private func run(_ body: () throws -> Void) {
        do { try body() } catch { errorMessage = error.localizedDescription }
        quarantined = Quarantine.entries()
    }
}

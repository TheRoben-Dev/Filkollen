import AppKit
import SwiftUI

private struct SourceResult: Sendable {
    let source: AppUpdate.Source
    let updates: [AppUpdate]
    var error: String? = nil
}

@MainActor
final class UpdatesModel: ObservableObject {
    @Published private(set) var updates: [AppUpdate] = []
    @Published private(set) var isChecking = false
    @Published private(set) var checkingSources: Set<AppUpdate.Source> = []
    @Published private(set) var lastChecked: Date? = Pref.defaults.object(forKey: Pref.lastUpdateCheck) as? Date
    @Published private(set) var working: Set<String> = []
    @Published var message: String?

    var brewInstalled: Bool { HomebrewChecker.brew != nil }
    var masInstalled: Bool { AppStoreChecker.mas != nil }

    func updates(for source: AppUpdate.Source) -> [AppUpdate] { updates.filter { $0.source == source } }

    func check(onFinish: (([AppUpdate]) -> Void)? = nil) {
        guard !isChecking else { return }
        isChecking = true
        message = nil
        let d = Pref.defaults
        var sources: [AppUpdate.Source] = []
        if d.bool(forKey: Pref.checkSparkle) { sources.append(.apps) }
        if d.bool(forKey: Pref.checkHomebrew) { sources.append(.homebrew) }
        if d.bool(forKey: Pref.checkAppStore) { sources.append(.appStore) }
        if d.bool(forKey: Pref.checkMacOS) { sources.append(.macOS) }
        checkingSources = Set(sources)
        updates = []
        let refreshBrew = d.bool(forKey: Pref.brewUpdateFirst)

        Task {
            await withTaskGroup(of: SourceResult.self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            switch source {
                            case .apps: return SourceResult(source: source, updates: await SparkleChecker.check())
                            case .homebrew:
                                return SourceResult(source: source, updates: try await HomebrewChecker.check(refreshIndex: refreshBrew))
                            case .appStore: return SourceResult(source: source, updates: await AppStoreChecker.check())
                            case .macOS: return SourceResult(source: source, updates: await MacOSUpdateChecker.check())
                            }
                        } catch {
                            return SourceResult(source: source, updates: [], error: error.localizedDescription)
                        }
                    }
                }
                // Show each source's results as soon as it finishes.
                for await result in group {
                    checkingSources.remove(result.source)
                    updates += result.updates
                    if let error = result.error { message = "\(result.source.rawValue): \(error)" }
                }
            }
            // An app installed as a Homebrew cask shows up twice; keep the brew entry, which can upgrade it.
            let casks = Set(updates.filter(\.isCask).compactMap(\.token))
            updates.removeAll {
                $0.source == .apps && casks.contains($0.name.lowercased().replacingOccurrences(of: " ", with: "-"))
            }
            isChecking = false
            let now = Date()
            lastChecked = now
            Pref.defaults.set(now, forKey: Pref.lastUpdateCheck)
            onFinish?(updates)
        }
    }

    // MARK: Actions

    func perform(_ update: AppUpdate) {
        switch update.source {
        case .apps:
            // Sparkle apps update themselves; opening them lets them offer the update.
            if let url = update.appURL { NSWorkspace.shared.open(url) }
        case .homebrew:
            upgradeHomebrew([update])
        case .appStore:
            NSWorkspace.shared.open(AppStoreChecker.updatesPage)
        case .macOS:
            NSWorkspace.shared.open(MacOSUpdateChecker.settingsURL)
        }
    }

    func upgradeHomebrew(_ list: [AppUpdate]) {
        let ids = Set(list.map(\.id))
        working.formUnion(ids)
        Task {
            let result = await HomebrewChecker.upgrade(list)
            working.subtract(ids)
            if result.ok {
                updates.removeAll { ids.contains($0.id) }
                message = "Upgraded \(list.count) Homebrew package\(list.count == 1 ? "" : "s")."
            } else {
                let tail = result.text.split(separator: "\n").suffix(3).joined(separator: " ")
                message = "Homebrew upgrade failed: \(tail)"
            }
        }
    }
}

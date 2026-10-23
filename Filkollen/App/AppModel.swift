import AppKit
import SwiftUI

/// Central app state. Owns scan results and drives the scan / review / clean flow.
@MainActor
final class AppModel: ObservableObject {
    enum Section: Hashable {
        case smartScan
        case category(JunkCategory)
        case protection
        case updates
        case system(SystemPage)
    }

    enum SystemPage: String, Hashable, CaseIterable {
        case overview = "System Overview"
        case startupItems = "Startup Items"

        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.50percent"
            case .startupItems: return "power.circle.fill"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case done(CleanupSummary)
    }

    @Published var section: Section = .smartScan
    @Published var phase: Phase = .idle
    @Published private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
    @Published var onboardingDismissed = UserDefaults.standard.bool(forKey: "onboardingDismissed")

    @Published private(set) var results: [JunkCategory: CategoryResult] = [:]
    @Published private(set) var scanningCategory: JunkCategory?
    @Published private(set) var scanStatus = ""

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool { phase == .scanning }
    var showOnboarding: Bool { !hasFullDiskAccess && !onboardingDismissed && !fullDiskAccessRevoked }

    init() {
        refreshFullDiskAccess()
    }

    // MARK: Full Disk Access

    /// Access was granted at some point and has since been turned off in System Settings.
    @Published private(set) var fullDiskAccessRevoked = false

    func refreshFullDiskAccess() {
        let granted = FullDiskAccess.isGranted
        let hadAccess = UserDefaults.standard.bool(forKey: "hadFullDiskAccess")
        if granted != hasFullDiskAccess || (hadAccess && !granted) != fullDiskAccessRevoked {
            Log.app.notice("Full Disk Access \(granted ? "granted" : (hadAccess ? "revoked" : "not granted"), privacy: .public)")
        }
        hasFullDiskAccess = granted
        fullDiskAccessRevoked = hadAccess && !granted
        if granted { UserDefaults.standard.set(true, forKey: "hadFullDiskAccess") }
    }

    func skipOnboarding() {
        onboardingDismissed = true
        UserDefaults.standard.set(true, forKey: "onboardingDismissed")
    }

    // MARK: Scanning

    @Published private(set) var lastSmartScan: Date? = Pref.defaults.object(forKey: Pref.lastAutoScan) as? Date

    var smartScanTotal: Int64 { JunkCategory.smartScan.reduce(0) { $0 + (results[$1]?.totalSize ?? 0) } }
    var smartScanSelected: Int64 { JunkCategory.smartScan.reduce(0) { $0 + (results[$1]?.selectedSize ?? 0) } }

    func startSmartScan(onFinish: (() -> Void)? = nil) {
        scan(JunkCategory.smartScan) { [weak self] in
            let now = Date()
            self?.lastSmartScan = now
            Pref.defaults.set(now, forKey: Pref.lastAutoScan)
            onFinish?()
        }
    }

    /// Identifies the current scan, so a cancelled one that's still winding down
    /// can never write its results over a newer scan's.
    private var scanGeneration = 0

    /// Whether a background (scheduled) scan may start now without disturbing the user:
    /// not while they're looking at results or cleaning.
    var canStartBackgroundScan: Bool {
        switch phase {
        case .idle, .done: return true
        case .scanning, .results, .cleaning: return false
        }
    }

    func scan(_ categories: [JunkCategory], onFinish: (() -> Void)? = nil) {
        guard !isScanning else { return }
        refreshFullDiskAccess()
        phase = .scanning
        for c in categories { results[c] = nil }
        scanGeneration += 1
        let generation = scanGeneration
        let started = Date()

        scanTask = Task {
            for category in categories {
                if Task.isCancelled { break }
                scanningCategory = category
                scanStatus = category.scanningMessage
                let items = await Self.runScanner(for: category) { path in
                    Task { @MainActor in
                        guard self.scanGeneration == generation else { return }
                        self.scanStatus = path
                    }
                }
                guard !Task.isCancelled, scanGeneration == generation else { break }
                let excluded = Exclusions.paths
                results[category] = CategoryResult(
                    category: category,
                    items: excluded.isEmpty ? items : items.filter { !Exclusions.isExcluded($0.url, in: excluded) }
                )
            }
            guard scanGeneration == generation else { return }
            scanningCategory = nil
            scanStatus = ""
            if Task.isCancelled {
                phase = .idle
                Log.scan.info("Scan cancelled after \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
            } else {
                phase = .results
                Log.scan.info("Scan finished in \(Date().timeIntervalSince(started), format: .fixed(precision: 1)) s")
                onFinish?()
            }
        }
    }

    /// Stops the scan for real: the scanner sees the cancellation and returns early.
    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanGeneration += 1
        scanningCategory = nil
        scanStatus = ""
        phase = .idle
    }

    nonisolated private static func runScanner(
        for category: JunkCategory,
        progress: @escaping @Sendable (String) -> Void
    ) async -> [JunkItem] {
        // Detached so the work runs off the main actor; cancellation is forwarded
        // by hand because detached tasks don't inherit it.
        let work = Task.detached(priority: .userInitiated) { () -> [JunkItem] in
            let context = ScanContext.live
            let found: [JunkItem]
            switch category {
            case .systemJunk: found = CacheScanner(context: context).scan(progress: progress)
            case .appLeftovers: found = LeftoverScanner(context: context).scan(progress: progress)
            case .duplicatePhotos: found = DuplicatePhotoScanner(context: context).scan(progress: progress)
            case .largeFiles: found = LargeFileScanner(context: context).scan(progress: progress)
            }
            if Task.isCancelled { return [] }
            return screened(found, category: category)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    /// Drops anything SafetyGuard would refuse, so it's never shown as cleanable,
    /// and records each item's resolved location for the delete-time re-check.
    nonisolated static func screened(_ items: [JunkItem], category: JunkCategory, safety: SafetyGuard = .shared) -> [JunkItem] {
        var refused = 0
        let kept = items.compactMap { item -> JunkItem? in
            guard case .allowed(let path) = safety.evaluate(item.url) else { refused += 1; return nil }
            var item = item
            item.resolvedPath = path
            return item
        }
        Log.scan.info("\(category.rawValue, privacy: .public): \(kept.count) items, \(refused) refused by SafetyGuard")
        return kept
    }

    // MARK: Selection

    func result(for category: JunkCategory) -> CategoryResult? { results[category] }

    func setSelected(_ selected: Bool, item: JunkItem.ID, in category: JunkCategory) {
        guard var result = results[category],
              let idx = result.items.firstIndex(where: { $0.id == item }) else { return }
        result.items[idx].isSelected = selected
        results[category] = result
    }

    func setAllSelected(_ selected: Bool, in category: JunkCategory) {
        guard var result = results[category] else { return }
        for i in result.items.indices {
            // Never auto-select the copy we keep in a duplicate group, or something an app is using.
            if result.items[i].isKeeper || (selected && result.items[i].inUseBy != nil) { continue }
            result.items[i].isSelected = selected
        }
        results[category] = result
    }

    var totalFound: Int64 { results.values.reduce(0) { $0 + $1.totalSize } }
    var totalSelected: Int64 { results.values.reduce(0) { $0 + $1.selectedSize } }
    var selectedItems: [JunkItem] { JunkCategory.allCases.flatMap { results[$0]?.selectedItems ?? [] } }

    // MARK: Cleaning

    /// Moves every selected item to the Trash. Nothing is permanently deleted.
    func cleanSelected(in categories: [JunkCategory] = JunkCategory.allCases) {
        let items = categories.flatMap { results[$0]?.selectedItems ?? [] }
        guard !items.isEmpty else { return }
        phase = .cleaning
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                Cleaner.moveToTrash(items)
            }.value
            for category in JunkCategory.allCases {
                guard var r = results[category] else { continue }
                r.items.removeAll { outcome.trashed.contains($0.url) }
                results[category] = r
            }
            phase = .done(CleanupSummary(outcome))
        }
    }

    func reset() {
        results = [:]
        phase = .idle
    }
}

/// What the done screen shows after a cleanup.
struct CleanupSummary: Equatable {
    var trashedCount: Int
    var trashedBytes: Int64
    var failures: [Cleaner.Failure]

    init(_ outcome: Cleaner.Outcome) {
        trashedCount = outcome.trashed.count - outcome.alreadyGone
        trashedBytes = outcome.trashedBytes
        failures = outcome.failures
    }
}

struct CategoryResult {
    let category: JunkCategory
    var items: [JunkItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [JunkItem] { items.filter(\.isSelected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
}

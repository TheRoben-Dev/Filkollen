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
    @Published var hasFullDiskAccess = FullDiskAccess.isGranted
    @Published var onboardingDismissed = UserDefaults.standard.bool(forKey: "onboardingDismissed")

    @Published private(set) var results: [JunkCategory: CategoryResult] = [:]
    @Published private(set) var scanningCategory: JunkCategory?
    @Published private(set) var scanStatus = ""

    private var scanTask: Task<Void, Never>?

    var isScanning: Bool { phase == .scanning }
    var showOnboarding: Bool { !hasFullDiskAccess && !onboardingDismissed }

    // MARK: Full Disk Access

    func refreshFullDiskAccess() {
        hasFullDiskAccess = FullDiskAccess.isGranted
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

    func scan(_ categories: [JunkCategory], onFinish: (() -> Void)? = nil) {
        guard !isScanning else { return }
        refreshFullDiskAccess()
        phase = .scanning
        for c in categories { results[c] = nil }

        scanTask = Task {
            for category in categories {
                if Task.isCancelled { break }
                scanningCategory = category
                scanStatus = category.scanningMessage
                let items = await Self.runScanner(for: category) { path in
                    Task { @MainActor in self.scanStatus = path }
                }
                let excluded = Exclusions.paths
                results[category] = CategoryResult(
                    category: category,
                    items: excluded.isEmpty ? items : items.filter { !Exclusions.isExcluded($0.url, in: excluded) }
                )
            }
            scanningCategory = nil
            scanStatus = ""
            phase = Task.isCancelled ? .idle : .results
            if !Task.isCancelled { onFinish?() }
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        scanningCategory = nil
        phase = .idle
    }

    nonisolated private static func runScanner(
        for category: JunkCategory,
        progress: @escaping @Sendable (String) -> Void
    ) async -> [JunkItem] {
        await Task.detached(priority: .userInitiated) {
            let found: [JunkItem]
            switch category {
            case .systemJunk: found = CacheScanner().scan(progress: progress)
            case .appLeftovers: found = LeftoverScanner().scan(progress: progress)
            case .duplicatePhotos: found = DuplicatePhotoScanner().scan(progress: progress)
            case .largeFiles: found = LargeFileScanner().scan(progress: progress)
            }
            return screened(found, category: category)
        }.value
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
            // Never auto-select the copy we keep in a duplicate group.
            if result.items[i].isKeeper { continue }
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

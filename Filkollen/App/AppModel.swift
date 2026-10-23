import AppKit
import SwiftUI

/// Central app state. Owns scan results and drives the scan / review / clean flow.
@MainActor
final class AppModel: ObservableObject {
    enum Section: Hashable {
        case smartScan
        case category(JunkCategory)
        case protection
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case cleaning
        case done(freed: Int64, failed: Int)
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

    func startSmartScan() {
        scan(JunkCategory.allCases)
    }

    func scan(_ categories: [JunkCategory]) {
        guard !isScanning else { return }
        refreshFullDiskAccess()
        phase = .scanning
        for c in categories { results[c] = nil }

        scanTask = Task {
            for category in categories {
                if Task.isCancelled { break }
                scanningCategory = category
                scanStatus = category.scanningMessage
                let items = await Self.runScanner(for: category) { [weak self] path in
                    Task { @MainActor in self?.scanStatus = path }
                }
                results[category] = CategoryResult(category: category, items: items)
            }
            scanningCategory = nil
            scanStatus = ""
            phase = Task.isCancelled ? .idle : .results
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
            switch category {
            case .systemJunk: return CacheScanner().scan(progress: progress)
            case .appLeftovers: return LeftoverScanner().scan(progress: progress)
            case .duplicatePhotos: return DuplicatePhotoScanner().scan(progress: progress)
            }
        }.value
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
            phase = .done(freed: outcome.freedBytes, failed: outcome.failures.count)
        }
    }

    func reset() {
        results = [:]
        phase = .idle
    }
}

struct CategoryResult {
    let category: JunkCategory
    var items: [JunkItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [JunkItem] { items.filter(\.isSelected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
}

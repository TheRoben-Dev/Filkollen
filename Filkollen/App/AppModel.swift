import AppKit
import SwiftUI

/// Central app state. Owns scan results and drives the scan / review / clean flow.
@MainActor
final class AppModel: ObservableObject {
    enum Section: Hashable {
        case smartScan
        case category(JunkCategory)
        case uninstaller
        case protection
        case updates
        case system(SystemPage)
    }

    enum SystemPage: String, Hashable, CaseIterable {
        case overview = "System Overview"
        case startupItems = "Startup Items"
        case snapshots = "Time Machine Snapshots"

        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.50percent"
            case .startupItems: return "power.circle.fill"
            case .snapshots: return "clock.arrow.circlepath"
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
    /// Categories still being scanned; they run side by side.
    @Published private(set) var scanningCategories: Set<JunkCategory> = []
    /// The category shown as "now scanning": the first unfinished one in display order.
    var scanningCategory: JunkCategory? { JunkCategory.allCases.first { scanningCategories.contains($0) } }
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
    var smartScanReclaimable: Int64 { JunkCategory.smartScan.reduce(0) { $0 + (results[$1]?.selectedReclaimable ?? 0) } }

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
            scanningCategories = Set(categories)
            scanStatus = categories.first?.scanningMessage ?? ""
            // Scanners run concurrently (each one also hashes/measures in parallel);
            // results appear as each finishes.
            await withTaskGroup(of: (JunkCategory, [JunkItem]).self) { group in
                for category in categories {
                    group.addTask {
                        let items = await Self.runScanner(for: category) { message in
                            Task { @MainActor in
                                guard self.scanGeneration == generation, self.scanningCategories.contains(category) else { return }
                                self.scanStatus = message
                            }
                        }
                        return (category, items)
                    }
                }
                for await (category, items) in group {
                    guard !Task.isCancelled, scanGeneration == generation else { continue }
                    let excluded = Exclusions.paths
                    results[category] = CategoryResult(
                        category: category,
                        items: excluded.isEmpty ? items : items.filter { !Exclusions.isExcluded($0.url, in: excluded) }
                    )
                    scanningCategories.remove(category)
                }
            }
            guard scanGeneration == generation else { return }
            scanningCategories = []
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
        scanningCategories = []
        scanStatus = ""
        phase = .idle
    }

    nonisolated private static func runScanner(
        for category: JunkCategory,
        progress: @escaping @Sendable (String) -> Void
    ) async -> [JunkItem] {
        // Detached so the work runs off the main actor; cancellation is forwarded
        // by hand because detached tasks don't inherit it.
        let context = ScanContext.live
        let work = Task.detached(priority: .userInitiated) { () -> [JunkItem] in
            let found: [JunkItem]
            switch category {
            case .systemJunk: found = CacheScanner(context: context).scan(progress: progress)
            case .appLeftovers: found = LeftoverScanner(context: context).scan(progress: progress)
            case .duplicatePhotos: found = DuplicatePhotoScanner(context: context).scan(progress: progress)
            case .duplicateFiles: found = DuplicatePhotoScanner(context: context, mode: .files).scan(progress: progress)
            case .largeFiles: found = LargeFileScanner(context: context).scan(progress: progress)
            case .developerJunk: found = DeveloperScanner(context: context).scan(progress: progress)
            case .oldInstallers: found = InstallerScanner(context: context).scan(progress: progress)
            case .iosBackups: found = IOSBackupScanner(context: context).scan(progress: progress)
            case .browserCaches: found = BrowserScanner(context: context).scan(progress: progress)
            }
            if context.isCancelled { return [] }
            return screened(found, category: category)
        }
        return await withTaskCancellationHandler { await work.value } onCancel: {
            work.cancel()
            context.cancellation.set()
        }
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

    /// Adds a path to Settings › Cleanup › Excluded folders and drops matching
    /// items from the current results.
    func alwaysIgnore(_ url: URL) {
        Exclusions.add(url)
        for category in JunkCategory.allCases {
            guard var r = results[category] else { continue }
            r.items.removeAll { Exclusions.isExcluded($0.url, in: [url.standardizedFileURL.path]) }
            results[category] = r
        }
        Log.scan.info("Added an item to the ignore list")
    }

    func setAllSelected(_ selected: Bool, in category: JunkCategory) {
        guard var result = results[category] else { return }
        for i in result.items.indices {
            // Never auto-select the copy we keep in a duplicate group, or something an app is using.
            let item = result.items[i]
            if item.isKeeper || (selected && (item.inUseBy != nil || item.confidence == .low)) { continue }
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

    /// Moves an app's remnants to the Trash (App Uninstaller). Same Cleaner and
    /// checks as any cleanup; anything trashed also leaves the scan results.
    func uninstall(_ items: [JunkItem]) async -> CleanupSummary {
        let screened = Self.screened(items, category: .appLeftovers)
        let outcome = await Task.detached(priority: .userInitiated) {
            Cleaner.moveToTrash(screened)
        }.value
        for category in JunkCategory.allCases {
            guard var r = results[category] else { continue }
            r.items.removeAll { outcome.trashed.contains($0.url) }
            results[category] = r
        }
        var summary = CleanupSummary(outcome)
        let refused = items.count - screened.count
        if refused > 0 {
            Log.cleaner.notice("Uninstaller: \(refused) items refused by SafetyGuard before cleaning")
        }
        summary.failures += items.filter { item in !screened.contains { $0.url == item.url } }
            .map { Cleaner.Failure(url: $0.url, reason: "Filkollen doesn't remove items in this location.") }
        return summary
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
    var reclaimableBytes: Int64
    var failures: [Cleaner.Failure]

    init(_ outcome: Cleaner.Outcome) {
        trashedCount = outcome.trashed.count - outcome.alreadyGone
        trashedBytes = outcome.trashedBytes
        reclaimableBytes = outcome.reclaimableBytes
        failures = outcome.failures
    }
}

struct CategoryResult {
    let category: JunkCategory
    var items: [JunkItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [JunkItem] { items.filter(\.isSelected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    /// What emptying the Trash would give back for the selection (clones and hard links excluded).
    var selectedReclaimable: Int64 { selectedItems.reduce(0) { $0 + $1.reclaimableSize } }
}

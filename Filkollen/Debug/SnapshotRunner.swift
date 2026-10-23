#if DEBUG
import AppKit
import SwiftUI

/// Debug builds only. Launch with `-FKSnapshotDir <folder>` to walk every screen
/// and state with fixture data and save a PNG of each, in dark and light
/// appearance, then quit. Used for the docs/design/ before/after shots.
///
/// Nothing here cleans, quarantines or deletes: it only sets published state
/// and takes pictures of the windows it owns (no Screen Recording needed).
@MainActor
final class SnapshotRunner {
    nonisolated static var directory: URL? {
        UserDefaults.standard.string(forKey: "FKSnapshotDir").map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
    }

    nonisolated static var isActive: Bool { directory != nil }

    private let app: AppDelegate
    private var index: [String] = []
    private var out: URL

    init(app: AppDelegate, directory: URL) {
        self.app = app
        self.out = directory
    }

    static func runIfRequested(app: AppDelegate) {
        guard let dir = directory else { return }
        Task { await SnapshotRunner(app: app, directory: dir).run() }
    }

    func run() async {
        let root = out
        let fm = FileManager.default
        await sleep(2)
        for (name, appearance) in [("dark", NSAppearance.Name.darkAqua), ("light", .aqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            out = root.appendingPathComponent(name, isDirectory: true)
            try? fm.createDirectory(at: out, withIntermediateDirectories: true)
            await mainWindowStates()
            await hostedViews()
            await settingsTabs()
            await aboutPanel()
        }
        try? index.joined(separator: "\n").write(to: root.appendingPathComponent("index.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }

    // MARK: Main window

    private var mainWindow: NSWindow? {
        NSApp.windows.first {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel) && $0.frame.width >= 900
        }
    }

    private func mainWindowStates() async {
        let m = app.model, p = app.protection
        app.showMainWindow()
        await sleep(1)
        mainWindow?.setContentSize(NSSize(width: 1180, height: 760))
        mainWindow?.center()
        let realFDA = FullDiskAccess.isGranted
        let realQuarantine = p.quarantined

        // Onboarding and the missing-access banner.
        m.reset()
        m.debugApply(fullDiskAccess: false)
        m.onboardingDismissed = false
        await shot("01-onboarding")
        m.onboardingDismissed = true
        await shot("02-sidebar-no-full-disk-access")
        m.debugApply(fullDiskAccess: true)

        // Smart Scan, start to finish.
        m.section = .smartScan
        await shot("03-smartscan-idle")
        m.phase = .scanning
        m.debugApply(scanning: [.appLeftovers, .duplicatePhotos, .browserCaches],
                     status: "~/Library/Application Support/Adobe/CoreSync/plugins/livetype/.r/.12345.otf")
        await shot("04-smartscan-scanning")
        m.debugApply(results: Fixtures.results, scanning: [])
        m.phase = .results
        await shot("05-smartscan-results", settle: 1.5)
        m.phase = .cleaning
        await shot("06-smartscan-cleaning")
        m.phase = .done(Fixtures.summary(failures: false))
        await shot("07-smartscan-done")
        m.phase = .done(Fixtures.summary(failures: true))
        await shot("08-smartscan-done-with-failures")
        m.phase = .results

        // Every category page: with results, not scanned, empty and scanning.
        for category in JunkCategory.allCases {
            m.section = .category(category)
            await shot("10-category-\(category.rawValue)")
        }
        m.debugApply(results: [.largeFiles: CategoryResult(category: .largeFiles, items: [])])
        m.section = .category(.largeFiles)
        await shot("11-category-empty")
        m.phase = .scanning
        m.debugApply(scanning: [.developerJunk], status: "~/Library/Developer/Xcode/DerivedData/Filkollen-abc/Build")
        m.section = .category(.developerJunk)
        await shot("12-category-scanning")
        m.debugApply(results: [.largeFiles: nil], scanning: [], status: "")
        m.phase = .results

        // Protection: every phase and tab.
        m.section = .protection
        await shot("20-protection-idle", settle: 1.5)
        p.phase = .updating
        p.status = "Downloading MalwareBazaar export… 38%"
        await shot("21-protection-updating")
        p.phase = .scanning
        p.status = "~/Downloads/Installer.pkg"
        await shot("22-protection-scanning")
        p.phase = .finished
        p.filesChecked = 48_211
        await shot("23-protection-clean")
        p.threats = Fixtures.threats
        await shot("24-protection-threats")
        p.quarantined = Fixtures.quarantine
        await openProtectionTab(.quarantine)
        await shot("25-protection-quarantine")
        p.quarantined = []
        await openProtectionTab(.quarantine)
        await shot("26-protection-quarantine-empty")
        await openProtectionTab(.trust)
        await shot("27-protection-app-trust", settle: 6)
        ProtectionView.startTab = .scan
        p.threats = []
        p.phase = .idle
        p.status = ""
        p.quarantined = realQuarantine

        // The other pages show live data from this Mac.
        let pages: [(String, AppModel.Section, Double)] = [
            ("30-uninstaller", .uninstaller, 3),
            ("31-history", .history, 2),
            ("32-updates", .updates, 1.5),
            ("33-system-overview", .system(.overview), 2),
            ("34-startup-items", .system(.startupItems), 3),
            ("35-time-machine", .system(.snapshots), 3),
            ("36-disk-usage", .system(.diskUsage), 10),
        ]
        for (name, section, settle) in pages {
            m.section = section
            await shot(name, settle: settle)
        }

        // Minimum window size.
        m.section = .smartScan
        mainWindow?.setContentSize(NSSize(width: 940, height: 620))
        await shot("40-smartscan-results-min-size", settle: 1.5)
        mainWindow?.setContentSize(NSSize(width: 1180, height: 760))

        m.reset()
        m.debugApply(fullDiskAccess: realFDA)
    }

    private func openProtectionTab(_ tab: ProtectionView.Tab) async {
        app.model.section = .history
        await sleep(0.3)
        ProtectionView.startTab = tab
        app.model.section = .protection
    }

    private func shot(_ name: String, settle: Double = 1.1) async {
        await sleep(settle)
        guard let window = mainWindow else { index.append("\(name): no main window"); return }
        save(window, name)
    }

    // MARK: Views that normally live in a sheet or the menu bar

    private func hostedViews() async {
        let m = app.model
        m.debugApply(results: Fixtures.results)
        m.phase = .results
        await host("50-review-sheet", ReviewSheet().environmentObject(m))
        await host("51-menu-bar", MenuBarView()
            .environmentObject(app).environmentObject(m)
            .environmentObject(app.protection).environmentObject(app.updates), settle: 2.5)
        app.protection.threats = Fixtures.threats
        await host("52-menu-bar-threats", MenuBarView()
            .environmentObject(app).environmentObject(m)
            .environmentObject(app.protection).environmentObject(app.updates), settle: 2.5)
        app.protection.threats = []
        m.reset()
    }

    private func host<V: View>(_ name: String, _ view: V, settle: Double = 1.5) async {
        let hosting = NSHostingView(rootView: view)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .windowBackgroundColor
        window.contentView = hosting
        window.center()
        window.orderFrontRegardless()
        await sleep(settle)
        save(window, name)
        window.orderOut(nil)
    }

    // MARK: Settings and About

    private func settingsTabs() async {
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        app.showSettings()
        await sleep(1.5)
        guard let window = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible })
                ?? NSApp.keyWindow, window !== mainWindow else {
            index.append("60-settings: window not found")
            return
        }
        let items = window.toolbar?.items.filter { $0.action != nil } ?? []
        if items.isEmpty {
            save(window, "60-settings")
        }
        for (i, item) in items.enumerated() {
            if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
            await sleep(1)
            save(window, "6\(i)-settings-\(item.label.lowercased())")
        }
        window.close()
    }

    private func aboutPanel() async {
        let before = Set(NSApp.windows.map { ObjectIdentifier($0) })
        AboutPanel.show()
        await sleep(1)
        guard let panel = NSApp.windows.first(where: { !before.contains(ObjectIdentifier($0)) && $0.isVisible }) else {
            index.append("70-about: panel not found")
            return
        }
        save(panel, "70-about")
        panel.close()
    }

    // MARK: Capture

    /// `CGWindowListCreateImage` is unavailable to Swift in the macOS 15 SDK but
    /// still works at runtime, and capturing the app's own windows needs no
    /// Screen Recording permission. It renders materials exactly as on screen.
    private typealias WindowImageFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    private static let windowImage: WindowImageFn? = {
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: WindowImageFn.self)
    }()

    private func save(_ window: NSWindow, _ name: String) {
        var method = "window server"
        var data: Data?
        // optionIncludingWindow = 1 << 3; boundsIgnoreFraming | bestResolution = 1 | 1 << 3
        if let fn = Self.windowImage, let image = fn(.null, 1 << 3, UInt32(window.windowNumber), 1 | 1 << 3)?.takeRetainedValue(),
           image.width > 1 {
            data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
        if data == nil, let view = window.contentView?.superview ?? window.contentView,
           let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            method = "cacheDisplay"
            view.cacheDisplay(in: view.bounds, to: rep)
            data = rep.representation(using: .png, properties: [:])
        }
        let url = out.appendingPathComponent("\(name).png")
        do {
            try data?.write(to: url)
            index.append("\(out.lastPathComponent)/\(name).png (\(method))")
        } catch {
            index.append("\(name): \(error.localizedDescription)")
        }
    }

    private func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

// MARK: - Fixtures

/// Made-up but realistic findings. Paths sit under the real home folder so they
/// show as ~/… without naming the user.
private enum Fixtures {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func item(
        _ category: JunkCategory, _ path: String, mb: Double, group: String, detail: String = "",
        keeper: Bool = false, low: Bool = false, inUse: String? = nil, reclaimable: Double? = nil
    ) -> JunkItem {
        var item = JunkItem(url: home.appendingPathComponent(path), size: Int64(mb * 1_000_000),
                            category: category, group: group, detail: detail)
        item.isKeeper = keeper
        item.confidence = low ? .low : nil
        item.inUseBy = inUse
        item.isSelected = !keeper && !low && inUse == nil
        item.reclaimable = reclaimable.map { Int64($0 * 1_000_000) }
        return item
    }

    static var results: [JunkCategory: CategoryResult?] {
        let system: [JunkItem] = [
            item(.systemJunk, "Library/Caches/com.spotify.client", mb: 1_840, group: "App caches", detail: "Spotify · rebuilt automatically"),
            item(.systemJunk, "Library/Caches/com.microsoft.teams2", mb: 612, group: "App caches", detail: "Microsoft Teams · rebuilt automatically", inUse: "Microsoft Teams"),
            item(.systemJunk, "Library/Caches/Homebrew/downloads", mb: 1_204, group: "App caches", detail: "Homebrew downloads"),
            item(.systemJunk, "Library/Logs/DiagnosticReports", mb: 86, group: "Logs", detail: "Crash and hang reports"),
            item(.systemJunk, "Library/Logs/JetBrains", mb: 212, group: "Logs", detail: "JetBrains Toolbox logs"),
            item(.systemJunk, "Library/Caches/TemporaryItems/Outlook Temp", mb: 41, group: "Temporary files", detail: "Older than 3 days"),
        ]
        let leftovers: [JunkItem] = [
            item(.appLeftovers, "Library/Application Support/Adobe/CoreSync", mb: 734, group: "com.adobe.acc", detail: "Adobe Creative Cloud"),
            item(.appLeftovers, "Library/Preferences/com.adobe.acc.AdobeCreativeCloud.plist", mb: 0.02, group: "com.adobe.acc", detail: "Adobe Creative Cloud"),
            item(.appLeftovers, "Library/Containers/com.parallels.desktop.console", mb: 455, group: "com.parallels.desktop", detail: "Parallels Desktop"),
            item(.appLeftovers, "Library/Application Support/Spotify", mb: 96, group: "Spotify", detail: "Name match only", low: true),
        ]
        let photos: [JunkItem] = [
            item(.duplicatePhotos, "Pictures/Iceland 2024/IMG_4312.HEIC", mb: 4.1, group: "a1", detail: "~/Pictures/Iceland 2024", keeper: true),
            item(.duplicatePhotos, "Downloads/IMG_4312.HEIC", mb: 4.1, group: "a1", detail: "~/Downloads"),
            item(.duplicatePhotos, "Desktop/IMG_4312 copy.HEIC", mb: 4.1, group: "a1", detail: "~/Desktop", reclaimable: 0),
            item(.duplicatePhotos, "Pictures/Wallpapers/aurora.jpg", mb: 11.6, group: "b2", detail: "~/Pictures/Wallpapers", keeper: true),
            item(.duplicatePhotos, "Downloads/aurora (1).jpg", mb: 11.6, group: "b2", detail: "~/Downloads"),
        ]
        let browser: [JunkItem] = [
            item(.browserCaches, "Library/Caches/Google/Chrome/Default/Cache", mb: 980, group: "Google Chrome", detail: "Cached web content"),
            item(.browserCaches, "Library/Caches/com.apple.Safari/WebKitCache", mb: 326, group: "Safari", detail: "Cached web content"),
            item(.browserCaches, "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", mb: 148, group: "Mail", detail: "Opened attachments"),
        ]
        return [
            .systemJunk: CategoryResult(category: .systemJunk, items: system),
            .appLeftovers: CategoryResult(category: .appLeftovers, items: leftovers),
            .duplicatePhotos: CategoryResult(category: .duplicatePhotos, items: photos),
            .browserCaches: CategoryResult(category: .browserCaches, items: browser),
        ]
    }

    static func summary(failures: Bool) -> CleanupSummary {
        var outcome = Cleaner.Outcome()
        outcome.trashed = Set((0..<412).map { URL(fileURLWithPath: "/tmp/fixture-\($0)") })
        outcome.trashedBytes = 6_412_000_000
        outcome.reclaimableBytes = 6_398_000_000
        if failures {
            outcome.failures = [
                Cleaner.Failure(url: home.appendingPathComponent("Library/Caches/com.microsoft.teams2"), reason: "Microsoft Teams is running"),
                Cleaner.Failure(url: home.appendingPathComponent("Library/Logs/JetBrains"), reason: "Permission denied"),
            ]
        }
        var summary = CleanupSummary(outcome)
        summary.recordID = UUID()
        return summary
    }

    static let threats: [Threat] = [
        Threat(url: home.appendingPathComponent("Downloads/CleanMyMac_Crack_5.2.dmg"), size: 48_200_000,
               engine: .malwareBazaar, identifier: "9f2c4e6a1b7d3c5e8f0a2b4c6d8e0f1a3b5c7d9e1f2a4b6c8d0e2f4a6b8c0d2e"),
        Threat(url: home.appendingPathComponent("Library/LaunchAgents/com.mac.updater.plist"), size: 1_204,
               engine: .clamAV, identifier: "Osx.Trojan.Atomic-10021"),
    ]

    static let quarantine: [Quarantine.Entry] = [
        Quarantine.Entry(id: UUID(), originalPath: home.appendingPathComponent("Downloads/FreeVPN-Installer.pkg").path,
                         storedPath: "/System/Library/CoreServices/SystemVersion.plist", engine: .malwareBazaar,
                         identifier: "4b8e1d0c7a2f5e9b3c6d1a8f4e7b0c2d5a9e3f6b1c4d8a7e0f2b5c9d3a6e1f4b",
                         size: 12_800_000, date: Date().addingTimeInterval(-86_400 * 3), originalPermissions: 0o644),
        Quarantine.Entry(id: UUID(), originalPath: home.appendingPathComponent("Library/LaunchAgents/com.mac.updater.plist").path,
                         storedPath: "/System/Library/CoreServices/SystemVersion.plist", engine: .clamAV,
                         identifier: "Osx.Trojan.Atomic-10021", size: 1_204,
                         date: Date().addingTimeInterval(-86_400 * 41), originalPermissions: 0o644),
    ]
}
#endif

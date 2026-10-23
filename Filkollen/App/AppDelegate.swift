import AppKit
import SwiftUI

/// Owns the shared models so both the main window and the menu bar extra see
/// the same state, and handles "keep running in the menu bar" behaviour.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model: AppModel
    let protection: ProtectionModel
    let selfUpdater: SelfUpdater
    let updates: UpdatesModel
    private(set) var scheduler: BackgroundScheduler!

    /// The running app's delegate, for App Intents (SwiftUI owns the instance).
    private(set) static weak var shared: AppDelegate?

    /// Set by the first SwiftUI view that appears; reopens the main window later.
    var openMainWindowAction: (() -> Void)?

    override init() {
        Pref.registerDefaults()
        model = AppModel()
        protection = ProtectionModel()
        updates = UpdatesModel()
        selfUpdater = SelfUpdater()
        super.init()
        Self.shared = self
        scheduler = BackgroundScheduler(model: model, protection: protection, updates: updates)
    }

    /// Start with no window and no Dock icon (login launch or "always start hidden").
    private var pendingHide = false

    /// Living in the menu bar only makes sense while the menu bar icon is shown;
    /// otherwise the app keeps its Dock icon so it can still be reached.
    private var livesInMenuBar: Bool {
        Pref.defaults.bool(forKey: Pref.keepRunningInMenuBar) && Pref.defaults.bool(forKey: Pref.showMenuBarIcon)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        if livesInMenuBar, Pref.defaults.bool(forKey: Pref.alwaysStartHidden) {
            pendingHide = true
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The launch Apple event is only readable from here on.
        if livesInMenuBar, launchedAsLoginItem {
            pendingHide = true
            NSApp.setActivationPolicy(.accessory)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil
        )
        // SwiftUI may create the window just after launch; RootView also calls this when it appears.
        DispatchQueue.main.async { [weak self] in self?.hideIfPending() }
        // Unit tests run inside the app; keep them free of scheduled scans and network.
        guard !AppEnvironment.isRunningTests else { return }
        scheduler.start()
        protection.startBackgroundWatchers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Pref.defaults.bool(forKey: Pref.keepRunningInMenuBar)
    }

    /// Dock icon clicked, or the app opened again from Finder, with no window open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    // MARK: Window / Dock handling

    func hideIfPending() {
        guard pendingHide, !mainWindows.isEmpty else { return }
        pendingHide = false
        hideToMenuBar()
    }

    func showMainWindow() {
        pendingHide = false
        NSApp.setActivationPolicy(.regular)
        if let open = openMainWindowAction {
            open()   // brings the existing window forward, or recreates it
        } else {
            mainWindows.first?.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func hideToMenuBar() {
        mainWindows.forEach { $0.close() }
        if livesInMenuBar { NSApp.setActivationPolicy(.accessory) }
    }

    /// Real app windows (not the menu bar panel, status item or alerts).
    private var mainWindows: [NSWindow] {
        NSApp.windows.filter {
            $0.canBecomeMain && !($0 is NSPanel) && !String(describing: type(of: $0)).contains("MenuBarExtra")
        }
    }

    @objc private func windowWillClose(_ note: Notification) {
        guard let closing = note.object as? NSWindow, mainWindows.contains(closing), livesInMenuBar else { return }
        // After the last real window closes, drop the Dock icon and live in the menu bar.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if !self.mainWindows.contains(where: { $0 !== closing && $0.isVisible }) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }
}

enum AppEnvironment {
    static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || NSClassFromString("XCTestCase") != nil
}

/// Periodic work while the app runs, including with no window open.
@MainActor
final class BackgroundScheduler {
    private let model: AppModel
    private let protection: ProtectionModel
    private let updates: UpdatesModel
    private var timer: Timer?

    init(model: AppModel, protection: ProtectionModel, updates: UpdatesModel) {
        self.model = model
        self.protection = protection
        self.updates = updates
    }

    func start() {
        if Pref.defaults.bool(forKey: Pref.notificationsEnabled) { Notifier.requestPermission() }
        // First check shortly after launch, then every 15 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func tick() {
        let d = Pref.defaults

        let hours = d.integer(forKey: Pref.autoScanHours)
        if hours > 0, model.canStartBackgroundScan, isDue(model.lastSmartScan, hours: hours) {
            model.startSmartScan { [weak self] in
                guard let self else { return }
                let total = self.model.smartScanTotal
                if total > 500 * 1_048_576 {
                    Notifier.post("Filkollen found \(total.formattedBytes) of junk",
                                  "Open Filkollen to review and clean it.")
                }
            }
        }

        if d.bool(forKey: Pref.autoUpdateThreatDB), protection.databaseIsStale,
           ThreatDatabase.authKey != nil, !protection.isBusy {
            protection.updateDatabase()
        }

        if d.bool(forKey: Pref.autoCheckUpdates), !updates.isChecking,
           isDue(updates.lastChecked, hours: 24) {
            updates.check { found in
                guard !found.isEmpty else { return }
                Notifier.post("\(found.count) update\(found.count == 1 ? "" : "s") available",
                              found.prefix(3).map(\.name).joined(separator: ", ") + (found.count > 3 ? "…" : ""))
            }
        }
    }

    private func isDue(_ last: Date?, hours: Int) -> Bool {
        guard let last else { return true }
        return Date().timeIntervalSince(last) >= TimeInterval(hours) * 3600
    }
}

import SwiftUI

@main
struct FilkollenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(Pref.showMenuBarIcon) private var showMenuBarIcon = true

    /// Jumps to a page in the main window, opening it if it was closed.
    @MainActor private func go(_ section: AppModel.Section) {
        delegate.model.section = section
        delegate.showMainWindow()
    }

    var body: some Scene {
        // A single Window (not WindowGroup) so reopening from the menu bar never
        // stacks up duplicate main windows.
        Window("Filkollen", id: "main") {
            RootView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
                .environmentObject(delegate)
                .frame(minWidth: DS.Layout.windowMinWidth, minHeight: DS.Layout.windowMinHeight)
                .dsAccent()
        }
        .defaultSize(width: DS.Layout.windowDefaultWidth, height: DS.Layout.windowDefaultHeight)
        // A real (transparent) title bar keeps the sidebar list below the
        // traffic lights; .hiddenTitleBar let rows scroll underneath them.
        .windowToolbarStyle(.unified(showsTitle: false))
        // Don't let the window shrink below what the current page needs,
        // otherwise SwiftUI overflows the split view past the window edges.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("About Filkollen") { AboutPanel.show() }
                if delegate.selfUpdater.isAvailable {
                    Button("Check for Filkollen Updates…") { delegate.selfUpdater.checkForUpdates() }
                }
            }
            CommandGroup(after: .help) {
                Button("Export Diagnostics…") { Diagnostics.export() }
            }
            CommandMenu("Scan") {
                Button("Smart Scan") { delegate.model.startSmartScan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Malware Scan") { delegate.protection.scan() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Check for Updates") { delegate.updates.check() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandMenu("Go") {
                Button("Smart Scan") { go(.smartScan) }.keyboardShortcut("1", modifiers: .command)
                Button("Malware Scan") { go(.protection) }.keyboardShortcut("2", modifiers: .command)
                Button("App Uninstaller") { go(.uninstaller) }.keyboardShortcut("3", modifiers: .command)
                Button("History") { go(.history) }.keyboardShortcut("4", modifiers: .command)
                Button("App Updates") { go(.updates) }.keyboardShortcut("5", modifiers: .command)
                Button("Disk Usage") { go(.system(.diskUsage)) }.keyboardShortcut("6", modifiers: .command)
            }
            #if DEBUG
            DebugCommands()
            #endif
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
                .environmentObject(delegate)
                .dsAccent()
        } label: {
            MenuBarLabel(model: delegate.model, protection: delegate.protection)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(delegate.selfUpdater)
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
                .dsAccent()
        }

        #if DEBUG
        Window("Design Gallery", id: DebugCommands.galleryID) {
            DesignGalleryView()
        }
        #endif
    }
}

#if DEBUG
/// Debug › Design Gallery. Only in Debug builds.
struct DebugCommands: Commands {
    static let galleryID = "design-gallery"
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandMenu("Debug") {
            Button("Design Gallery") { openWindow(id: Self.galleryID) }
                .keyboardShortcut("g", modifiers: [.command, .option])
        }
    }
}
#endif

/// The status item icon: a warning badge when threats were found, a busy icon while scanning.
private struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var protection: ProtectionModel

    var body: some View {
        if !protection.threats.isEmpty {
            Image(systemName: "exclamationmark.shield.fill")
        } else if model.isScanning || protection.isBusy {
            Image(systemName: "arrow.triangle.2.circlepath")
        } else {
            Image(systemName: "sparkles")
        }
    }
}

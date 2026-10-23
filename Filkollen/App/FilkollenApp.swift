import SwiftUI

@main
struct FilkollenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @AppStorage(Pref.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        // A single Window (not WindowGroup) so reopening from the menu bar never
        // stacks up duplicate main windows.
        Window("Filkollen", id: "main") {
            RootView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
                .environmentObject(delegate)
                .frame(minWidth: 940, minHeight: 620)
        }
        // A real (transparent) title bar keeps the sidebar list below the
        // traffic lights; .hiddenTitleBar let rows scroll underneath them.
        .windowToolbarStyle(.unified(showsTitle: false))
        // Don't let the window shrink below what the current page needs,
        // otherwise SwiftUI overflows the split view past the window edges.
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Smart Scan") { delegate.model.startSmartScan() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Malware Scan") { delegate.protection.scan() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Check for Updates") { delegate.updates.check() }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
                .environmentObject(delegate)
        } label: {
            MenuBarLabel(model: delegate.model, protection: delegate.protection)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(delegate.model)
                .environmentObject(delegate.protection)
                .environmentObject(delegate.updates)
        }
    }
}

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

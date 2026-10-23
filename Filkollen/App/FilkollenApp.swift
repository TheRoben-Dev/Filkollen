import SwiftUI

@main
struct FilkollenApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var protection = ProtectionModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(protection)
                .frame(minWidth: 940, minHeight: 620)
        }
        // A real (transparent) title bar keeps the sidebar list below the
        // traffic lights; .hiddenTitleBar let rows scroll underneath them.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Smart Scan") { model.startSmartScan() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.isScanning)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(protection)
        }
    }
}

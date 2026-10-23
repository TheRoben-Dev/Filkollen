import Combine
import SwiftUI

/// First-run screen that explains and walks through granting Full Disk Access.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            BackdropView(tint: .purple)
            VStack(spacing: 28) {
                GradientIcon(symbol: "externaldrive.fill.badge.checkmark", gradient: Theme.accent, size: 96)

                VStack(spacing: 10) {
                    Text("Welcome to Filkollen")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("To find junk hiding in Library folders, Filkollen needs Full Disk Access.\nIt only reads what it scans, and nothing leaves your Mac.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.75))
                }

                VStack(alignment: .leading, spacing: 14) {
                    step(1, "Open **System Settings › Privacy & Security › Full Disk Access**")
                    step(2, "Click **+** (or drag Filkollen in) and switch it on")
                    step(3, "Come back here. Filkollen notices automatically")
                }
                .glassCard(padding: 22)
                .frame(maxWidth: 520)

                HStack(spacing: 12) {
                    Button("Open System Settings") { FullDiskAccess.openSettings() }
                        .buttonStyle(PillButtonStyle(large: true))
                    Button("Show Filkollen in Finder") { FullDiskAccess.revealAppInFinder() }
                        .buttonStyle(GhostButtonStyle())
                }

                if model.hasFullDiskAccess {
                    Label("Access granted, you're all set!", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Continue without Full Disk Access") { model.skipOnboarding() }
                        .buttonStyle(.link)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("Granted it and nothing happens? macOS sometimes needs a relaunch.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    Button("Relaunch Filkollen", action: relaunch)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(40)
            .foregroundStyle(.white)
        }
        .onReceive(poll) { _ in model.refreshFullDiskAccess() }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(n)")
                .font(.callout.bold())
                .frame(width: 26, height: 26)
                .background(Theme.accent, in: Circle())
            Text(text)
        }
    }

    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

import Combine
import SwiftUI

/// First-run screen that explains and walks through granting Full Disk Access.
/// When access arrives it shows a short "granted" moment before RootView hands off.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            Spacer(minLength: 0)

            ZStack {
                if model.hasFullDiskAccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DS.Color.success)
                        .dsTransition(.dsPop)
                } else {
                    DSTile(symbol: "externaldrive.fill.badge.checkmark", tint: DS.Color.brand, size: .large)
                        .scaleEffect(1.3)
                        .dsTransition(.dsPop)
                }
            }
            .frame(height: 80)
            .accessibilityHidden(true)

            VStack(spacing: DS.Space.sm) {
                Text(model.hasFullDiskAccess ? "Access granted, you're all set" : "Welcome to Filkollen")
                    .font(DS.Font.heroTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(model.hasFullDiskAccess
                     ? "Filkollen can now see the Library folders where junk hides."
                     : "To find junk hiding in Library folders, Filkollen needs Full Disk Access. It only reads what it scans, and nothing leaves your Mac.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: DS.Layout.readableWidth)
            }

            if !model.hasFullDiskAccess {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    step(1, "Open **System Settings › Privacy & Security › Full Disk Access**")
                    step(2, "Click **+** (or drag Filkollen in) and switch it on")
                    step(3, "Come back here. Filkollen notices automatically")
                }
                .frame(maxWidth: DS.Layout.readableWidth, alignment: .leading)
                .dsCard(insets: DS.Inset.hero)
                .frame(maxWidth: DS.Layout.readableWidth + DS.Space.xxxl * 2)

                HStack(spacing: DS.Space.md) {
                    Button("Open System Settings") { FullDiskAccess.openSettings() }
                        .buttonStyle(.ds(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                    Button("Show Filkollen in Finder") { FullDiskAccess.revealAppInFinder() }
                        .buttonStyle(.ds(.secondary, size: .large))
                }

                VStack(spacing: DS.Space.xs) {
                    Button("Continue without Full Disk Access") { model.skipOnboarding() }
                        .buttonStyle(.dsPlain)
                    HStack(spacing: DS.Space.xs) {
                        Text("Granted it and nothing happens? macOS sometimes needs a relaunch.")
                            .foregroundStyle(DS.Color.textSecondary)
                        Button("Relaunch Filkollen", action: relaunch)
                            .buttonStyle(.dsPlain)
                    }
                    .font(DS.Font.caption)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(DS.Inset.hero)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSBackdrop().ignoresSafeArea())
        .dsAnimation(.smooth, value: model.hasFullDiskAccess)
        .onReceive(poll) { _ in model.refreshFullDiskAccess() }
        .onChange(of: model.hasFullDiskAccess) { granted in
            guard granted else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: String(localized: "Full Disk Access granted")])
        }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text("\(n)")
                .font(DS.Font.captionEmphasized.monospacedDigit())
                .foregroundStyle(DS.Color.textOnAccent)
                .frame(width: 22, height: 22)
                .background(DS.Color.brand, in: Circle())
                .accessibilityLabel(String(localized: "Step \(n)"))
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

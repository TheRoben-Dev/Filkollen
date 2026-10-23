import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var app: AppDelegate
    @Environment(\.openWindow) private var openWindow
    /// Follows `model.showOnboarding`, but holds onboarding up briefly after
    /// access is granted so the "granted" moment is seen before the hand-off.
    @State private var holdOnboarding = false

    var body: some View {
        Group {
            if model.showOnboarding || holdOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .dsAnimation(.smooth, value: model.showOnboarding || holdOnboarding)
        .onChange(of: model.showOnboarding) { showing in
            guard !showing, model.hasFullDiskAccess else { return }
            holdOnboarding = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { holdOnboarding = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
        }
        .registersSettingsOpener(app)
        .onAppear {
            app.openMainWindowAction = { openWindow(id: "main") }
            DispatchQueue.main.async { app.hideIfPending() }
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: DS.Layout.sidebarMin, ideal: DS.Layout.sidebarIdeal, max: DS.Layout.sidebarMax)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.Color.backgroundWindow)
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .smartScan: SmartScanView()
        case .category(let category): CategoryDetailView(category: category)
        case .uninstaller: UninstallerView()
        case .history: HistoryView()
        case .protection: ProtectionView()
        case .updates: UpdatesView()
        case .system(.overview): SystemOverviewView()
        case .system(.startupItems): StartupItemsView()
        case .system(.snapshots): TimeMachineView()
        case .system(.diskUsage): DiskUsageView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var protection: ProtectionModel
    @EnvironmentObject private var updates: UpdatesModel

    var body: some View {
        List(selection: Binding<AppModel.Section?>(
            get: { model.section },
            set: { if let s = $0 { model.section = s } }
        )) {
            Label("Smart Scan", systemImage: DS.Icon.scan)
                .tag(AppModel.Section.smartScan)

            Section("Cleanup") {
                ForEach(JunkCategory.allCases) { category in
                    Label {
                        HStack {
                            Text(category.title)
                            Spacer(minLength: DS.Space.xs)
                            if let size = model.result(for: category)?.totalSize, size > 0 {
                                Text(size.formattedBytes)
                                    .font(DS.Font.numericCaption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                    } icon: {
                        DSTile(category, size: .small)
                    }
                    .tag(AppModel.Section.category(category))
                }
                Label("App Uninstaller", systemImage: "xmark.app")
                    .tag(AppModel.Section.uninstaller)
                Label("History", systemImage: "clock.arrow.circlepath")
                    .tag(AppModel.Section.history)
            }

            Section("Protection") {
                HStack {
                    Label("Malware Scan", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    if !protection.threats.isEmpty {
                        SidebarCount(value: protection.threats.count, tint: DS.ProtectionState.threat.color)
                            .accessibilityLabel(String(localized: "\(protection.threats.count) threats"))
                    }
                }
                .tag(AppModel.Section.protection)
            }

            Section("Maintenance") {
                ForEach(AppModel.SystemPage.allCases, id: \.self) { page in
                    Label(page.title, systemImage: page.symbol)
                        .tag(AppModel.Section.system(page))
                }
                HStack {
                    Label("App Updates", systemImage: "arrow.down.app")
                    Spacer()
                    if updates.isChecking {
                        ProgressView().controlSize(.mini)
                    } else if !updates.updates.isEmpty {
                        SidebarCount(value: updates.updates.count, tint: DS.Color.info)
                            .accessibilityLabel(String(localized: "\(updates.updates.count) updates"))
                    }
                }
                .tag(AppModel.Section.updates)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !model.hasFullDiskAccess {
                Button {
                    FullDiskAccess.openSettings()
                } label: {
                    HStack(alignment: .top, spacing: DS.Space.sm) {
                        Image(systemName: "exclamationmark.lock.fill")
                            .foregroundStyle(DS.Color.warning)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(model.fullDiskAccessRevoked ? "Full Disk Access was turned off" : "Full Disk Access is off")
                                .font(DS.Font.captionEmphasized)
                                .foregroundStyle(DS.Color.textPrimary)
                            Text(model.fullDiskAccessRevoked
                                 ? "Scans will miss most of your Library. Click to turn it back on."
                                 : "Scans can't see most of your Library. Click to turn it on.")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DS.Inset.row)
                    .background(DS.Color.warning.opacity(0.1), in: DS.shape(DS.Radius.row))
                    .overlay(DS.shape(DS.Radius.row).strokeBorder(DS.Color.warning.opacity(0.3), lineWidth: 1))
                    .contentShape(DS.shape(DS.Radius.row))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Privacy & Security in System Settings")
                .padding(DS.Space.md)
            }
        }
    }
}

/// A count pill in the sidebar (threats, updates).
private struct SidebarCount: View {
    let value: Int
    let tint: Color

    var body: some View {
        Text(value.formatted())
            .font(DS.Font.badge.monospacedDigit())
            .foregroundStyle(DS.Color.textOnFill)
            .padding(DS.Inset.badge)
            .background(tint, in: Capsule())
    }
}

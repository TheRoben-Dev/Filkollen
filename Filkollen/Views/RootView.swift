import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var app: AppDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.showOnboarding {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainView()
            }
        }
        .preferredColorScheme(.dark)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .animation(.easeInOut, value: model.showOnboarding)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
        }
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
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            ZStack {
                BackdropView(tint: tint)
                detail
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch model.section {
        case .smartScan: SmartScanView()
        case .category(let category): CategoryDetailView(category: category)
        case .protection: ProtectionView()
        case .updates: UpdatesView()
        case .system(.overview): SystemOverviewView()
        case .system(.startupItems): StartupItemsView()
        }
    }

    private var tint: Color {
        switch model.section {
        case .smartScan: return .pink
        case .category(let c): return c.tint
        case .protection: return .green
        case .updates: return .cyan
        case .system(.overview): return .teal
        case .system(.startupItems): return .orange
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
            Label("Smart Scan", systemImage: "sparkles")
                .tag(AppModel.Section.smartScan)

            Section("Cleanup") {
                ForEach(JunkCategory.allCases) { category in
                    HStack {
                        Label(category.title, systemImage: category.symbol)
                        Spacer()
                        if let size = model.result(for: category)?.totalSize, size > 0 {
                            Text(size.formattedBytes)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(AppModel.Section.category(category))
                }
            }

            Section("Protection") {
                HStack {
                    Label("Malware Scan", systemImage: "shield.lefthalf.filled")
                    Spacer()
                    if !protection.threats.isEmpty {
                        Text("\(protection.threats.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.red, in: Capsule())
                    }
                }
                .tag(AppModel.Section.protection)
            }

            Section("Maintenance") {
                ForEach(AppModel.SystemPage.allCases, id: \.self) { page in
                    Label(page.rawValue, systemImage: page.symbol)
                        .tag(AppModel.Section.system(page))
                }
                HStack {
                    Label("App Updates", systemImage: "arrow.down.app.fill")
                    Spacer()
                    if updates.isChecking {
                        ProgressView().controlSize(.mini)
                    } else if !updates.updates.isEmpty {
                        Text("\(updates.updates.count)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.blue, in: Capsule())
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
                    VStack(alignment: .leading, spacing: 2) {
                        Label(model.fullDiskAccessRevoked ? "Full Disk Access was turned off" : "Full Disk Access is off",
                              systemImage: "exclamationmark.lock.fill")
                            .font(.caption.weight(.semibold))
                        if model.fullDiskAccessRevoked {
                            Text("Scans will miss most of your Library. Click to turn it back on.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .padding(12)
            }
        }
    }
}

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

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
        .animation(.easeInOut, value: model.showOnboarding)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshFullDiskAccess()
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
        }
    }

    private var tint: Color {
        switch model.section {
        case .smartScan: return .pink
        case .category(let c): return c.tint
        case .protection: return .green
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var protection: ProtectionModel

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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !model.hasFullDiskAccess {
                Button {
                    FullDiskAccess.openSettings()
                } label: {
                    Label("Full Disk Access is off", systemImage: "exclamationmark.lock.fill")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .padding(12)
            }
        }
    }
}

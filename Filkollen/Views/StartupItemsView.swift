import SwiftUI

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var loading = true
    @State private var pendingRemoval: StartupItem?
    @State private var errorMessage: String?

    private let scopes: [StartupItem.Scope] = [.userAgent, .systemAgent, .systemDaemon]

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 18)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(padding: 12)
                    .padding(.horizontal, 28).padding(.bottom, 12)
            }

            if loading {
                Spacer()
                ProgressView()
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        loginItemsCard
                        ForEach(scopes, id: \.self) { scope in
                            let list = items.filter { $0.scope == scope }
                            if !list.isEmpty { section(scope, list) }
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 28)
                }
            }
        }
        .foregroundStyle(.white)
        .task { await reload() }
        .confirmationDialog(
            "Remove \(pendingRemoval?.displayName ?? "")?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { item in
            Button("Stop and Move to Trash", role: .destructive) { remove(item) }
        } message: { _ in
            Text("The launch agent is unloaded and its file moved to the Trash. You can put it back from the Trash if something stops working.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GradientIcon(symbol: AppModel.SystemPage.startupItems.symbol, gradient: Theme.gradient(.orange, .red), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Startup Items").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var subtitle: String {
        let broken = items.filter(\.isBroken).count
        let base = "\(items.count) launch agents and daemons"
        return broken > 0 ? base + ", \(broken) pointing to missing apps" : base
    }

    private var loginItemsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark").font(.title2).foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Login Items").font(.headline)
                Text("Apps that open when you log in are managed in System Settings.")
                    .font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Button("Open Login Items") { LoginItem.openSystemSettings() }
                .buttonStyle(GhostButtonStyle())
        }
        .glassCard(padding: 14)
    }

    private func section(_ scope: StartupItem.Scope, _ list: [StartupItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(scope.rawValue).font(.headline)
                Text("\(list.count)").font(.caption.bold())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.white.opacity(0.15), in: Capsule())
                Spacer()
                if !scope.removable {
                    Text("Needs an administrator to change")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
            }
            ForEach(list) { item in
                StartupRow(item: item) { pendingRemoval = item }
                if item.id != list.last?.id { Divider().overlay(.white.opacity(0.08)) }
            }
        }
        .glassCard()
    }

    private func reload() async {
        loading = items.isEmpty
        items = await Task.detached(priority: .userInitiated) { StartupItems.load() }.value
        loading = false
    }

    private func remove(_ item: StartupItem) {
        Task {
            do {
                try await StartupItems.remove(item)
                errorMessage = nil
                items.removeAll { $0.id == item.id }
            } catch {
                errorMessage = "Couldn't remove \(item.displayName): \(error.localizedDescription)"
            }
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isBroken ? "exclamationmark.triangle.fill" : "power.circle.fill")
                .font(.title3)
                .foregroundStyle(item.isBroken ? Color.orange : Color.white.opacity(0.7))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName).font(.body.weight(.medium)).lineLimit(1)
                    if item.isBroken { Badge("App missing", .orange) }
                    if item.disabled { Badge("Disabled", .gray) }
                    if item.runAtLoad && !item.disabled { Badge("Runs at login", .blue) }
                }
                Text(item.label).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            if item.scope.removable {
                Button("Remove", action: onRemove).buttonStyle(GhostButtonStyle())
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let color: Color
    init(_ text: String, _ color: Color) { self.text = text; self.color = color }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.3), in: Capsule())
    }
}

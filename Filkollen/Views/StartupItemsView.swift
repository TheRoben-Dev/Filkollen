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
                .padding(DS.Inset.page)

            if let errorMessage {
                DSBanner(.error, title: errorMessage)
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.md)
            }

            if loading {
                VStack(spacing: DS.Space.sm) {
                    ForEach(0..<6, id: \.self) { _ in DSPlaceholderRow() }
                }
                .padding(.horizontal, DS.Space.xxl)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: DS.Space.md) {
                        loginItemsCard
                        ForEach(scopes, id: \.self) { scope in
                            let list = items.filter { $0.scope == scope }
                            if !list.isEmpty { section(scope, list) }
                        }
                    }
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.xxl)
                }
            }
        }
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
        DSPageHeader(title: String(localized: "Startup Items"), subtitle: subtitle,
                     tile: DSTile(symbol: AppModel.SystemPage.startupItems.symbol, tint: DS.Color.brand, size: .large)) {
            Button { Task { await reload() } } label: { Label("Refresh", systemImage: DS.Icon.refresh) }
                .buttonStyle(.dsSecondary)
        }
    }

    private var subtitle: String {
        let broken = items.filter(\.isBroken).count
        let review = items.filter(\.needsReview).count
        var parts = [items.count == 1 ? String(localized: "1 launch agent or daemon")
                                      : String(localized: "\(items.count) launch agents and daemons")]
        if broken > 0 { parts.append(String(localized: "\(broken) pointing to missing apps")) }
        if review > 0 { parts.append(String(localized: "\(review) worth a closer look")) }
        return parts.joined(separator: ", ")
    }

    private var loginItemsCard: some View {
        DSBanner(kind: .info, title: String(localized: "Login Items"),
                 message: String(localized: "Apps that open when you log in are managed in System Settings.")) {
            Button("Open Login Items") { LoginItem.openSystemSettings() }
                .buttonStyle(.dsSecondary)
        }
    }

    private func section(_ scope: StartupItem.Scope, _ list: [StartupItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSSectionHeader(title: String(localized: String.LocalizationValue(scope.rawValue)),
                            subtitle: scope.removable ? nil : String(localized: "Needs an administrator to change")) {
                Text(list.count.formatted()).font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
            }
            ForEach(list) { item in
                StartupRow(item: item) { pendingRemoval = item }
                if item.id != list.last?.id { Divider() }
            }
        }
        .dsCard()
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
                errorMessage = String(localized: "Couldn't remove \(item.displayName): \(error.localizedDescription)")
            }
        }
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: item.isBroken ? DS.Icon.warning : "power.circle.fill")
                .font(DS.Font.sectionTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isBroken ? DS.Color.warning : DS.Color.textSecondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Text(item.displayName).font(DS.Font.bodyEmphasized).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    if item.isBroken { badge("App missing", "questionmark.app.fill", DS.Color.warning) }
                    if let trust = item.trust {
                        badge(trust.level.label, trust.level.isConcerning ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                              trust.level.isConcerning ? DS.Color.danger : DS.Color.success)
                            .help(trust.teamID.map { "Team ID \($0)" + (trust.signer.map { " · \($0)" } ?? "") } ?? "No signing identity")
                    }
                    if item.isScript { badge("Script", "terminal.fill", DS.Color.info) }
                    if item.oddLocation { badge("Unusual location", "mappin.slash", DS.Color.danger) }
                    if item.disabled { badge("Disabled", "pause.circle.fill", DS.Color.textSecondary) }
                    if item.runAtLoad && !item.disabled { badge("Runs at login", "power", DS.Color.info) }
                }
                Text(item.label).dsPath()
                    .textSelection(.enabled)
                if let target = item.target {
                    Text(target).dsPath()
                        .foregroundStyle(DS.Color.textTertiary)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            DSIconButton(String(localized: "Show \(item.displayName) in Finder"), symbol: DS.Icon.revealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([item.plist])
            }
            if item.scope.removable {
                Button("Remove…", action: onRemove).buttonStyle(.dsSecondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func badge(_ title: String, _ symbol: String, _ tint: Color) -> DSBadge {
        DSBadge(.custom(String(localized: String.LocalizationValue(title)), symbol: symbol, tint: tint))
    }
}

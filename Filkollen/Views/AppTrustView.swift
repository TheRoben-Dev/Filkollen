import SwiftUI

/// Who signed each installed app. Read-only: nothing here changes an app.
struct AppTrustView: View {
    struct Row: Identifiable, Hashable, Sendable {
        var id: URL { url }
        let url: URL
        let name: String
        var report: CodeTrust.Report
        var deepChecked = false
    }

    @State private var rows: [Row] = []
    @State private var loading = true
    @State private var showAll = false
    @State private var checking: Set<URL> = []

    private var visible: [Row] { showAll ? rows : rows.filter { $0.report.level.isConcerning || $0.report.level == .developerID } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Text(summary).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Toggle("Show all apps", isOn: $showAll).toggleStyle(.switch).controlSize(.small)
                Button { Task { await load() } } label: { Label("Refresh", systemImage: DS.Icon.refresh) }
                    .buttonStyle(.dsSecondary)
                    .disabled(loading)
            }
            .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.md)

            if loading {
                VStack(spacing: DS.Space.sm) {
                    ForEach(0..<6, id: \.self) { _ in DSPlaceholderRow() }
                }
                .padding(.horizontal, DS.Space.xxl)
                .accessibilityElement()
                .accessibilityLabel(String(localized: "Checking signatures…"))
                Spacer(minLength: 0)
            } else if visible.isEmpty {
                DSEmptyState(symbol: "checkmark.seal.fill", tint: DS.Color.success,
                             title: String(localized: "All apps look trustworthy"),
                             message: String(localized: "Every app is signed by Apple, notarized, or from the App Store."))
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        ForEach(visible) { row in rowView(row) }
                    }
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
                }
            }
            Text("Checked offline. \"Developer ID\" means signed by a registered developer with no notarization ticket attached; that's common and not a problem on its own. Unsigned or broken signatures deserve a closer look.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Inset.bar)
                .overlay(alignment: .top) { Divider() }
        }
        .task { if rows.isEmpty { await load() } }
    }

    private var summary: String {
        let concerning = rows.filter { $0.report.level.isConcerning }.count
        return concerning == 0 ? String(localized: "\(rows.count) apps checked")
                               : String(localized: "\(rows.count) apps checked, \(concerning) unsigned or broken")
    }

    private func levelBadge(_ level: CodeTrust.Level) -> DSBadge {
        switch level {
        case .invalid, .unsigned, .adHoc:
            return DSBadge(.custom(String(localized: String.LocalizationValue(level.label)), symbol: "exclamationmark.triangle.fill", tint: DS.Color.danger))
        case .developerID:
            return DSBadge(.custom(String(localized: String.LocalizationValue(level.label)), symbol: "person.badge.shield.checkmark.fill", tint: DS.Color.warning))
        case .notarized:
            return DSBadge(.notarized)
        case .appStore, .apple:
            return DSBadge(.custom(String(localized: String.LocalizationValue(level.label)), symbol: "checkmark.seal.fill", tint: DS.Color.success))
        }
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: DS.Space.md) {
            DSFileIcon(url: row.url, size: DS.Icon.TileSize.medium.side)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Text(row.name).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    levelBadge(row.report.level)
                    if row.report.quarantined {
                        Text("Never opened").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                    if row.deepChecked {
                        Image(systemName: "checkmark.seal").font(DS.Font.caption).foregroundStyle(DS.Color.success)
                            .help("Every file in the app was verified")
                            .accessibilityLabel(String(localized: "Every file verified"))
                    }
                }
                Text([row.report.signer, row.report.teamID.map { String(localized: "Team \($0)") }].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer()
            if checking.contains(row.url) {
                ProgressView().controlSize(.small)
            } else if !row.deepChecked {
                Button("Verify All Files") { Task { await deepCheck(row) } }
                    .buttonStyle(.dsSecondary)
                    .help("Checks every file in the app against its signature. Slower for big apps.")
            }
            DSIconButton(String(localized: "Show \(row.name) in Finder"), symbol: DS.Icon.revealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            }
        }
        .dsCard(insets: DS.Inset.row)
        .accessibilityElement(children: .contain)
    }

    private func load() async {
        loading = true
        rows = await Task.detached(priority: .userInitiated) { () -> [Row] in
            let apps = AppTrustView.appURLs()
            let reports = parallelMap(apps) { CodeTrust.evaluate($0) }
            return zip(apps, reports).map { url, report in
                Row(url: url, name: url.deletingPathExtension().lastPathComponent, report: report)
            }
            .sorted { ($0.report.level, $0.name.lowercased()) < ($1.report.level, $1.name.lowercased()) }
        }.value
        loading = false
    }

    private func deepCheck(_ row: Row) async {
        checking.insert(row.url)
        let report = await Task.detached(priority: .userInitiated) { CodeTrust.evaluate(row.url, deep: true) }.value
        if let i = rows.firstIndex(where: { $0.url == row.url }) {
            rows[i].report = report
            rows[i].deepChecked = true
        }
        checking.remove(row.url)
    }

    nonisolated static func appURLs() -> [URL] {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        return roots.flatMap { root -> [URL] in
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            let nested = entries.filter { $0.pathExtension.isEmpty }.flatMap { dir in
                ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            }
            return (entries + nested).filter { $0.pathExtension == "app" }
        }
    }
}

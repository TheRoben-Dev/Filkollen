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
            HStack {
                Text(summary).font(.callout).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Toggle("Show all apps", isOn: $showAll).toggleStyle(.switch).controlSize(.small)
                Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 28).padding(.bottom, 12)

            if loading {
                Spacer(); ProgressView("Checking signatures…"); Spacer()
            } else if visible.isEmpty {
                Spacer()
                Label("Every app is signed by Apple, notarized, or from the App Store.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visible) { row in rowView(row) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 16)
                }
            }
            Text("Checked offline. \"Developer ID\" means signed by a registered developer with no notarization ticket attached; that's common and not a problem on its own. Unsigned or broken signatures deserve a closer look.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28).padding(.vertical, 10)
        }
        .task { if rows.isEmpty { await load() } }
    }

    private var summary: String {
        let concerning = rows.filter { $0.report.level.isConcerning }.count
        return concerning == 0 ? "\(rows.count) apps checked" : "\(rows.count) apps checked, \(concerning) unsigned or broken"
    }

    private func rowView(_ row: Row) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.url.path)).resizable().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(.headline).lineLimit(1)
                    Text(row.report.level.label)
                        .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background((row.report.level.isConcerning ? Color.red : row.report.level == .developerID ? .orange : .green).opacity(0.5), in: Capsule())
                    if row.report.quarantined {
                        Text("Never opened").font(.caption2).foregroundStyle(.white.opacity(0.6))
                    }
                    if row.deepChecked { Image(systemName: "checkmark.seal").font(.caption).help("Every file in the app was verified") }
                }
                Text([row.report.signer, row.report.teamID.map { "Team \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            if checking.contains(row.url) {
                ProgressView().controlSize(.small)
            } else if !row.deepChecked {
                Button("Verify All Files") { Task { await deepCheck(row) } }
                    .buttonStyle(GhostButtonStyle())
                    .help("Checks every file in the app against its signature. Slower for big apps.")
            }
            Button { NSWorkspace.shared.activateFileViewerSelecting([row.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder")
        }
        .glassCard(padding: 12)
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

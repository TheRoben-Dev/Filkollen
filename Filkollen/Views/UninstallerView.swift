import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Pick an app (or drop one), see everything it keeps in your home folder,
/// and move it all to the Trash after a review.
struct UninstallerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var apps: [AppUninstaller.App] = []
    @State private var loading = true
    @State private var search = ""
    @State private var chosen: AppUninstaller.App?
    @State private var remnants: [JunkItem] = []
    @State private var deselected: Set<URL> = []
    @State private var refusal: String?
    @State private var showReview = false
    @State private var working = false
    @State private var summary: CleanupSummary?
    @State private var dropTargeted = false
    @State private var previewURL: URL?

    private var filtered: [AppUninstaller.App] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }
    }

    private var selected: [JunkItem] { remnants.filter { !deselected.contains($0.url) } }

    var body: some View {
        HStack(spacing: 0) {
            appList
                .frame(width: 280)
                .background(.black.opacity(0.18))
            Divider().overlay(.white.opacity(0.08))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.white)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            choose(url: url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showReview) {
            if let chosen {
                UninstallReviewSheet(app: chosen, items: selected) { start() }
            }
        }
        .quickLookPreview($previewURL)
        .environment(\.showQuickLook, { previewURL = $0 })
        .task { await loadApps() }
    }

    // MARK: App list

    private var appList: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            if loading {
                Spacer(); ProgressView(); Spacer()
            } else {
                List(filtered, selection: Binding(
                    get: { chosen?.url },
                    set: { url in if let app = apps.first(where: { $0.url == url }) { choose(app) } }
                )) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable().frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text(app.version.map { "Version \($0)" } ?? app.bundleID)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(app.url)
                }
                .scrollContentBackground(.hidden)
            }
            Text("Or drop an app here").font(.caption).foregroundStyle(.white.opacity(0.5)).padding(10)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let summary, let chosen {
            done(summary, app: chosen)
        } else if let chosen {
            VStack(spacing: 0) {
                header(chosen).padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 14)
                if remnants.isEmpty {
                    Spacer()
                    Text(chosen.canTrashBundle ? "Nothing found besides the app." : "No support files found in your home folder.")
                        .foregroundStyle(.white.opacity(0.7))
                    if !chosen.canTrashBundle { finderStep(chosen).padding(.top, 12) }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(remnants) { item in row(item) }
                        }
                        .glassCard(padding: 14)
                        .padding(.horizontal, 28).padding(.bottom, 16)
                        if !chosen.canTrashBundle {
                            finderNote.padding(.horizontal, 28).padding(.bottom, 16)
                        }
                    }
                    footer
                }
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                GradientIcon(symbol: "xmark.app.fill", gradient: Theme.gradient(.orange, .pink), size: 90)
                Text("App Uninstaller").font(.title2.weight(.semibold))
                Text(refusal ?? "Choose an app on the left, or drop one here, to see everything it keeps on your Mac.")
                    .foregroundStyle(refusal == nil ? .white.opacity(0.65) : .orange)
                    .multilineTextAlignment(.center).frame(maxWidth: 420)
                Spacer()
            }
        }
    }

    private func header(_ app: AppUninstaller.App) -> some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.system(size: 26, weight: .bold, design: .rounded))
                Text([app.bundleID, app.version].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(remnants.reduce(0) { $0 + $1.size }.formattedBytes).font(.title.weight(.bold).monospacedDigit())
                Text("\(remnants.count) items").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func row(_ item: JunkItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !deselected.contains(item.url) },
                set: { if $0 { deselected.remove(item.url) } else { deselected.insert(item.url) } }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Remove \(item.name)")
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                Text(item.detail).font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(item.size.formattedBytes).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            Button { previewURL = item.url } label: { Image(systemName: "eye") }
                .buttonStyle(.plain).help("Quick Look").accessibilityLabel("Quick Look \(item.name)")
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show \(item.name) in Finder")
        }
        .contextMenu { ItemContextMenu(item: item) }
    }

    private var finderNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The app itself is in a system folder", systemImage: "info.circle").font(.headline)
            Text("Filkollen only removes files in your home folder. After the support files are gone, drag the app to the Trash in Finder; macOS asks for your password if it needs to.")
                .font(.callout).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 14)
    }

    private func finderStep(_ app: AppUninstaller.App) -> some View {
        Button("Show \(app.name) in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            .buttonStyle(GhostButtonStyle())
    }

    private var footer: some View {
        HStack {
            if RunningApps.isRunning(chosen?.bundleID ?? "") {
                Label("Quit \(chosen?.name ?? "the app") first", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("\(selected.count) selected").foregroundStyle(.white.opacity(0.6))
            Button("Review & Uninstall \(selected.reduce(0) { $0 + $1.size }.formattedBytes)") { showReview = true }
                .buttonStyle(PillButtonStyle())
                .disabled(selected.isEmpty || working)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private func done(_ summary: CleanupSummary, app: AppUninstaller.App) -> some View {
        VStack(spacing: 14) {
            Spacer()
            GradientIcon(symbol: "checkmark", gradient: Theme.safe, size: 80)
            Text("Moved \(summary.trashedCount) items to the Trash").font(.title2.weight(.semibold))
            Text(reclaimNote(selected: summary.trashedBytes, reclaimable: summary.reclaimableBytes))
                .font(.callout).foregroundStyle(.white.opacity(0.65))
            if !summary.failures.isEmpty {
                FailureList(failures: summary.failures).frame(maxWidth: 520)
            }
            if !app.canTrashBundle, FileManager.default.fileExists(atPath: app.url.path) {
                Text("Last step: drag \(app.name) to the Trash.").foregroundStyle(.white.opacity(0.8))
                finderStep(app)
            }
            Button("Done") { reset(); Task { await loadApps() } }.buttonStyle(PillButtonStyle())
            Spacer()
        }
        .padding(28)
    }

    // MARK: Actions

    private func loadApps() async {
        loading = true
        apps = await Task.detached(priority: .userInitiated) { AppUninstaller().installedApps() }.value
        loading = false
    }

    private func choose(url: URL) {
        do {
            choose(try AppUninstaller().app(at: url))
        } catch {
            reset()
            refusal = (error as? LocalizedError)?.errorDescription ?? "That app can't be uninstalled here."
        }
    }

    private func choose(_ app: AppUninstaller.App) {
        reset()
        chosen = app
        Task {
            let found = await Task.detached(priority: .userInitiated) {
                AppModel.screened(AppUninstaller().remnants(of: app), category: .appLeftovers)
            }.value
            if chosen == app { remnants = found }
        }
    }

    private func start() {
        let items = selected
        working = true
        Task {
            summary = await model.uninstall(items, appName: chosen?.name ?? "an app")
            working = false
        }
    }

    private func reset() {
        chosen = nil
        remnants = []
        deselected = []
        refusal = nil
        summary = nil
    }
}

/// Last look before an app's files go to the Trash.
private struct UninstallReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppUninstaller.App
    let items: [JunkItem]
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                GradientIcon(symbol: "trash.fill", gradient: Theme.accent, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(app.name)?").font(.title2.bold())
                    Text("\(items.count) items, \(items.reduce(0) { $0 + $1.size }.formattedBytes), will be moved to the Trash. You can put anything back from there.")
                        .foregroundStyle(.secondary)
                    Text(reclaimNote(selected: items.reduce(0) { $0 + $1.size }, reclaimable: items.reduce(0) { $0 + $1.reclaimableSize }))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            List(items) { item in
                HStack {
                    Text(item.url.abbreviatedPath).lineLimit(1).truncationMode(.middle).font(.callout.monospaced())
                    Spacer()
                    Text(item.size.formattedBytes).foregroundStyle(.secondary).font(.caption)
                }
            }
            .frame(minHeight: 220)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Move to Trash") { confirm(); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 620, height: 480)
    }
}

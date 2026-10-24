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
                .frame(width: DS.Layout.inspectorWidth)
                .background(DS.Color.backgroundUnderPage)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            choose(url: url)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                DS.shape(DS.Radius.hero)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .background(Color.accentColor.opacity(0.06), in: DS.shape(DS.Radius.hero))
                    .padding(DS.Space.md)
                    .allowsHitTesting(false)
                    .dsTransition(.opacity)
            }
        }
        .dsAnimation(.snappy, value: dropTargeted)
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
                .padding(DS.Space.md)
            if loading {
                VStack(spacing: DS.Space.xs) {
                    ForEach(0..<8, id: \.self) { _ in DSPlaceholderRow() }
                }
                .padding(.horizontal, DS.Space.sm)
                Spacer(minLength: 0)
            } else {
                List(filtered, selection: Binding(
                    get: { chosen?.url },
                    set: { url in if let app = apps.first(where: { $0.url == url }) { choose(app) } }
                )) { app in
                    HStack(spacing: DS.Space.sm) {
                        DSFileIcon(url: app.url, size: 26)
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text(app.name).font(DS.Font.body).lineLimit(1)
                            Text(app.version.map { String(localized: "Version \($0)") } ?? app.bundleID)
                                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                        }
                    }
                    .tag(app.url)
                }
                .scrollContentBackground(.hidden)
            }
            Label("Or drop an app here", systemImage: "arrow.down.app")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                .padding(DS.Space.sm)
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let summary, let chosen {
            done(summary, app: chosen)
        } else if let chosen {
            VStack(spacing: 0) {
                header(chosen).padding(DS.Inset.page)
                if remnants.isEmpty {
                    DSEmptyState(symbol: "sparkles", tint: DS.Color.success,
                                 title: chosen.canTrashBundle ? String(localized: "Nothing found besides the app.")
                                                              : String(localized: "No support files found in your home folder.")) {
                        if !chosen.canTrashBundle { finderStep(chosen) }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(remnants) { item in row(item) }
                        }
                        .padding(DS.Space.xs)
                        .dsElevation()
                        .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
                        if !chosen.canTrashBundle {
                            finderNote.padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
                        }
                    }
                    footer
                }
            }
        } else if let refusal {
            DSEmptyState(symbol: "xmark.app", badge: "exclamationmark.circle.fill", tint: DS.Color.warning,
                         title: String(localized: "That app can't be uninstalled here"), message: refusal)
        } else {
            DSEmptyState(symbol: "xmark.app", tint: DS.Color.textTertiary,
                         title: String(localized: "App Uninstaller"),
                         message: String(localized: "Choose an app on the left, or drop one here, to see everything it keeps on your Mac."))
        }
    }

    private func header(_ app: AppUninstaller.App) -> some View {
        HStack(spacing: DS.Space.lg) {
            DSFileIcon(url: app.url, size: DS.Icon.TileSize.large.side)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(app.name).font(DS.Font.title).foregroundStyle(DS.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text([app.bundleID, app.version].compactMap { $0 }.joined(separator: " · "))
                    .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                DSByteCount(remnants.reduce(0) { $0 + $1.size }, font: DS.Font.numericLarge)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(DS.itemCount(remnants.count)).font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
            }
        }
    }

    private func row(_ item: JunkItem) -> some View {
        DSFileRow(item: item,
                  isSelected: Binding(
                      get: { !deselected.contains(item.url) },
                      set: { if $0 { deselected.remove(item.url) } else { deselected.insert(item.url) } }
                  ),
                  showsPath: false,
                  quickLook: { previewURL = $0 })
            .contextMenu { ItemContextMenu(item: item) }
    }

    private var finderNote: some View {
        DSBanner(.info, title: String(localized: "The app itself is in a system folder"),
                 message: String(localized: "Filkollen only removes files in your home folder. After the support files are gone, drag the app to the Trash in Finder; macOS asks for your password if it needs to."))
    }

    private func finderStep(_ app: AppUninstaller.App) -> some View {
        Button(String(localized: "Show \(app.name) in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            .buttonStyle(.dsSecondary)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if RunningApps.isRunning(chosen?.bundleID ?? "") {
                Label(String(localized: "Quit \(chosen?.name ?? String(localized: "the app")) first"), systemImage: DS.Icon.warning)
                    .font(DS.Font.callout)
                    .foregroundStyle(DS.Color.warning)
            }
            Spacer()
            Text(String(localized: "\(selected.count) selected"))
                .font(DS.Font.numericCallout).foregroundStyle(DS.Color.textSecondary)
            Button(String(localized: "Review & Uninstall \(selected.reduce(0) { $0 + $1.size }.formattedBytes)…")) { showReview = true }
                .buttonStyle(.dsPrimary)
                .disabled(selected.isEmpty || working)
        }
        .padding(DS.Inset.bar)
        .background(DS.Color.backgroundWindow)
        .overlay(alignment: .top) { Divider() }
    }

    private func done(_ summary: CleanupSummary, app: AppUninstaller.App) -> some View {
        VStack(spacing: DS.Space.lg) {
            Spacer(minLength: 0)
            DSEmptyState(symbol: "checkmark.circle.fill", tint: DS.Color.success,
                         title: String(localized: "Moved \(summary.trashedCount) items to the Trash"),
                         message: reclaimNote(selected: summary.trashedBytes, reclaimable: summary.reclaimableBytes))
                .fixedSize(horizontal: false, vertical: true)
            if !summary.failures.isEmpty {
                FailureList(failures: summary.failures).frame(maxWidth: DS.Layout.readableWidth)
            }
            if !app.canTrashBundle, FileManager.default.fileExists(atPath: app.url.path) {
                Text(String(localized: "Last step: drag \(app.name) to the Trash."))
                    .font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                finderStep(app)
            }
            Button("Done") { reset(); Task { await loadApps() } }
                .buttonStyle(.dsPrimary)
                .keyboardShortcut(.defaultAction)
            Spacer(minLength: 0)
        }
        .padding(DS.Inset.page)
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

/// Last look before an app's files go to the Trash. Same badges as the list it came from.
private struct UninstallReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppUninstaller.App
    let items: [JunkItem]
    let confirm: () -> Void

    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                DSFileIcon(url: app.url, size: DS.Icon.TileSize.large.side)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(String(localized: "Uninstall \(app.name)?")).font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: "\(items.count) items, \(total.formattedBytes), will be moved to the Trash. You can put anything back from there."))
                        .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reclaimNote(selected: total, reclaimable: items.reduce(0) { $0 + $1.reclaimableSize }))
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.Inset.sheet)
            Divider()
            List(items) { item in
                HStack(spacing: DS.Space.md) {
                    DSFileIcon(url: item.url)
                    Text(item.url.abbreviatedPath).dsPath(DS.Font.pathBody)
                    if item.inUseBy != nil { DSBadge(.inUse(item.inUseBy)) }
                    if item.confidence == .low { DSBadge(.lowConfidence) }
                    Spacer()
                    Text(item.size.formattedBytes).font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .listStyle(.inset)
            .frame(minHeight: 220)
            HStack(spacing: DS.Space.md) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.dsSecondary)
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") { confirm(); dismiss() }
                    .buttonStyle(.dsPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Inset.bar)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 640, height: 500)
    }
}

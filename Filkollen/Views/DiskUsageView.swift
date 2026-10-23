import SwiftUI

/// A map of what takes space in your home folder. Look only: to remove
/// something, reveal it in Finder or use a cleanup page.
struct DiskUsageView: View {
    @State private var path: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @State private var entries: [DiskUsage.Entry] = []
    @State private var loading = false
    @State private var hovered: URL?
    @State private var task: Task<Void, Never>?

    private var current: URL { path.last! }
    /// Small items are folded into one "Other" tile so the map stays readable.
    private var shown: [DiskUsage.Entry] { Array(entries.prefix(40)) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSPageHeader(title: String(localized: "Disk Usage"),
                         subtitle: String(localized: "What takes up space in your home folder"),
                         tile: DSTile(symbol: AppModel.SystemPage.diskUsage.symbol, tint: DS.Color.brand, size: .large)) {
                Button { load() } label: { Label("Refresh", systemImage: DS.Icon.refresh) }
                    .buttonStyle(.dsSecondary)
                    .disabled(loading)
            }
            breadcrumbs
            ZStack {
                if loading && entries.isEmpty {
                    DS.shape(DS.Radius.card).fill(DS.Color.surfaceSunken)
                        .dsShimmer()
                        .overlay {
                            Text(String(localized: "Measuring \(current.lastPathComponent)…"))
                                .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        }
                } else if entries.isEmpty {
                    DSEmptyState(symbol: "folder", tint: DS.Color.textTertiary,
                                 title: String(localized: "Nothing to show"),
                                 message: String(localized: "Empty, or Filkollen can't read this folder."))
                } else {
                    map
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(footer).font(DS.Font.path).foregroundStyle(DS.Color.textSecondary).lineLimit(1).truncationMode(.middle)
        }
        .padding(DS.Inset.page)
        .onAppear { if entries.isEmpty { load() } }
        .onDisappear { task?.cancel() }
    }

    private var footer: String {
        if let hovered, let e = entries.first(where: { $0.url == hovered }) {
            return "\(e.url.abbreviatedPath) · \(e.size.formattedBytes)" + (e.isFolder ? String(localized: " · click to open") : "")
        }
        let total = entries.reduce(0) { $0 + $1.size }
        return String(localized: "\(current.abbreviatedPath) · \(total.formattedBytes) in \(entries.count) items")
    }

    private var breadcrumbs: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(path.enumerated()), id: \.offset) { i, url in
                if i > 0 {
                    Image(systemName: "chevron.right").font(DS.Font.badge).foregroundStyle(DS.Color.textTertiary)
                        .accessibilityHidden(true)
                }
                Button(i == 0 ? String(localized: "Home") : url.lastPathComponent) {
                    path = Array(path.prefix(i + 1)); load()
                }
                .buttonStyle(.dsPlain)
                .font(DS.Font.callout.weight(i == path.count - 1 ? .semibold : .regular))
                .foregroundStyle(i == path.count - 1 ? DS.Color.textPrimary : Color.accentColor)
                .disabled(i == path.count - 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Path"))
    }

    private var map: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(shown.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, entry in
                    tile(entry, rect: rects[i], index: i)
                }
            }
        }
    }

    /// Calm, tested tints (white text ≥ 4:1) instead of a rainbow; files are a step quieter than folders.
    private static let palette: [Color] = JunkCategory.allCases.map(\.dsTint)

    private func tile(_ entry: DiskUsage.Entry, rect: CGRect, index: Int) -> some View {
        let isHovered = hovered == entry.url
        return DS.shape(DS.Radius.small)
            .fill(Self.palette[index % Self.palette.count].opacity(entry.isFolder ? 1 : 0.75))
            .overlay(DS.shape(DS.Radius.small).fill(.white.opacity(isHovered ? 0.16 : 0)))
            .overlay(DS.shape(DS.Radius.small).strokeBorder(.white.opacity(isHovered ? 0.6 : 0), lineWidth: 1.5))
            .overlay(alignment: .topLeading) {
                if rect.width > 70 && rect.height > 34 {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Image(systemName: entry.isFolder ? "folder.fill" : "doc.fill").font(DS.Font.badge)
                            Text(entry.name).font(DS.Font.captionEmphasized).lineLimit(1)
                        }
                        Text(entry.size.formattedBytes).font(DS.Font.numericCaption).opacity(0.85)
                    }
                    .foregroundStyle(DS.Color.textOnFill)
                    .padding(6)
                }
            }
            .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
            .offset(x: rect.minX, y: rect.minY)
            .onHover { hovered = $0 ? entry.url : (hovered == entry.url ? nil : hovered) }
            .dsAnimation(.snappy, value: isHovered)
            .onTapGesture { if entry.isFolder { path.append(entry.url); load() } }
            .contextMenu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                if entry.isFolder { Button("Open") { path.append(entry.url); load() } }
            }
            .accessibilityElement()
            .accessibilityLabel("\(entry.name), \(entry.size.formattedBytes)")
            .accessibilityAddTraits(entry.isFolder ? .isButton : [])
            .accessibilityAction { if entry.isFolder { path.append(entry.url); load() } }
    }

    private func load() {
        task?.cancel()
        let folder = current
        loading = true
        entries = []
        task = Task {
            let found = await Task.detached(priority: .userInitiated) { DiskUsage.children(of: folder) }.value
            guard !Task.isCancelled, folder == current else { return }
            entries = found
            loading = false
        }
    }
}

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                GradientIcon(symbol: "square.grid.3x3.square", gradient: Theme.gradient(.blue, .purple), size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disk Usage").font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("What takes up space in your home folder").foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
                Button { load() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(GhostButtonStyle())
            }
            breadcrumbs
            ZStack {
                if loading && entries.isEmpty {
                    ProgressView("Measuring \(current.lastPathComponent)…")
                } else if entries.isEmpty {
                    Text("Empty, or Filkollen can't read this folder.").foregroundStyle(.white.opacity(0.6))
                } else {
                    map
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(footer).font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1).truncationMode(.middle)
        }
        .padding(28)
        .foregroundStyle(.white)
        .onAppear { if entries.isEmpty { load() } }
        .onDisappear { task?.cancel() }
    }

    private var footer: String {
        if let hovered, let e = entries.first(where: { $0.url == hovered }) {
            return "\(e.url.abbreviatedPath) · \(e.size.formattedBytes)" + (e.isFolder ? " · click to open" : "")
        }
        let total = entries.reduce(0) { $0 + $1.size }
        return "\(current.abbreviatedPath) · \(total.formattedBytes) in \(entries.count) items"
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(path.enumerated()), id: \.offset) { i, url in
                if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.white.opacity(0.4)) }
                Button(i == 0 ? "Home" : url.lastPathComponent) {
                    path = Array(path.prefix(i + 1)); load()
                }
                .buttonStyle(.plain)
                .font(.callout.weight(i == path.count - 1 ? .semibold : .regular))
                .disabled(i == path.count - 1)
            }
        }
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

    private func tile(_ entry: DiskUsage.Entry, rect: CGRect, index: Int) -> some View {
        let hue = Double(index % 12) / 12.0
        return RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hue: hue, saturation: 0.55, brightness: hovered == entry.url ? 0.85 : 0.65).opacity(entry.isFolder ? 0.9 : 0.6))
            .overlay(alignment: .topLeading) {
                if rect.width > 70 && rect.height > 34 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.caption.weight(.semibold)).lineLimit(1)
                        Text(entry.size.formattedBytes).font(.caption2).opacity(0.8)
                    }
                    .padding(6)
                }
            }
            .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
            .offset(x: rect.minX, y: rect.minY)
            .onHover { hovered = $0 ? entry.url : (hovered == entry.url ? nil : hovered) }
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

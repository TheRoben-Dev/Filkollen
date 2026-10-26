import QuickLook
import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let category: JunkCategory
    @State private var showReview = false
    @State private var expanded: Set<String> = []
    @State private var previewURL: URL?

    private var result: CategoryResult? { model.result(for: category) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(DS.Inset.page)

            if model.scanningCategories.contains(category) || (model.isScanning && result == nil) {
                scanning
            } else if let result, !result.items.isEmpty {
                list(result)
                footer(result)
            } else if result != nil {
                empty
            } else {
                notScanned
            }
        }
        .sheet(isPresented: $showReview) { ReviewSheet(only: category).environmentObject(model) }
        .quickLookPreview($previewURL)
        .environment(\.showQuickLook, { previewURL = $0 })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSPageHeader(title: category.title, subtitle: category.subtitle, tile: DSTile(category, size: .large)) {
                if let result {
                    VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                        DSByteCount(result.totalSize, font: DS.Font.numericLarge)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(DS.itemCount(result.items.count))
                            .font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            HStack(spacing: DS.Space.xs) {
                Circle().fill(category.dsTint).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(category.family.title).font(DS.Font.captionEmphasized).foregroundStyle(DS.Color.textPrimary)
                Text(category.family.explanation).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: List

    private func groups(_ result: CategoryResult) -> [(key: String, items: [JunkItem])] {
        var order: [String] = []
        var map: [String: [JunkItem]] = [:]
        for item in result.items {
            if map[item.group] == nil { order.append(item.group) }
            map[item.group, default: []].append(item)
        }
        return order.map { ($0, map[$0]!) }
            .sorted { $0.items.reduce(0) { $0 + $1.size } > $1.items.reduce(0) { $0 + $1.size } }
    }

    private func list(_ result: CategoryResult) -> some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.sm) {
                ForEach(groups(result), id: \.key) { group in
                    GroupCard(
                        category: category,
                        title: groupTitle(group.key, items: group.items),
                        items: group.items,
                        isExpanded: Binding(
                            get: { expanded.contains(group.key) || category.isDuplicates },
                            set: { if $0 { expanded.insert(group.key) } else { expanded.remove(group.key) } }
                        )
                    )
                }
            }
            .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
        }
    }

    private func groupTitle(_ key: String, items: [JunkItem]) -> String {
        switch category {
        case .duplicatePhotos, .duplicateFiles: return items.first(where: \.isKeeper)?.name ?? key
        case .appLeftovers, .systemJunk, .largeFiles, .developerJunk, .oldInstallers, .iosBackups, .browserCaches: return key
        }
    }

    /// Solid bar with a top separator; no blur behind the scrolling list.
    private func footer(_ result: CategoryResult) -> some View {
        HStack(spacing: DS.Space.md) {
            Button("Select All") { model.setAllSelected(true, in: category) }
                .buttonStyle(.dsSecondary)
            Button("Select None") { model.setAllSelected(false, in: category) }
                .buttonStyle(.dsSecondary)
            Spacer()
            Text(String(localized: "\(result.selectedItems.count) selected"))
                .font(DS.Font.numericCallout)
                .foregroundStyle(DS.Color.textSecondary)
            Button(String(localized: "Review \(result.selectedSize.formattedBytes)…")) { showReview = true }
                .buttonStyle(.dsPrimary)
                .disabled(result.selectedSize == 0 || model.phase == .cleaning)
        }
        .padding(DS.Inset.bar)
        .background(DS.Color.backgroundWindow)
        .overlay(alignment: .top) { Divider() }
    }

    private var scanning: some View {
        VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)
            DSScanRing(segments: DSScanSegment.segments(for: [category], scanning: model.scanningCategories,
                                                        finished: Set(model.results.keys)),
                       isWorking: true, settled: false, diameter: 120, lineWidth: 8) {
                Image(systemName: category.dsSymbol)
                    .font(.system(size: 30, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Color.brand)
                    .accessibilityHidden(true)
            }
            Text(category.scanningMessage).font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
            Text(model.scanStatus).dsPath(DS.Font.pathBody).frame(maxWidth: DS.Layout.readableWidth)
            Spacer(minLength: 0)
        }
        .padding(DS.Inset.page)
        .frame(maxWidth: .infinity)
    }

    private var empty: some View {
        DSEmptyState(symbol: "sparkles", badge: "checkmark.circle.fill", tint: DS.Color.success,
                     title: String(localized: "Nothing to clean here"),
                     message: String(localized: "Filkollen didn't find anything in \(category.title) worth removing.")) {
            Button("Scan Again") { model.scan([category]) }
                .buttonStyle(.dsSecondary)
                .disabled(model.isScanning)
        }
    }

    private var notScanned: some View {
        DSEmptyState(symbol: category.dsSymbol, tint: category.dsTint,
                     title: String(localized: "Not scanned yet"),
                     message: category.family.explanation) {
            Button(String(localized: "Scan \(category.title)")) { model.scan([category]) }
                .buttonStyle(.ds(.primary, size: .large))
                .disabled(model.isScanning)
        }
    }
}

private struct GroupCard: View {
    @EnvironmentObject private var model: AppModel
    let category: JunkCategory
    let title: String
    let items: [JunkItem]
    @Binding var isExpanded: Bool

    @Environment(\.showQuickLook) private var showQuickLook
    @State private var hovering = false

    /// Items a group checkbox selects: never the kept duplicate or something in use.
    private var selectable: [JunkItem] { items.filter { !$0.isKeeper && $0.inUseBy == nil && $0.confidence != .low } }
    private var allSelected: Bool { !selectable.isEmpty && selectable.allSatisfy(\.isSelected) }
    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { v in
                        for i in items where !i.isKeeper && (!v || (i.inUseBy == nil && i.confidence != .low)) {
                            model.setSelected(v, item: i.id, in: category)
                        }
                    }
                ))
                .toggleStyle(.checkbox).labelsHidden()
                .accessibilityLabel(String(localized: "Select all in \(title)"))

                if category == .duplicatePhotos, let first = items.first {
                    DSFileIcon(url: first.url, size: 40, thumbnail: true)
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
                }
                Spacer()
                if items.contains(where: { $0.inUseBy != nil }) { DSBadge(.inUse(nil)) }
                if items.contains(where: { $0.confidence == .low }) { DSBadge(.lowConfidence) }
                Text(total.formattedBytes)
                    .font(DS.Font.numericCallout.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
                if !category.isDuplicates {
                    Button {
                        withMotion(.smooth) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(DS.Font.captionEmphasized)
                            .foregroundStyle(DS.Color.textSecondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .frame(width: DS.Layout.minHitTarget, height: DS.Layout.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isExpanded ? String(localized: "Hide items in \(title)")
                                                   : String(localized: "Show items in \(title)"))
                }
            }
            .padding(DS.Inset.row)

            if isExpanded {
                Divider().padding(.horizontal, DS.Space.md)
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        DSFileRow(item: item,
                                  isSelected: Binding(get: { item.isSelected },
                                                      set: { model.setSelected($0, item: item.id, in: item.category) }),
                                  showsThumbnail: item.category == .duplicatePhotos,
                                  showsPath: false,
                                  quickLook: { showQuickLook($0) })
                            .padding(.leading, DS.Space.xxl)
                            .opacity(item.confidence == .low ? 0.8 : 1)
                            .contextMenu { ItemContextMenu(item: item) }
                    }
                }
                .padding(.vertical, DS.Space.xs)
                .dsTransition(.dsRise)
            }
        }
        .dsElevation(hovering ? .raised : .surface)
        .onHover { hovering = $0 }
        .dsAnimation(.snappy, value: hovering)
    }

    private var subtitle: String {
        switch category {
        case .duplicatePhotos, .duplicateFiles: return String(localized: "\(items.count) identical copies")
        case .appLeftovers:
            return Set(items.map(\.detail)).sorted().joined(separator: ", ")
        case .developerJunk:
            return items.count == 1 ? items[0].detail : String(localized: "\(items.count) items · \(items[0].detail)")
        case .systemJunk, .largeFiles, .oldInstallers, .iosBackups, .browserCaches: return DS.itemCount(items.count)
        }
    }
}

/// Right-click actions shared by item rows.
struct ItemContextMenu: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.showQuickLook) private var showQuickLook
    let item: JunkItem

    var body: some View {
        Button("Quick Look") { showQuickLook(item.url) }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Divider()
        Button("Always Ignore This Item") { model.alwaysIgnore(item.url) }
        Button("Always Ignore Its Folder") { model.alwaysIgnore(item.url.deletingLastPathComponent()) }
    }
}

private struct ShowQuickLookKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (URL) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Opens the Quick Look panel for a file; set by the page that hosts `.quickLookPreview`.
    var showQuickLook: @MainActor @Sendable (URL) -> Void {
        get { self[ShowQuickLookKey.self] }
        set { self[ShowQuickLookKey.self] = newValue }
    }
}

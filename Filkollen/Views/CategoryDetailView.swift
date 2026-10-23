import SwiftUI

struct CategoryDetailView: View {
    @EnvironmentObject private var model: AppModel
    let category: JunkCategory
    @State private var showReview = false
    @State private var expanded: Set<String> = []

    private var result: CategoryResult? { model.result(for: category) }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 18)

            if model.isScanning && result == nil {
                Spacer()
                ScanningRing(size: 120)
                Text(model.scanStatus).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle).padding(.top, 16).frame(maxWidth: 480)
                Spacer()
            } else if let result, !result.items.isEmpty {
                list(result)
                footer(result)
            } else if result != nil {
                empty
            } else {
                notScanned
            }
        }
        .foregroundStyle(.white)
        .sheet(isPresented: $showReview) { ReviewSheet(only: category).environmentObject(model) }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GradientIcon(category, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title).font(.system(size: 26, weight: .bold, design: .rounded))
                Text(category.subtitle).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            if let result {
                VStack(alignment: .trailing) {
                    Text(result.totalSize.formattedBytes)
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("\(result.items.count) items").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
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
            LazyVStack(spacing: 10) {
                ForEach(groups(result), id: \.key) { group in
                    GroupCard(
                        category: category,
                        title: groupTitle(group.key, items: group.items),
                        items: group.items,
                        isExpanded: Binding(
                            get: { expanded.contains(group.key) || category == .duplicatePhotos },
                            set: { if $0 { expanded.insert(group.key) } else { expanded.remove(group.key) } }
                        )
                    )
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 16)
        }
    }

    private func groupTitle(_ key: String, items: [JunkItem]) -> String {
        switch category {
        case .duplicatePhotos: return items.first(where: \.isKeeper)?.name ?? key
        case .appLeftovers, .systemJunk, .largeFiles, .developerJunk, .oldInstallers: return key
        }
    }

    private func footer(_ result: CategoryResult) -> some View {
        HStack {
            Button("Select All") { model.setAllSelected(true, in: category) }
                .buttonStyle(GhostButtonStyle())
            Button("Select None") { model.setAllSelected(false, in: category) }
                .buttonStyle(GhostButtonStyle())
            Spacer()
            Text("\(result.selectedItems.count) selected")
                .foregroundStyle(.white.opacity(0.6))
            Button("Review & Clean \(result.selectedSize.formattedBytes)") { showReview = true }
                .buttonStyle(PillButtonStyle())
                .disabled(result.selectedSize == 0 || model.phase == .cleaning)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            GradientIcon(symbol: "checkmark", gradient: Theme.safe, size: 80)
            Text("Nothing to clean here").font(.title2.weight(.semibold))
            Button("Scan Again") { model.scan([category]) }.buttonStyle(GhostButtonStyle())
            Spacer()
        }
    }

    private var notScanned: some View {
        VStack(spacing: 18) {
            Spacer()
            GradientIcon(category, size: 90)
            Text("Not scanned yet").font(.title2.weight(.semibold))
            Button("Scan \(category.title)") { model.scan([category]) }
                .buttonStyle(PillButtonStyle(large: true))
                .disabled(model.isScanning)
            Spacer()
        }
    }
}

private struct GroupCard: View {
    @EnvironmentObject private var model: AppModel
    let category: JunkCategory
    let title: String
    let items: [JunkItem]
    @Binding var isExpanded: Bool

    /// Items a group checkbox selects: never the kept duplicate or something in use.
    private var selectable: [JunkItem] { items.filter { !$0.isKeeper && $0.inUseBy == nil } }
    private var allSelected: Bool { !selectable.isEmpty && selectable.allSatisfy(\.isSelected) }
    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(
                    get: { allSelected },
                    set: { v in
                        for i in items where !i.isKeeper && (!v || i.inUseBy == nil) {
                            model.setSelected(v, item: i.id, in: category)
                        }
                    }
                ))
                .toggleStyle(.checkbox).labelsHidden()

                if category == .duplicatePhotos, let first = items.first {
                    Thumbnail(url: first.url, size: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text(total.formattedBytes).font(.callout.weight(.semibold).monospacedDigit())
                if category != .duplicatePhotos {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded {
                Divider().overlay(.white.opacity(0.1))
                ForEach(items) { item in ItemRow(item: item) }
            }
        }
        .glassCard(padding: 14)
    }

    private var subtitle: String {
        switch category {
        case .duplicatePhotos: return "\(items.count) identical copies"
        case .appLeftovers:
            return Set(items.map(\.detail)).sorted().joined(separator: ", ")
        case .developerJunk:
            return items.count == 1 ? items[0].detail : "\(items.count) items · \(items[0].detail)"
        case .systemJunk, .largeFiles, .oldInstallers: return "\(items.count) items"
        }
    }
}

private struct ItemRow: View {
    @EnvironmentObject private var model: AppModel
    let item: JunkItem

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { model.setSelected($0, item: item.id, in: item.category) }
            ))
            .toggleStyle(.checkbox).labelsHidden()

            if item.category == .duplicatePhotos {
                Thumbnail(url: item.url, size: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                    if item.isKeeper {
                        Text("KEEP")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.safe, in: Capsule())
                    }
                    if item.inUseBy != nil {
                        Text("IN USE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(.orange, in: Capsule())
                            .accessibilityLabel("In use by \(item.inUseBy ?? "a running app")")
                    }
                }
                Text(item.detail).font(.caption).foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(item.size.formattedBytes).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
        .padding(.leading, 26)
    }
}

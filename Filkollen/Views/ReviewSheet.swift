import QuickLook
import SwiftUI

/// Final confirmation before anything is moved to the Trash. Lists what was
/// selected when it opened; unticking an item here deselects it, and the
/// totals follow.
struct ReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Limit cleaning to one category (from a detail page); nil means everything selected.
    var only: JunkCategory? = nil

    enum Sort: String, CaseIterable { case size = "Size", name = "Name", location = "Location" }

    @State private var reviewed: [JunkCategory: [JunkItem]] = [:]
    @State private var search = ""
    @State private var sort = Sort.size
    @State private var previewURL: URL?

    private var categories: [JunkCategory] { only.map { [$0] } ?? JunkCategory.smartScan }

    /// Live selection, limited to what this sheet showed.
    private var items: [JunkItem] {
        categories.flatMap { category -> [JunkItem] in
            let shown = Set((reviewed[category] ?? []).map(\.id))
            return (model.result(for: category)?.selectedItems ?? []).filter { shown.contains($0.id) }
        }
    }

    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                GradientIcon(symbol: "trash.fill", gradient: Theme.accent, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to clean").font(.title2.bold())
                    Text("\(items.count) items, \(total.formattedBytes), will be moved to the Trash. You can put anything back from there or from History.")
                        .foregroundStyle(.secondary)
                    Text(reclaimNote(selected: total, reclaimable: items.reduce(0) { $0 + $1.reclaimableSize }))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                TextField("Filter by name or folder", text: $search).textFieldStyle(.roundedBorder)
                Picker("Sort", selection: $sort) {
                    ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).frame(width: 230)
            }

            List {
                ForEach(categories) { category in
                    let shown = visible(in: category)
                    if !shown.isEmpty {
                        Section {
                            ForEach(shown.prefix(500)) { item in row(item) }
                            if shown.count > 500 {
                                Text("…and \(shown.count - 500) more").foregroundStyle(.secondary)
                            }
                        } header: {
                            HStack {
                                Label(category.title, systemImage: category.symbol)
                                Spacer()
                                Button("Untick All") {
                                    for item in shown { model.setSelected(false, item: item.id, in: category) }
                                }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move \(items.count) Items to Trash") {
                    model.section = .smartScan
                    model.cleanSelected(in: categories)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PillButtonStyle())
                .disabled(items.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 680, height: 580)
        .quickLookPreview($previewURL)
        .onAppear {
            reviewed = Dictionary(uniqueKeysWithValues: categories.map { ($0, model.result(for: $0)?.selectedItems ?? []) })
        }
    }

    private func visible(in category: JunkCategory) -> [JunkItem] {
        let live = Dictionary(uniqueKeysWithValues: (model.result(for: category)?.items ?? []).map { ($0.id, $0) })
        var list = (reviewed[category] ?? []).compactMap { live[$0.id] }
        if !search.isEmpty {
            list = list.filter { $0.url.path.localizedCaseInsensitiveContains(search) || $0.detail.localizedCaseInsensitiveContains(search) }
        }
        switch sort {
        case .size: list.sort { $0.size > $1.size }
        case .name: list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .location: list.sort { $0.url.path < $1.url.path }
        }
        return list
    }

    private func row(_ item: JunkItem) -> some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { item.isSelected },
                set: { model.setSelected($0, item: item.id, in: item.category) }
            ))
            .toggleStyle(.checkbox).labelsHidden()
            .accessibilityLabel("Clean \(item.name)")
            Text(item.url.abbreviatedPath)
                .lineLimit(1).truncationMode(.middle)
                .font(.callout.monospaced())
                .foregroundStyle(item.isSelected ? .primary : .secondary)
            Spacer()
            Text(item.size.formattedBytes).foregroundStyle(.secondary).font(.caption)
            Button { previewURL = item.url } label: { Image(systemName: "eye") }
                .buttonStyle(.plain).help("Quick Look").accessibilityLabel("Quick Look \(item.name)")
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder").accessibilityLabel("Show \(item.name) in Finder")
        }
    }
}

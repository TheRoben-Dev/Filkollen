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
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                HStack(alignment: .top, spacing: DS.Space.lg) {
                    DSTile(symbol: "trash.fill", tint: DS.Color.brand, size: .large)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text("Ready to clean").font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(items.count) items, \(total.formattedBytes), will be moved to the Trash. You can put anything back from there or from History.")
                            .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(reclaimNote(selected: total, reclaimable: items.reduce(0) { $0 + $1.reclaimableSize }))
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    DSByteCount(total, font: DS.Font.numericLarge)
                        .foregroundStyle(DS.Color.textPrimary)
                }

                HStack(spacing: DS.Space.md) {
                    TextField("Filter by name or folder", text: $search).textFieldStyle(.roundedBorder)
                    Picker("Sort", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240)
                }
            }
            .padding(DS.Inset.sheet)

            Divider()

            // Every selected item, virtualised; no cap, same badges as the category page.
            List {
                ForEach(categories) { category in
                    let shown = visible(in: category)
                    if !shown.isEmpty {
                        Section {
                            ForEach(shown) { item in
                                DSFileRow(item: item,
                                          isSelected: Binding(get: { item.isSelected },
                                                              set: { model.setSelected($0, item: item.id, in: item.category) }),
                                          quickLook: { previewURL = $0 })
                                    .listRowInsets(EdgeInsets(top: 0, leading: DS.Space.xs, bottom: 0, trailing: DS.Space.xs))
                            }
                        } header: {
                            HStack(spacing: DS.Space.sm) {
                                DSTile(category, size: .small)
                                Text(category.title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                                Text(String(localized: "\(shown.count) items")).font(DS.Font.numericCaption)
                                    .foregroundStyle(DS.Color.textSecondary)
                                Spacer()
                                Button("Untick All") {
                                    for item in shown { model.setSelected(false, item: item.id, in: category) }
                                }
                                .buttonStyle(.dsPlain).font(DS.Font.caption)
                            }
                            .padding(.vertical, DS.Space.xs)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 260)

            // Solid action bar: no blur behind scrolling content.
            HStack(spacing: DS.Space.md) {
                Text(String(localized: "\(items.count) items · \(total.formattedBytes)"))
                    .font(DS.Font.numericCallout).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.dsSecondary)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Move \(items.count) Items to Trash")) {
                    model.section = .smartScan
                    model.cleanSelected(in: categories)
                    dismiss()
                }
                .buttonStyle(.dsPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(items.isEmpty)
            }
            .padding(DS.Inset.bar)
            .background(DS.Color.backgroundWindow)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: DS.Layout.sheetWidth, idealWidth: DS.Layout.sheetWidth,
               minHeight: DS.Layout.sheetMinHeight, idealHeight: 620)
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
}

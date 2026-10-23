import SwiftUI

/// Final confirmation before anything is moved to the Trash.
struct ReviewSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    /// Limit cleaning to one category (from a detail page); nil means everything selected.
    var only: JunkCategory? = nil

    private var categories: [JunkCategory] { only.map { [$0] } ?? JunkCategory.smartScan }

    private var items: [JunkItem] {
        categories.flatMap { model.result(for: $0)?.selectedItems ?? [] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                GradientIcon(symbol: "trash.fill", gradient: Theme.accent, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to clean").font(.title2.bold())
                    Text("\(items.count) items, \(items.reduce(0) { $0 + $1.size }.formattedBytes), will be moved to the Trash. You can put anything back from there.")
                        .foregroundStyle(.secondary)
                }
            }

            List {
                ForEach(categories) { category in
                    let selected = model.result(for: category)?.selectedItems ?? []
                    if !selected.isEmpty {
                        Section {
                            ForEach(selected.prefix(200)) { item in
                                HStack {
                                    Text(item.url.abbreviatedPath)
                                        .lineLimit(1).truncationMode(.middle)
                                        .font(.callout.monospaced())
                                    Spacer()
                                    Text(item.size.formattedBytes).foregroundStyle(.secondary).font(.caption)
                                }
                            }
                            if selected.count > 200 {
                                Text("…and \(selected.count - 200) more").foregroundStyle(.secondary)
                            }
                        } header: {
                            Label(category.title, systemImage: category.symbol)
                        }
                    }
                }
            }
            .frame(minHeight: 260)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
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
        .frame(width: 620, height: 520)
    }
}

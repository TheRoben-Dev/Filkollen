import Charts
import SwiftUI

/// Every cleanup Filkollen did, with Put Back for anything still in the Trash.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var records: [CleanupHistory.Record] = []
    @State private var expanded: Set<UUID> = []
    @State private var inTrash: [CleanupHistory.Item] = []
    @State private var confirmEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            header.padding(DS.Inset.page)
            if let message = model.putBackMessage {
                DSBanner(.success, title: message)
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.md)
                    .dsTransition(.dsRise)
            }
            if records.isEmpty {
                DSEmptyState(symbol: "clock.arrow.circlepath", tint: DS.Color.textTertiary,
                             title: String(localized: "Nothing cleaned yet"),
                             message: String(localized: "Cleanups show up here so you can put things back."))
            } else {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        if months.count > 1 { chart.padding(.bottom, DS.Space.sm) }
                        ForEach(records) { record in card(record) }
                    }
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
                }
            }
        }
        .dsAnimation(.smooth, value: model.putBackMessage)
        .confirmationDialog("Delete \(inTrash.count) items permanently?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete from Trash", role: .destructive) {
                let history = model.history
                let home = FileManager.default.homeDirectoryForCurrentUser
                Task {
                    let result = await Task.detached(priority: .userInitiated) { history.emptyFromTrash(home: home) }.value
                    model.putBackMessage = result.failed == 0
                        ? String(localized: "Deleted \(result.freed.formattedBytes) of Filkollen's items from the Trash.")
                        : String(localized: "Deleted \(result.freed.formattedBytes); \(result.failed) items couldn't be deleted.")
                }
            }
        } message: {
            Text("Only items Filkollen moved to the Trash (\(inTrash.reduce(0) { $0 + $1.size }.formattedBytes)) are deleted. Everything else in your Trash stays. This can't be undone.")
        }
        .onAppear(perform: reload)
        .onChange(of: model.putBackMessage) { _ in reload() }
    }

    private var header: some View {
        let totals = (records.count, records.reduce(0) { $0 + $1.bytes })
        return DSPageHeader(title: String(localized: "Cleanup History"),
                            subtitle: totals.0 == 0 ? String(localized: "What Filkollen moved to the Trash")
                                : String(localized: "\(totals.0) cleanups, \(totals.1.formattedBytes) moved to the Trash in total"),
                            tile: DSTile(symbol: "clock.arrow.circlepath", tint: DS.Color.brand, size: .large)) {
            if !inTrash.isEmpty {
                Button("Empty Filkollen's Items from Trash…") { confirmEmpty = true }
                    .buttonStyle(.dsDestructive)
                    .help("Frees the space now. Only deletes what Filkollen put in the Trash.")
            }
        }
    }

    /// Bytes moved to the Trash per month, last 12 months.
    private var months: [(month: Date, bytes: Int64)] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .month, value: -11, to: calendar.startOfMonth(Date())) ?? .distantPast
        let grouped = Dictionary(grouping: records.filter { $0.date >= cutoff }) { calendar.startOfMonth($0.date) }
        return grouped.map { ($0.key, $0.value.reduce(0) { $0 + $1.bytes }) }.sorted { $0.month < $1.month }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            DSSectionHeader(String(localized: "Moved to the Trash per month"))
            Chart(months, id: \.month) { entry in
                BarMark(x: .value("Month", entry.month, unit: .month), y: .value("Bytes", Double(entry.bytes)))
                    .foregroundStyle(DS.Color.brand)
                    .cornerRadius(DS.Radius.badge)
                    .accessibilityLabel(entry.month.formatted(.dateTime.month(.wide).year()))
                    .accessibilityValue(entry.bytes.formattedBytes)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(DS.Color.separator)
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Int64(v).formattedBytes).font(DS.Font.numericCaption) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
            }
            .frame(height: 140)
        }
        .dsCard()
    }

    private func card(_ record: CleanupHistory.Record) -> some View {
        let isOpen = expanded.contains(record.id)
        return VStack(alignment: .leading, spacing: DS.Space.md) {
            HStack(spacing: DS.Space.md) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(record.source).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                    Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.items.count) items · \(record.bytes.formattedBytes)")
                        .font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                if record.restorable.isEmpty {
                    Text(record.items.allSatisfy(\.restored) ? "Put back" : "Done")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                } else {
                    Button("Put Back All") { model.putBack(record.id) }.buttonStyle(.dsSecondary)
                }
                Button {
                    withMotion(.smooth) {
                        if isOpen { expanded.remove(record.id) } else { expanded.insert(record.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(DS.Font.captionEmphasized)
                        .foregroundStyle(DS.Color.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: DS.Layout.minHitTarget, height: DS.Layout.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOpen ? "Hide items" : "Show items")
            }
            if isOpen {
                Divider()
                ForEach(record.items, id: \.original) { item in
                    HStack(spacing: DS.Space.md) {
                        Text((item.original as NSString).abbreviatingWithTildeInPath).dsPath()
                        Spacer()
                        Text(item.size.formattedBytes).font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                        if item.restored {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Color.success).help("Put back")
                                .accessibilityLabel("Put back")
                        } else if item.emptied == true {
                            Image(systemName: "trash.slash").foregroundStyle(DS.Color.textTertiary).help("Deleted from the Trash")
                                .accessibilityLabel("Deleted from the Trash")
                        } else {
                            Button("Put Back") { model.putBack(record.id, only: [item.original]) }
                                .buttonStyle(.dsPlain).font(DS.Font.caption)
                        }
                    }
                }
                .dsTransition(.dsRise)
            }
        }
        .dsCard()
    }

    private func reload() {
        records = model.history.records()
        inTrash = model.history.itemsInTrash(home: FileManager.default.homeDirectoryForCurrentUser)
    }
}

private extension Calendar {
    func startOfMonth(_ date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}

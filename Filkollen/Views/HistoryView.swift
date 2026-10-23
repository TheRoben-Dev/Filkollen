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
            header.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 14)
            if let message = model.putBackMessage {
                Label(message, systemImage: "arrow.uturn.backward.circle")
                    .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28).padding(.bottom, 10)
            }
            if records.isEmpty {
                Spacer()
                Text("Nothing cleaned yet. Cleanups show up here so you can put things back.")
                    .foregroundStyle(.white.opacity(0.65))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if months.count > 1 { chart }
                        ForEach(records) { record in card(record) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 16)
                }
            }
        }
        .foregroundStyle(.white)
        .confirmationDialog("Delete \(inTrash.count) items permanently?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Delete from Trash", role: .destructive) {
                let history = model.history
                let home = FileManager.default.homeDirectoryForCurrentUser
                Task {
                    let result = await Task.detached(priority: .userInitiated) { history.emptyFromTrash(home: home) }.value
                    model.putBackMessage = result.failed == 0
                        ? "Deleted \(result.freed.formattedBytes) of Filkollen's items from the Trash."
                        : "Deleted \(result.freed.formattedBytes); \(result.failed) items couldn't be deleted."
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
        return HStack(spacing: 16) {
            GradientIcon(symbol: "arrow.uturn.backward.circle.fill", gradient: Theme.gradient(.teal, .indigo), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("Cleanup History").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(totals.0 == 0 ? "What Filkollen moved to the Trash"
                     : "\(totals.0) cleanups, \(totals.1.formattedBytes) moved to the Trash in total")
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            if !inTrash.isEmpty {
                Button("Empty Filkollen's Items from Trash…") { confirmEmpty = true }
                    .buttonStyle(GhostButtonStyle())
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Moved to the Trash per month").font(.headline)
            Chart(months, id: \.month) { entry in
                BarMark(x: .value("Month", entry.month, unit: .month), y: .value("Bytes", Double(entry.bytes)))
                    .foregroundStyle(Theme.gradient(.teal, .indigo))
                    .accessibilityLabel(entry.month.formatted(.dateTime.month(.wide).year()))
                    .accessibilityValue(entry.bytes.formattedBytes)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel { if let v = value.as(Double.self) { Text(Int64(v).formattedBytes) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) }
            }
            .frame(height: 140)
        }
        .glassCard(padding: 14)
    }

    private func card(_ record: CleanupHistory.Record) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.source).font(.headline)
                    Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(record.items.count) items · \(record.bytes.formattedBytes)")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                if record.restorable.isEmpty {
                    Text(record.items.allSatisfy(\.restored) ? "Put back" : "Done")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                } else {
                    Button("Put Back All") { model.putBack(record.id) }.buttonStyle(GhostButtonStyle())
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if expanded.contains(record.id) { expanded.remove(record.id) } else { expanded.insert(record.id) }
                    }
                } label: {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded.contains(record.id) ? 90 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded.contains(record.id) ? "Hide items" : "Show items")
            }
            if expanded.contains(record.id) {
                Divider().overlay(.white.opacity(0.1))
                ForEach(record.items, id: \.original) { item in
                    HStack {
                        Text((item.original as NSString).abbreviatingWithTildeInPath)
                            .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(item.size.formattedBytes).font(.caption).foregroundStyle(.white.opacity(0.6))
                        if item.restored {
                            Image(systemName: "checkmark.circle").foregroundStyle(.green).help("Put back")
                                .accessibilityLabel("Put back")
                        } else if item.emptied == true {
                            Image(systemName: "trash.slash").foregroundStyle(.white.opacity(0.5)).help("Deleted from the Trash")
                                .accessibilityLabel("Deleted from the Trash")
                        } else {
                            Button("Put Back") { model.putBack(record.id, only: [item.original]) }
                                .buttonStyle(.plain).font(.caption).foregroundStyle(.cyan)
                        }
                    }
                }
            }
        }
        .glassCard(padding: 14)
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

import SwiftUI

/// Every cleanup Filkollen did, with Put Back for anything still in the Trash.
struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var records: [CleanupHistory.Record] = []
    @State private var expanded: Set<UUID> = []

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
                        ForEach(records) { record in card(record) }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 16)
                }
            }
        }
        .foregroundStyle(.white)
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
        }
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
                    Text("Put back").font(.caption).foregroundStyle(.white.opacity(0.5))
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

    private func reload() { records = model.history.records() }
}

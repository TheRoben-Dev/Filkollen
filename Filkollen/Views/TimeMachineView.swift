import SwiftUI

/// Shows Time Machine local snapshots and explains them. Nothing to clean here.
struct TimeMachineView: View {
    @State private var snapshots: [LocalSnapshots.Snapshot] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                DSPageHeader(title: String(localized: "Time Machine Snapshots"),
                             subtitle: String(localized: "Local snapshots on your startup disk"),
                             tile: DSTile(symbol: AppModel.SystemPage.snapshots.symbol, tint: DS.Color.brand, size: .large)) {
                    Button { Task { await reload() } } label: { Label("Refresh", systemImage: DS.Icon.refresh) }
                        .buttonStyle(.dsSecondary)
                        .disabled(loading)
                }

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    DSSectionHeader(String(localized: "What these are"))
                    Text("When Time Machine is on, macOS keeps hourly snapshots on this Mac so you can restore files even when your backup disk isn't connected. They can look like used space, but macOS deletes them automatically, oldest first, whenever space is needed, so you don't need to remove them to free space.")
                        .font(DS.Font.body).foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Filkollen doesn't delete snapshots. To turn local snapshots off, turn off Time Machine or change its options in System Settings.")
                        .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Time Machine Settings") { LocalSnapshots.openTimeMachineSettings() }
                        .buttonStyle(.dsSecondary)
                        .padding(.top, DS.Space.xs)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()

                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    if loading {
                        ForEach(0..<3, id: \.self) { _ in DSPlaceholderRow() }
                    } else if snapshots.isEmpty {
                        Label("No local snapshots right now.", systemImage: DS.Icon.success)
                            .font(DS.Font.body).foregroundStyle(DS.Color.textSecondary)
                    } else {
                        DSSectionHeader(snapshots.count == 1 ? String(localized: "1 snapshot")
                                                             : String(localized: "\(snapshots.count) snapshots"))
                        ForEach(snapshots) { snap in
                            HStack(spacing: DS.Space.md) {
                                Image(systemName: "camera.metering.center.weighted").foregroundStyle(DS.Color.brand)
                                Text(snap.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snap.name)
                                    .font(DS.Font.numeric).foregroundStyle(DS.Color.textPrimary)
                                Spacer()
                                Text(snap.date.map { $0.formatted(.relative(presentation: .named)) } ?? "")
                                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .dsCard()
            }
            .padding(DS.Inset.page)
            .frame(maxWidth: DS.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        snapshots = await LocalSnapshots.list()
        loading = false
    }
}

import SwiftUI

/// Shows Time Machine local snapshots and explains them. Nothing to clean here.
struct TimeMachineView: View {
    @State private var snapshots: [LocalSnapshots.Snapshot] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    GradientIcon(symbol: "clock.arrow.circlepath", gradient: Theme.gradient(.teal, .green), size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Machine Snapshots").font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("Local snapshots on your startup disk").foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button { Task { await reload() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .buttonStyle(GhostButtonStyle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("What these are").font(.headline)
                    Text("When Time Machine is on, macOS keeps hourly snapshots on this Mac so you can restore files even when your backup disk isn't connected. They can look like used space, but macOS deletes them automatically, oldest first, whenever space is needed, so you don't need to remove them to free space.")
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Filkollen doesn't delete snapshots. To turn local snapshots off, turn off Time Machine or change its options in System Settings.")
                        .font(.callout).foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Time Machine Settings") { LocalSnapshots.openTimeMachineSettings() }
                        .buttonStyle(GhostButtonStyle())
                }
                .glassCard()

                VStack(alignment: .leading, spacing: 8) {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if snapshots.isEmpty {
                        Label("No local snapshots right now.", systemImage: "checkmark.circle")
                    } else {
                        Text("\(snapshots.count) snapshot\(snapshots.count == 1 ? "" : "s")").font(.headline)
                        ForEach(snapshots) { snap in
                            HStack {
                                Image(systemName: "camera.metering.center.weighted").foregroundStyle(.teal)
                                Text(snap.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? snap.name)
                                Spacer()
                                Text(snap.date.map { $0.formatted(.relative(presentation: .named)) } ?? "")
                                    .font(.caption).foregroundStyle(.white.opacity(0.55))
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .glassCard()
            }
            .padding(28)
        }
        .foregroundStyle(.white)
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        snapshots = await LocalSnapshots.list()
        loading = false
    }
}

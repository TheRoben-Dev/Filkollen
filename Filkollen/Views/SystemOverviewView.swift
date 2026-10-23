import SwiftUI

struct SystemOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var snapshot = SystemInfo.snapshot()
    @State private var trashSize: Int64?
    @State private var confirmEmpty = false
    @State private var trashMessage: String?

    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let columns = [GridItem(.adaptive(minimum: 190), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                LazyVGrid(columns: columns, spacing: 14) {
                    RingCard(title: "Disk", symbol: "internaldrive.fill", fraction: snapshot.diskUsedFraction,
                             primary: "\(snapshot.diskFree.formattedBytes) free",
                             secondary: "of \(snapshot.diskTotal.formattedBytes)")
                    RingCard(title: "Memory", symbol: "memorychip.fill", fraction: snapshot.memoryFraction,
                             primary: "\(snapshot.memoryUsed.formattedMemory) used",
                             secondary: "of \(snapshot.memoryTotal.formattedMemory)")
                    RingCard(title: "CPU load", symbol: "cpu.fill", fraction: snapshot.cpuFraction,
                             primary: String(format: "%.2f", snapshot.load),
                             secondary: "1-min average, \(snapshot.cpuCount) cores")
                }
                HStack(alignment: .top, spacing: 14) {
                    infoCard
                    trashCard
                }
                toolsCard
            }
            .padding(28)
        }
        .foregroundStyle(.white)
        .onAppear { refresh(includeTrash: true) }
        .onReceive(tick) { _ in refresh(includeTrash: false) }
        .confirmationDialog("Empty the Trash permanently?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive, action: emptyTrash)
        } message: {
            Text("\((trashSize ?? 0).formattedBytes) will be deleted. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            GradientIcon(symbol: AppModel.SystemPage.overview.symbol, gradient: Theme.gradient(.teal, .indigo), size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text("System Overview").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("How your Mac is doing right now").foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("This Mac", systemImage: "laptopcomputer").font(.headline)
            InfoRow("System", snapshot.osVersion)
            InfoRow("Model", Self.modelIdentifier)
            InfoRow("Uptime", snapshot.uptime.uptimeString)
            InfoRow("Processor cores", "\(snapshot.cpuCount)")
            InfoRow("Full Disk Access", model.hasFullDiskAccess ? "Granted" : "Not granted")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var trashCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Trash", systemImage: "trash.fill").font(.headline)
            Text(trashSize.map(\.formattedBytes) ?? "Measuring…")
                .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
            if let trashMessage {
                Text(trashMessage).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            HStack {
                Button("Empty Trash…") { confirmEmpty = true }
                    .buttonStyle(PillButtonStyle(fill: Theme.danger))
                    .disabled((trashSize ?? 0) == 0)
                Button("Show") { NSWorkspace.shared.open(SystemInfo.trashURL) }
                    .buttonStyle(GhostButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .glassCard()
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Shortcuts", systemImage: "wrench.and.screwdriver.fill").font(.headline)
            HStack(spacing: 10) {
                tool("Activity Monitor", "waveform.path.ecg",
                     URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                tool("Disk Utility", "externaldrive.fill",
                     URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
                tool("Storage Settings", "chart.pie.fill",
                     URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
                tool("Software Update", "arrow.down.circle.fill", MacOSUpdateChecker.settingsURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func tool(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(GhostButtonStyle())
    }

    private func refresh(includeTrash: Bool) {
        Task {
            let s = await Task.detached(priority: .utility) { SystemInfo.snapshot(includeTrash: includeTrash) }.value
            snapshot = s
            if includeTrash { trashSize = s.trashSize }
        }
    }

    private func emptyTrash() {
        Task {
            let result = await Task.detached(priority: .userInitiated) { SystemInfo.emptyTrash() }.value
            trashMessage = result.failed == 0
                ? "Freed \(result.freed.formattedBytes)."
                : "Freed \(result.freed.formattedBytes). \(result.failed) item(s) couldn't be removed."
            refresh(includeTrash: true)
        }
    }

    /// e.g. "MacBookPro18,3"
    private static let modelIdentifier: String = {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }()
}

private struct InfoRow: View {
    let title: String
    let value: String
    init(_ title: String, _ value: String) { self.title = title; self.value = value }

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.callout)
    }
}

private struct RingCard: View {
    let title: String
    let symbol: String
    let fraction: Double
    let primary: String
    let secondary: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: min(1, max(0.01, fraction)))
                    .stroke(gradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                Text(primary).font(.headline.monospacedDigit())
                Text(secondary).font(.caption).foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }

    private var gradient: LinearGradient {
        fraction > 0.9 ? Theme.danger : fraction > 0.75 ? Theme.gradient(.orange, .pink) : Theme.safe
    }
}

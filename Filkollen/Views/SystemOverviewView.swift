import Combine
import SwiftUI

struct SystemOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @State private var snapshot = SystemInfo.snapshot()
    @State private var trashSize: Int64?
    @State private var confirmEmpty = false
    @State private var trashMessage: String?

    private let tick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: DS.Space.lg)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                LazyVGrid(columns: columns, spacing: DS.Space.lg) {
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
                HStack(alignment: .top, spacing: DS.Space.lg) {
                    infoCard
                    trashCard
                }
                toolsCard
            }
            .padding(DS.Inset.page)
            .frame(maxWidth: DS.Layout.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .onAppear { refresh(includeTrash: true) }
        .onReceive(tick) { _ in refresh(includeTrash: false) }
        .confirmationDialog("Empty the Trash permanently?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive, action: emptyTrash)
        } message: {
            Text("\((trashSize ?? 0).formattedBytes) will be deleted. This can't be undone.")
        }
    }

    private var header: some View {
        DSPageHeader(title: String(localized: "System Overview"),
                     subtitle: String(localized: "How your Mac is doing right now"),
                     tile: DSTile(symbol: AppModel.SystemPage.overview.symbol, tint: DS.Color.brand, size: .large))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("This Mac", systemImage: "laptopcomputer").font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
            InfoRow(String(localized: "System"), snapshot.osVersion)
            InfoRow(String(localized: "Model"), Self.modelIdentifier)
            InfoRow(String(localized: "Uptime"), snapshot.uptime.uptimeString)
            InfoRow(String(localized: "Processor cores"), "\(snapshot.cpuCount)")
            InfoRow(String(localized: "Full Disk Access"), model.hasFullDiskAccess ? String(localized: "Granted") : String(localized: "Not granted"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private var trashCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label("Trash", systemImage: "trash").font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
            if let trashSize {
                DSByteCount(trashSize, font: DS.Font.numericLarge).foregroundStyle(DS.Color.textPrimary)
            } else {
                Text("Measuring…").font(DS.Font.numericLarge).foregroundStyle(DS.Color.textTertiary)
            }
            if let trashMessage {
                Text(trashMessage).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: DS.Space.sm) {
                Button("Empty Trash…") { confirmEmpty = true }
                    .buttonStyle(.dsDestructive)
                    .disabled((trashSize ?? 0) == 0)
                Button("Show") { NSWorkspace.shared.open(SystemInfo.trashURL) }
                    .buttonStyle(.dsSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
        .dsCard()
    }

    private var toolsCard: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Label("Shortcuts", systemImage: "wrench.and.screwdriver").font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
            HStack(spacing: DS.Space.sm) {
                tool(String(localized: "Activity Monitor"), "waveform.path.ecg",
                     URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                tool(String(localized: "Disk Utility"), "externaldrive",
                     URL(fileURLWithPath: "/System/Applications/Utilities/Disk Utility.app"))
                tool(String(localized: "Storage Settings"), "chart.pie",
                     URL(string: "x-apple.systempreferences:com.apple.settings.Storage")!)
                tool(String(localized: "Software Update"), "arrow.down.circle", MacOSUpdateChecker.settingsURL)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    private func tool(_ title: String, _ symbol: String, _ url: URL) -> some View {
        Button { NSWorkspace.shared.open(url) } label: { Label(title, systemImage: symbol) }
            .buttonStyle(.dsSecondary)
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
                ? String(localized: "Freed \(result.freed.formattedBytes).")
                : String(localized: "Freed \(result.freed.formattedBytes). \(result.failed) item(s) couldn't be removed.")
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
            Text(title).foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Text(value).foregroundStyle(DS.Color.textPrimary).monospacedDigit().textSelection(.enabled)
        }
        .font(DS.Font.callout)
        .accessibilityElement(children: .combine)
    }
}

/// A gauge card: brand while healthy, warning above 75 %, danger above 90 %.
private struct RingCard: View {
    let title: String
    let symbol: String
    let fraction: Double
    let primary: String
    let secondary: String

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            ZStack {
                Circle().stroke(DS.Color.surfaceSunken, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, max(0.01, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .dsAnimation(.smooth, value: fraction)
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(DS.Font.numericCallout.weight(.semibold))
                    .foregroundStyle(DS.Color.textPrimary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Label(title, systemImage: symbol).font(DS.Font.captionEmphasized).foregroundStyle(DS.Color.textSecondary)
                Text(primary).font(DS.Font.headline.monospacedDigit()).foregroundStyle(DS.Color.textPrimary)
                Text(secondary).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .dsCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title), \(Int((fraction * 100).rounded())) percent, \(primary), \(secondary)"))
    }

    private var tint: Color {
        fraction > 0.9 ? DS.Color.danger : fraction > 0.75 ? DS.Color.warning : DS.Color.brand
    }
}

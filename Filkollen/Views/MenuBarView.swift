import Combine
import SwiftUI

/// The panel that drops down from the menu bar icon: live stats plus quick actions.
struct MenuBarView: View {
    @EnvironmentObject private var app: AppDelegate
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var protection: ProtectionModel
    @EnvironmentObject private var updates: UpdatesModel
    @Environment(\.openWindow) private var openWindow

    @State private var snapshot = SystemInfo.snapshot()
    @State private var trashSize: Int64?
    @State private var confirmTrash = false
    @State private var trashMessage: String?

    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            header
            stats
            statusCards
            actions
            Divider()
            footer
        }
        .padding(DS.Inset.menuBar)
        .frame(width: DS.Layout.menuBarWidth)
        .registersSettingsOpener(app)
        .onAppear {
            app.openMainWindowAction = { openWindow(id: "main") }
            refresh(includeTrash: true)
        }
        .onReceive(tick) { _ in refresh(includeTrash: false) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            DSTile(symbol: protection.threats.isEmpty ? DS.Icon.scan : DS.ProtectionState.threat.symbol,
                   tint: protection.threats.isEmpty ? DS.Color.brand : DS.ProtectionState.threat.color, size: .medium)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text("Filkollen").font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                Text(headline).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }

    private var headline: String {
        if !protection.threats.isEmpty {
            return protection.threats.count == 1 ? String(localized: "1 threat needs attention")
                                                 : String(localized: "\(protection.threats.count) threats need attention")
        }
        if model.isScanning { return String(localized: "Scanning for junk…") }
        if protection.phase == .scanning { return String(localized: "Checking files for malware…") }
        if model.smartScanTotal > 0 { return String(localized: "\(model.smartScanTotal.formattedBytes) of junk ready to clean") }
        return String(localized: "Your Mac looks good")
    }

    // MARK: Stats

    private var stats: some View {
        VStack(spacing: DS.Space.sm) {
            StatBar(symbol: "internaldrive.fill", title: "Disk",
                    detail: "\(snapshot.diskFree.formattedBytes) free of \(snapshot.diskTotal.formattedBytes)",
                    fraction: snapshot.diskUsedFraction)
            StatBar(symbol: "memorychip.fill", title: "Memory",
                    detail: "\(snapshot.memoryUsed.formattedMemory) of \(snapshot.memoryTotal.formattedMemory)",
                    fraction: snapshot.memoryFraction)
            StatBar(symbol: "cpu.fill", title: "CPU load",
                    detail: String(format: "%.2f on %d cores", snapshot.load, snapshot.cpuCount),
                    fraction: snapshot.cpuFraction)
        }
        .dsCard(insets: DS.Inset.menuBar)
    }

    private var statusCards: some View {
        HStack(spacing: DS.Space.sm) {
            MiniCard(symbol: "trash.fill", title: String(localized: "Junk"),
                     value: model.isScanning ? String(localized: "Scanning") : (model.lastSmartScan == nil ? String(localized: "Not scanned") : model.smartScanTotal.formattedBytes),
                     tint: DS.Color.brand)
            MiniCard(symbol: protectionState.symbol, title: String(localized: "Protection"), value: protectionValue,
                     tint: protectionState.color)
            MiniCard(symbol: "arrow.down.app.fill", title: String(localized: "Updates"), value: updatesValue, tint: DS.Color.info)
        }
    }

    private var protectionState: DS.ProtectionState {
        if !protection.threats.isEmpty { return .threat }
        if protection.databaseCount == 0 || protection.databaseIsStale { return .attention }
        return .protected
    }

    private var protectionValue: String {
        if protection.phase == .scanning { return String(localized: "Scanning") }
        if protection.phase == .updating { return String(localized: "Updating") }
        if !protection.threats.isEmpty { return String(localized: "\(protection.threats.count) found") }
        if protection.databaseCount == 0 { return String(localized: "No database") }
        return protection.databaseIsStale ? String(localized: "DB outdated") : String(localized: "Protected")
    }

    private var updatesValue: String {
        if updates.isChecking { return String(localized: "Checking") }
        if updates.lastChecked == nil { return String(localized: "Not checked") }
        return updates.updates.isEmpty ? String(localized: "Up to date") : String(localized: "\(updates.updates.count) available")
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: DS.Space.xs) {
            if model.phase == .results, model.smartScanSelected > 0 {
                MenuAction(symbol: "sparkles", title: "Review & Clean \(model.smartScanSelected.formattedBytes)") {
                    model.section = .smartScan
                    open()
                }
            } else {
                MenuAction(symbol: "sparkles", title: model.isScanning ? "Scanning…" : "Smart Scan",
                           detail: model.isScanning ? model.scanStatus : nil, busy: model.isScanning) {
                    model.startSmartScan()
                }
                .disabled(model.isScanning)
            }

            MenuAction(symbol: "shield.lefthalf.filled",
                       title: protection.threats.isEmpty ? (protection.phase == .scanning ? "Malware Scan…" : "Malware Scan") : "Review Threats",
                       detail: protection.isBusy ? protection.status : nil, busy: protection.isBusy) {
                if protection.threats.isEmpty {
                    protection.scan()
                } else {
                    model.section = .protection
                    open()
                }
            }
            .disabled(protection.isBusy)

            MenuAction(symbol: "arrow.down.app", title: updates.isChecking ? "Checking for Updates…" : "Check for Updates",
                       busy: updates.isChecking) {
                if updates.updates.isEmpty || updates.isChecking {
                    updates.check()
                } else {
                    model.section = .updates
                    open()
                }
            }
            .disabled(updates.isChecking)

            MenuAction(symbol: confirmTrash ? "exclamationmark.triangle.fill" : "trash",
                       title: trashTitle, detail: trashMessage, destructive: confirmTrash) {
                if confirmTrash { emptyTrash() } else { armTrash() }
            }
            .disabled((trashSize ?? 0) == 0 && !confirmTrash)
        }
    }

    private var trashTitle: String {
        let size = trashSize.map { $0 > 0 ? " (\($0.formattedBytes))" : String(localized: " (empty)") } ?? ""
        return confirmTrash ? String(localized: "Click again to delete permanently\(size)") : String(localized: "Empty Trash\(size)")
    }

    private func armTrash() {
        confirmTrash = true
        trashMessage = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { confirmTrash = false }
    }

    private func emptyTrash() {
        confirmTrash = false
        Task {
            let result = await Task.detached(priority: .userInitiated) { SystemInfo.emptyTrash() }.value
            trashMessage = result.failed == 0
                ? String(localized: "Freed \(result.freed.formattedBytes)")
                : String(localized: "Freed \(result.freed.formattedBytes), \(result.failed) item(s) couldn't be removed")
            refresh(includeTrash: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: DS.Space.xs) {
            Button { open() } label: { Label("Open Filkollen", systemImage: "macwindow") }
                .buttonStyle(.dsSecondary)
            Spacer()
            DSIconButton(String(localized: "Settings"), symbol: "gearshape") { app.showSettings() }
            DSIconButton(String(localized: "Quit Filkollen"), symbol: "power") { NSApp.terminate(nil) }
        }
    }

    // MARK: Helpers

    private func open() {
        app.showMainWindow()
    }

    private func refresh(includeTrash: Bool) {
        Task {
            let s = await Task.detached(priority: .utility) { SystemInfo.snapshot(includeTrash: includeTrash) }.value
            snapshot = s
            if includeTrash { trashSize = s.trashSize }
        }
    }
}

// MARK: - Pieces

private struct StatBar: View {
    let symbol: String
    let title: String
    let detail: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack {
                Label(title, systemImage: symbol).font(DS.Font.captionEmphasized).foregroundStyle(DS.Color.textPrimary)
                Spacer()
                Text(detail).font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
            }
            DSLinearProgress(value: fraction, tint: tint)
                .accessibilityLabel(title)
        }
    }

    private var tint: Color {
        fraction > 0.9 ? DS.Color.danger : fraction > 0.75 ? DS.Color.warning : DS.Color.brand
    }
}

private struct MiniCard: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title).font(DS.Font.badge).foregroundStyle(DS.Color.textSecondary)
            Text(value).font(DS.Font.captionEmphasized.monospacedDigit()).foregroundStyle(DS.Color.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(insets: EdgeInsets(top: DS.Space.sm, leading: DS.Space.sm, bottom: DS.Space.sm, trailing: DS.Space.sm))
        .accessibilityElement(children: .combine)
    }
}

private struct MenuAction: View {
    let symbol: String
    let title: String
    var detail: String? = nil
    var busy = false
    var destructive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.sm) {
                ZStack {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol).symbolRenderingMode(.hierarchical)
                    }
                }
                .frame(width: DS.Icon.TileSize.small.side)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(title).font(DS.Font.callout.weight(.medium)).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).dsPath(DS.Font.path)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Inset.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: DS.shape(DS.Radius.row))
            .contentShape(DS.shape(DS.Radius.row))
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? DS.Color.danger : DS.Color.textPrimary)
        .opacity(isEnabled || busy ? 1 : 0.45)
        .onHover { hovering = $0 }
        .dsAnimation(.snappy, value: hovering)
    }

    private var background: Color {
        if destructive { return DS.Color.danger.opacity(0.14) }
        return hovering && isEnabled ? DS.Color.surfaceSunken : .clear
    }
}

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
        VStack(alignment: .leading, spacing: 14) {
            header
            stats
            statusCards
            actions
            Divider().overlay(.white.opacity(0.15))
            footer
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(.white)
        .background(BackdropView(tint: headerTint).clipped())
        .preferredColorScheme(.dark)
        .onAppear {
            app.openMainWindowAction = { openWindow(id: "main") }
            refresh(includeTrash: true)
        }
        .onReceive(tick) { _ in refresh(includeTrash: false) }
    }

    // MARK: Header

    private var headerTint: Color { protection.threats.isEmpty ? .pink : .red }

    private var header: some View {
        HStack(spacing: 12) {
            GradientIcon(symbol: "sparkles", gradient: Theme.accent, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Filkollen").font(.headline)
                Text(headline).font(.caption).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
            Spacer()
        }
    }

    private var headline: String {
        if !protection.threats.isEmpty {
            return "\(protection.threats.count) threat\(protection.threats.count == 1 ? "" : "s") need attention"
        }
        if model.isScanning { return "Scanning for junk…" }
        if protection.phase == .scanning { return "Checking files for malware…" }
        if model.smartScanTotal > 0 { return "\(model.smartScanTotal.formattedBytes) of junk ready to clean" }
        return "Your Mac looks good"
    }

    // MARK: Stats

    private var stats: some View {
        VStack(spacing: 10) {
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
        .glassCard(padding: 12)
    }

    private var statusCards: some View {
        HStack(spacing: 8) {
            MiniCard(symbol: "trash.fill", title: "Junk",
                     value: model.isScanning ? "Scanning" : (model.lastSmartScan == nil ? "Not scanned" : model.smartScanTotal.formattedBytes),
                     tint: .pink)
            MiniCard(symbol: protection.threats.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                     title: "Protection", value: protectionValue,
                     tint: protection.threats.isEmpty ? .green : .red)
            MiniCard(symbol: "arrow.down.app.fill", title: "Updates", value: updatesValue, tint: .blue)
        }
    }

    private var protectionValue: String {
        if protection.phase == .scanning { return "Scanning" }
        if protection.phase == .updating { return "Updating" }
        if !protection.threats.isEmpty { return "\(protection.threats.count) found" }
        if protection.databaseCount == 0 { return "No database" }
        return protection.databaseIsStale ? "DB outdated" : "Protected"
    }

    private var updatesValue: String {
        if updates.isChecking { return "Checking" }
        if updates.lastChecked == nil { return "Not checked" }
        return updates.updates.isEmpty ? "Up to date" : "\(updates.updates.count) available"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 6) {
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
        let size = trashSize.map { $0 > 0 ? " (\($0.formattedBytes))" : " (empty)" } ?? ""
        return confirmTrash ? "Click again to delete permanently\(size)" : "Empty Trash\(size)"
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
                ? "Freed \(result.freed.formattedBytes)"
                : "Freed \(result.freed.formattedBytes), \(result.failed) item(s) couldn't be removed"
            refresh(includeTrash: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { open() } label: { Label("Open Filkollen", systemImage: "macwindow") }
                .buttonStyle(GhostButtonStyle())
            Spacer()
            Button { app.showSettings() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(GhostButtonStyle())
                .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(GhostButtonStyle())
                .help("Quit Filkollen")
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(title, systemImage: symbol).font(.caption.weight(.semibold))
                Spacer()
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.65))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(color).frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.4), value: fraction)
        }
    }

    private var color: LinearGradient {
        fraction > 0.9 ? Theme.danger : fraction > 0.75 ? Theme.gradient(.orange, .pink) : Theme.safe
    }
}

private struct MiniCard: View {
    let symbol: String
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
            Text(value).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(padding: 10)
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
            HStack(spacing: 10) {
                ZStack {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: symbol)
                    }
                }
                .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout.weight(.medium)).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? Color.red : Color.white)
        .opacity(isEnabled || busy ? 1 : 0.45)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if destructive { return .red.opacity(0.2) }
        return .white.opacity(hovering && isEnabled ? 0.14 : 0.06)
    }
}

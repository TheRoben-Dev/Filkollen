import SwiftUI

struct ProtectionView: View {
    @EnvironmentObject private var protection: ProtectionModel
    @AppStorage("abuseChAuthKey") private var abuseChAuthKey = ""
    @State private var tab = ProtectionView.startTab
    @State private var pendingDelete: [Threat] = []
    @State private var pendingQuarantineDelete: [Quarantine.Entry] = []

    enum Tab: String, CaseIterable { case scan = "Scan", quarantine = "Quarantine", trust = "App Trust" }

    #if DEBUG
    /// SnapshotRunner sets this to open a specific tab.
    @MainActor static var startTab = Tab.scan
    #else
    static let startTab = Tab.scan
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 28).padding(.top, 28).padding(.bottom, 16)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t == .quarantine && !protection.quarantined.isEmpty
                         ? "\(t.rawValue) (\(protection.quarantined.count))" : t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380)
            .padding(.bottom, 16)

            if let error = protection.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.horizontal, 28).padding(.bottom, 10)
            }

            switch tab {
            case .scan: scanTab
            case .quarantine: quarantineTab
            case .trust: AppTrustView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .confirmationDialog(
            "Permanently delete \(pendingDelete.count) file(s)?",
            isPresented: Binding(get: { !pendingDelete.isEmpty }, set: { if !$0 { pendingDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                protection.deletePermanently(pendingDelete)
                pendingDelete = []
            }
        } message: {
            Text("They skip the Trash and can't be recovered. Quarantine is the safer choice if you're unsure.")
        }
        .confirmationDialog(
            "Permanently delete \(pendingQuarantineDelete.count) quarantined file(s)?",
            isPresented: Binding(get: { !pendingQuarantineDelete.isEmpty },
                                 set: { if !$0 { pendingQuarantineDelete = [] } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                protection.deleteQuarantined(pendingQuarantineDelete)
                pendingQuarantineDelete = []
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 16) {
            GradientIcon(
                symbol: protection.threats.isEmpty ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                gradient: protection.threats.isEmpty ? Theme.safe : Theme.danger, size: 56
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Malware Scan").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Checks downloads, apps and launch items against known threats")
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }

    // MARK: Scan tab

    @ViewBuilder private var scanTab: some View {
        switch protection.phase {
        case .updating, .scanning:
            VStack(spacing: 18) {
                Spacer()
                ScanningRing(gradient: AngularGradient(colors: [.green, .teal, .blue, .green], center: .center), size: 150)
                Text(protection.phase == .updating ? "Updating threat database…" : "Scanning for malware…")
                    .font(.title3.weight(.semibold))
                Text(protection.status).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
                Spacer()
            }
        case .finished where !protection.threats.isEmpty:
            threatList
        case .finished:
            VStack(spacing: 14) {
                Spacer()
                GradientIcon(symbol: "checkmark.shield.fill", gradient: Theme.safe, size: 90)
                Text("No threats found").font(.title2.weight(.semibold))
                Text("\(protection.filesChecked) files checked").foregroundStyle(.white.opacity(0.6))
                Button("Scan Again") { protection.scan() }.buttonStyle(GhostButtonStyle())
                Spacer()
            }
        case .idle:
            idle
        }
    }

    /// Scrolls instead of overflowing the window when it's short, but stays
    /// vertically centred when there's room.
    private var idle: some View {
        GeometryReader { proxy in
            ScrollView {
                idleContent
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    private var idleContent: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    engineCard(
                        title: "MalwareBazaar",
                        detail: protection.databaseCount > 0
                            ? "\(protection.databaseCount.formatted()) known threats · updated \(protection.databaseUpdated?.formatted(.relative(presentation: .named)) ?? "never")"
                            : "Not downloaded yet. Needs a free abuse.ch Auth-Key.",
                        ok: !protection.databaseIsStale,
                        action: ("Update", protection.updateDatabase)
                    )
                    if abuseChAuthKey.isEmpty {
                        HStack {
                            SecureField("Paste your abuse.ch Auth-Key", text: $abuseChAuthKey)
                                .textFieldStyle(.roundedBorder)
                            Link("Get one", destination: URL(string: "https://auth.abuse.ch/")!)
                                .font(.caption)
                        }
                    }
                }
                engineCard(
                    title: "ClamAV (optional)",
                    detail: clamDetail,
                    ok: protection.clamAVInstalled && !protection.clamSignaturesAreStale,
                    toggle: protection.clamAVInstalled ? $protection.useClamAV : nil
                )
            }
            .padding(.horizontal, 28)

            if protection.databaseCount > 0 && protection.databaseIsStale {
                Label("The threat database is more than a week old. Update it before scanning to catch recent malware.",
                      systemImage: "clock.badge.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
                    .padding(.horizontal, 28)
            }

            Spacer(minLength: 12)
            BigScanButton(title: "Scan") { protection.scan() }
                .disabled(protection.databaseCount == 0 && !(protection.clamAVInstalled && protection.useClamAV))
            if protection.databaseCount == 0 {
                Text("Download the threat database first.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 8)
    }

    private var clamDetail: String {
        guard protection.clamAVInstalled else { return "Install with: brew install clamav" }
        guard let date = protection.clamSignaturesDate else {
            return "Installed, but no signatures yet. Run freshclam in Terminal first."
        }
        let age = "signatures from \(date.formatted(.relative(presentation: .named)))"
        return protection.clamSignaturesAreStale
            ? "Installed, \(age). Run freshclam in Terminal to update them."
            : "Installed, \(age). Deeper signature scan, slower"
    }

    private func engineCard(
        title: String, detail: String, ok: Bool,
        action: (String, () -> Void)? = nil, toggle: Binding<Bool>? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1).buttonStyle(GhostButtonStyle())
            }
            if let toggle {
                Toggle("", isOn: toggle).toggleStyle(.switch).labelsHidden()
            }
        }
        .frame(maxWidth: .infinity)
        .glassCard(padding: 16)
    }

    private var threatList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(protection.threats) { threat in
                        ThreatRow(threat: threat,
                                  quarantine: { protection.quarantine([threat]) },
                                  delete: { pendingDelete = [threat] })
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
            HStack {
                Text("\(protection.threats.count) threat(s) found")
                    .font(.headline).foregroundStyle(.red)
                Spacer()
                Button("Delete All…") { pendingDelete = protection.threats }
                    .buttonStyle(GhostButtonStyle())
                Button("Quarantine All") { protection.quarantine(protection.threats) }
                    .buttonStyle(PillButtonStyle(fill: Theme.danger))
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: Quarantine tab

    @ViewBuilder private var quarantineTab: some View {
        if protection.quarantined.isEmpty {
            VStack(spacing: 14) {
                Spacer()
                Image(systemName: "archivebox").font(.system(size: 54)).foregroundStyle(.white.opacity(0.4))
                Text("Quarantine is empty").font(.title3.weight(.semibold))
                Text("Quarantined files are locked so they can't run, and can be restored if it was a false alarm.")
                    .font(.callout).foregroundStyle(.white.opacity(0.6))
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(protection.quarantined) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: "lock.doc.fill").font(.title2).foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(entry.name).font(.headline).lineLimit(1)
                                        if entry.isMissing {
                                            Text("MISSING")
                                                .font(.caption2.bold())
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(.gray.opacity(0.6), in: Capsule())
                                                .help("The quarantined copy is no longer in the quarantine folder.")
                                        }
                                    }
                                    Text("\(entry.engine.rawValue) · \(entry.identifier.prefix(40)) · from \((entry.originalPath as NSString).abbreviatingWithTildeInPath)")
                                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                                        .lineLimit(1).truncationMode(.middle)
                                        .textSelection(.enabled)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                    Text(entry.size.formattedBytes)
                                }
                                .font(.caption).foregroundStyle(.white.opacity(0.55))
                                Button("Restore") { protection.restore(entry) }.buttonStyle(GhostButtonStyle())
                                    .disabled(entry.isMissing)
                                Button("Delete") { pendingQuarantineDelete = [entry] }
                                    .buttonStyle(PillButtonStyle(fill: Theme.danger))
                            }
                            .glassCard(padding: 14)
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 16)
                }
                HStack {
                    Button("Export Report…") { protection.exportQuarantineReport() }
                        .buttonStyle(GhostButtonStyle())
                        .help("Saves what was quarantined, from where and its SHA-256, as JSON. The files themselves stay here.")
                    Spacer()
                    let old = protection.quarantined(olderThanDays: 30)
                    if !old.isEmpty {
                        Button("Delete \(old.count) Older Than 30 Days…") { pendingQuarantineDelete = old }
                            .buttonStyle(GhostButtonStyle())
                    }
                    Button("Delete All Quarantined…") { pendingQuarantineDelete = protection.quarantined }
                        .buttonStyle(PillButtonStyle(fill: Theme.danger))
                }
                .padding(.horizontal, 28).padding(.vertical, 14)
                .background(.ultraThinMaterial)
            }
        }
    }
}

private struct ThreatRow: View {
    let threat: Threat
    let quarantine: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GradientIcon(symbol: "ladybug.fill", gradient: Theme.danger, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(threat.name).font(.headline).lineLimit(1)
                Text(threat.url.deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.white.opacity(0.55)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(threat.engine.rawValue)
                        .font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.white.opacity(0.15), in: Capsule())
                    if threat.engine == .clamAV {
                        Text(threat.identifier).font(.caption2.monospaced()).foregroundStyle(.orange)
                    } else if let report = threat.reportURL {
                        Link("View report", destination: report).font(.caption2)
                    }
                }
            }
            Spacer()
            Text(threat.size.formattedBytes).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.7))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([threat.url])
            } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain).help("Show in Finder")
                .accessibilityLabel("Show \(threat.name) in Finder")
            Button("Quarantine", action: quarantine).buttonStyle(GhostButtonStyle())
            Button("Delete", action: delete).buttonStyle(PillButtonStyle(fill: Theme.danger))
        }
        .glassCard(padding: 14)
    }
}

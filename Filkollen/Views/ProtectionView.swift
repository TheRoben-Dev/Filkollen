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

    /// Calm to alert, one layout: only colour, symbol and words change.
    private var state: DS.ProtectionState {
        if !protection.threats.isEmpty { return .threat }
        if protection.databaseCount == 0 || protection.databaseIsStale { return .attention }
        return .protected
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(DS.Inset.page)

            Picker("Section", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t == .quarantine && !protection.quarantined.isEmpty
                         ? "\(String(localized: String.LocalizationValue(t.rawValue))) (\(protection.quarantined.count))"
                         : String(localized: String.LocalizationValue(t.rawValue))).tag(t)
                }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 380)
            .padding(.bottom, DS.Space.lg)

            if let error = protection.errorMessage {
                DSBanner(.error, title: error)
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.md)
            }

            switch tab {
            case .scan: scanTab
            case .quarantine: quarantineTab
            case .trust: AppTrustView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
        DSPageHeader(title: String(localized: "Malware Scan"),
                     subtitle: String(localized: "Checks downloads, apps and launch items against known threats"),
                     tile: DSTile(symbol: state.symbol, tint: state.color, size: .large)) {
            Label(state.title, systemImage: state.symbol)
                .font(DS.Font.captionEmphasized)
                .foregroundStyle(state.color)
                .padding(DS.Inset.button)
                .background(state.color.opacity(0.12), in: Capsule())
        }
        .dsAnimation(.smooth, value: state)
    }

    // MARK: Scan tab

    @ViewBuilder private var scanTab: some View {
        switch protection.phase {
        case .updating, .scanning:
            VStack(spacing: DS.Space.xl) {
                Spacer(minLength: 0)
                DSScanRing(segments: [], isWorking: true, settled: false, diameter: 150, lineWidth: 10,
                           label: protection.phase == .updating ? String(localized: "Updating threat database")
                                                                : String(localized: "Scanning for malware")) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 36, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(DS.Color.brand)
                }
                Text(protection.phase == .updating ? "Updating threat database…" : "Scanning for malware…")
                    .font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                Text(protection.status).dsPath(DS.Font.pathBody).frame(maxWidth: DS.Layout.readableWidth)
                Spacer(minLength: 0)
            }
            .padding(DS.Inset.page)
        case .finished where !protection.threats.isEmpty:
            threatList
        case .finished:
            DSEmptyState(symbol: "checkmark.shield.fill", tint: DS.ProtectionState.protected.color,
                         title: String(localized: "No threats found"),
                         message: String(localized: "\(protection.filesChecked) files checked")) {
                Button("Scan Again") { protection.scan() }.buttonStyle(.dsSecondary)
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
        VStack(spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.lg) {
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    engineCard(
                        title: "MalwareBazaar",
                        detail: protection.databaseCount > 0
                            ? String(localized: "\(protection.databaseCount.formatted()) known threats · updated \(protection.databaseUpdated?.formatted(.relative(presentation: .named)) ?? String(localized: "never"))")
                            : String(localized: "Not downloaded yet. Needs a free abuse.ch Auth-Key."),
                        ok: !protection.databaseIsStale,
                        action: (String(localized: "Update"), protection.updateDatabase)
                    )
                    if abuseChAuthKey.isEmpty {
                        HStack(spacing: DS.Space.sm) {
                            SecureField("Paste your abuse.ch Auth-Key", text: $abuseChAuthKey)
                                .textFieldStyle(.roundedBorder)
                            Link("Get one", destination: URL(string: "https://auth.abuse.ch/")!)
                                .font(DS.Font.caption)
                        }
                    }
                }
                engineCard(
                    title: String(localized: "ClamAV (optional)"),
                    detail: clamDetail,
                    ok: protection.clamAVInstalled && !protection.clamSignaturesAreStale,
                    toggle: protection.clamAVInstalled ? $protection.useClamAV : nil
                )
            }
            .padding(.horizontal, DS.Space.xxl)

            if protection.databaseCount > 0 && protection.databaseIsStale {
                DSBanner(.warning, title: String(localized: "The threat database is more than a week old."),
                         message: String(localized: "Update it before scanning to catch recent malware."))
                    .padding(.horizontal, DS.Space.xxl)
            }

            Spacer(minLength: DS.Space.md)
            VStack(spacing: DS.Space.sm) {
                Button("Scan for Malware") { protection.scan() }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(protection.databaseCount == 0 && !(protection.clamAVInstalled && protection.useClamAV))
                if protection.databaseCount == 0 {
                    Text("Download the threat database first.")
                        .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.md)
        }
        .padding(.vertical, DS.Space.sm)
    }

    private var clamDetail: String {
        guard protection.clamAVInstalled else { return String(localized: "Install with: brew install clamav") }
        guard let date = protection.clamSignaturesDate else {
            return String(localized: "Installed, but no signatures yet. Run freshclam in Terminal first.")
        }
        let age = String(localized: "signatures from \(date.formatted(.relative(presentation: .named)))")
        return protection.clamSignaturesAreStale
            ? String(localized: "Installed, \(age). Run freshclam in Terminal to update them.")
            : String(localized: "Installed, \(age). Deeper signature scan, slower")
    }

    private func engineCard(
        title: String, detail: String, ok: Bool,
        action: (String, () -> Void)? = nil, toggle: Binding<Bool>? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: ok ? DS.Icon.success : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? DS.Color.success : DS.Color.warning).font(DS.Font.sectionTitle)
                .accessibilityLabel(ok ? String(localized: "Up to date") : String(localized: "Needs attention"))
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                Text(detail).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer()
            if let action {
                Button(action.0, action: action.1).buttonStyle(.dsSecondary)
            }
            if let toggle {
                Toggle(title, isOn: toggle).toggleStyle(.switch).labelsHidden()
            }
        }
        .frame(maxWidth: .infinity)
        .dsCard()
    }

    private var threatList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: DS.Space.sm) {
                    ForEach(protection.threats) { threat in
                        ThreatRow(threat: threat,
                                  quarantine: { protection.quarantine([threat]) },
                                  delete: { pendingDelete = [threat] })
                    }
                }
                .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
            }
            // Quarantine is the primary action; permanent delete is behind a confirmation.
            HStack(spacing: DS.Space.md) {
                Label(protection.threats.count == 1 ? String(localized: "1 threat found")
                                                    : String(localized: "\(protection.threats.count) threats found"),
                      systemImage: DS.ProtectionState.threat.symbol)
                    .font(DS.Font.headline).foregroundStyle(DS.ProtectionState.threat.color)
                Spacer()
                Button("Delete All…") { pendingDelete = protection.threats }
                    .buttonStyle(.dsSecondary)
                Button("Quarantine All") { protection.quarantine(protection.threats) }
                    .buttonStyle(.dsPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(DS.Inset.bar)
            .background(DS.Color.backgroundWindow)
            .overlay(alignment: .top) { Divider() }
        }
    }

    // MARK: Quarantine tab

    @ViewBuilder private var quarantineTab: some View {
        if protection.quarantined.isEmpty {
            DSEmptyState(symbol: "archivebox", badge: "lock.shield.fill", tint: DS.Color.info,
                         title: String(localized: "Quarantine is empty"),
                         message: String(localized: "Quarantined files are locked so they can't run, and can be restored if it was a false alarm."))
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: DS.Space.sm) {
                        ForEach(protection.quarantined) { entry in
                            QuarantineRow(entry: entry,
                                          restore: { protection.restore(entry) },
                                          delete: { pendingQuarantineDelete = [entry] })
                        }
                    }
                    .padding(.horizontal, DS.Space.xxl).padding(.bottom, DS.Space.lg)
                }
                HStack(spacing: DS.Space.md) {
                    Button("Export Report…") { protection.exportQuarantineReport() }
                        .buttonStyle(.dsSecondary)
                        .help("Saves what was quarantined, from where and its SHA-256, as JSON. The files themselves stay here.")
                    Spacer()
                    let old = protection.quarantined(olderThanDays: 30)
                    if !old.isEmpty {
                        Button(String(localized: "Delete \(old.count) Older Than 30 Days…")) { pendingQuarantineDelete = old }
                            .buttonStyle(.dsSecondary)
                    }
                    Button("Delete All Quarantined…") { pendingQuarantineDelete = protection.quarantined }
                        .buttonStyle(.dsDestructive)
                }
                .padding(DS.Inset.bar)
                .background(DS.Color.backgroundWindow)
                .overlay(alignment: .top) { Divider() }
            }
        }
    }
}

private struct QuarantineRow: View {
    let entry: Quarantine.Entry
    let restore: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            DSTile(symbol: "lock.doc.fill", tint: DS.Color.info, size: .medium)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Text(entry.name).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    DSBadge(.quarantined)
                    if entry.isMissing { DSBadge(.missing) }
                }
                Text("\(entry.engine.rawValue) · \(String(entry.identifier.prefix(40))) · from \((entry.originalPath as NSString).abbreviatingWithTildeInPath)")
                    .dsPath()
                    .textSelection(.enabled)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                Text(entry.size.formattedBytes)
            }
            .font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
            Button("Restore", action: restore).buttonStyle(.dsSecondary)
                .disabled(entry.isMissing)
            Button("Delete…", action: delete).buttonStyle(.dsSecondary)
                .help("Deletes the quarantined copy permanently, after asking")
        }
        .dsCard(insets: DS.Inset.row)
        .accessibilityElement(children: .contain)
    }
}

private struct ThreatRow: View {
    let threat: Threat
    let quarantine: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            DSTile(symbol: "ladybug.fill", tint: DS.ProtectionState.threat.color, size: .medium)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(threat.name).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(threat.url.deletingLastPathComponent().abbreviatedPath).dsPath()
                HStack(spacing: DS.Space.sm) {
                    DSBadge(.custom(threat.engine.rawValue, symbol: "shield.lefthalf.filled", tint: DS.Color.textSecondary))
                    if threat.engine == .clamAV {
                        Text(threat.identifier).font(DS.Font.path).foregroundStyle(DS.Color.warning)
                            .textSelection(.enabled)
                    } else if let report = threat.reportURL {
                        Link("View report", destination: report).font(DS.Font.caption).foregroundStyle(DS.Color.brand)
                    }
                }
            }
            Spacer()
            Text(threat.size.formattedBytes).font(DS.Font.numericCallout).foregroundStyle(DS.Color.textSecondary)
            DSIconButton(String(localized: "Show \(threat.name) in Finder"), symbol: DS.Icon.revealInFinder) {
                NSWorkspace.shared.activateFileViewerSelecting([threat.url])
            }
            Button("Delete…", action: delete).buttonStyle(.dsSecondary)
            Button("Quarantine", action: quarantine).buttonStyle(.dsPrimary)
        }
        .dsCard(insets: DS.Inset.row)
        .overlay(DS.shape(DS.Radius.card).strokeBorder(DS.ProtectionState.threat.color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

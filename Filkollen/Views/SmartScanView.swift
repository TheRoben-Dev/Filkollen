import SwiftUI

struct SmartScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showReview = false

    var body: some View {
        VStack(spacing: 28) {
            switch model.phase {
            case .idle: idle
            case .scanning: scanning
            case .results: results
            case .cleaning: cleaning
            case .done(let summary): done(summary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: model.phase)
        .sheet(isPresented: $showReview) { ReviewSheet().environmentObject(model) }
    }

    // MARK: States

    private var idle: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Text("Let's tidy up your Mac")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Smart Scan checks for system junk, app leftovers and duplicate photos in one go.")
                    .foregroundStyle(.white.opacity(0.7))
            }
            BigScanButton(title: "Scan") { model.startSmartScan() }
            HStack(spacing: 14) {
                ForEach(JunkCategory.smartScan) { category in
                    HStack(spacing: 10) {
                        GradientIcon(category, size: 30)
                        Text(category.title).font(.callout.weight(.medium))
                    }
                    .glassCard(padding: 10)
                }
            }
            Spacer()
        }
    }

    private var scanning: some View {
        VStack(spacing: 26) {
            Spacer()
            ZStack {
                ScanningRing()
                if let c = model.scanningCategory {
                    VStack(spacing: 10) {
                        GradientIcon(c, size: 54)
                        Text(c.title).font(.headline)
                    }
                }
            }
            Text(model.scanningCategory?.scanningMessage ?? "Scanning…")
                .font(.title3.weight(.semibold))
            Text(model.scanStatus)
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 520)
            Button("Stop") { model.cancelScan() }
                .buttonStyle(GhostButtonStyle())
            Spacer()
        }
    }

    private var results: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(model.smartScanTotal.formattedBytes)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("of junk found")
                    .font(.title3).foregroundStyle(.white.opacity(0.75))
                if model.smartScanSelected > 0 {
                    Text(reclaimNote(selected: model.smartScanSelected, reclaimable: model.smartScanReclaimable))
                        .font(.callout).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.top, 20)

            HStack(spacing: 16) {
                ForEach(JunkCategory.smartScan) { category in
                    ResultCard(category: category, result: model.result(for: category)) {
                        model.section = .category(category)
                    }
                }
            }

            Spacer()

            HStack(spacing: 14) {
                Button("Start Over") { model.reset() }
                    .buttonStyle(GhostButtonStyle())
                Button {
                    showReview = true
                } label: {
                    Text("Review & Clean \(model.smartScanSelected.formattedBytes)")
                }
                .buttonStyle(PillButtonStyle(large: true))
                .disabled(model.smartScanSelected == 0)
            }
        }
    }

    private var cleaning: some View {
        VStack(spacing: 22) {
            Spacer()
            ScanningRing(gradient: AngularGradient(colors: [.teal, .green, .teal], center: .center))
            Text("Moving files to Trash…").font(.title3.weight(.semibold))
            Spacer()
        }
    }

    private func done(_ summary: CleanupSummary) -> some View {
        VStack(spacing: 20) {
            Spacer()
            GradientIcon(
                symbol: summary.failures.isEmpty ? "checkmark" : "exclamationmark",
                gradient: summary.failures.isEmpty ? Theme.safe : Theme.gradient(.orange, .pink), size: 110
            )
            Text(summary.failures.isEmpty ? "Nice and clean!" : (summary.trashedCount > 0 ? "Mostly clean" : "Nothing was moved"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(summary.reclaimableBytes < summary.trashedBytes
                 ? "\(summary.trashedBytes.formattedBytes) moved to the Trash. About \(summary.reclaimableBytes.formattedBytes) comes back once you empty it; the rest was shared with other files."
                 : "\(summary.trashedBytes.formattedBytes) moved to the Trash. The space comes back once you empty it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            if !summary.failures.isEmpty {
                FailureList(failures: summary.failures)
                    .frame(maxWidth: 560)
            }
            if let message = model.putBackMessage {
                Text(message).font(.callout).foregroundStyle(.white.opacity(0.8))
            }
            HStack {
                if let id = summary.recordID, model.putBackMessage == nil {
                    Button("Undo") { model.putBack(id) }
                        .buttonStyle(GhostButtonStyle())
                        .help("Puts everything from this cleanup back where it was")
                }
                Button("Open Trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                .buttonStyle(GhostButtonStyle())
                Button("Done") { model.reset() }
                    .buttonStyle(PillButtonStyle())
            }
            Spacer()
        }
    }
}

/// "You'll get about X back once you empty the Trash", honest about clones.
func reclaimNote(selected: Int64, reclaimable: Int64) -> String {
    reclaimable < selected
        ? "About \(reclaimable.formattedBytes) of that comes back once you empty the Trash; the rest is shared with other files (APFS clones or hard links)."
        : "The space comes back once you empty the Trash."
}

/// Items a cleanup couldn't move, with the reason for each.
struct FailureList: View {
    let failures: [Cleaner.Failure]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("\(failures.count) item\(failures.count == 1 ? "" : "s") couldn't be moved")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the list" : "Shows each item and why")

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(failures, id: \.self) { failure in
                            HStack(alignment: .firstTextBaseline) {
                                Text(failure.url.abbreviatedPath)
                                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(failure.reason).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
            }
        }
        .glassCard(padding: 12)
    }
}

private struct ResultCard: View {
    let category: JunkCategory
    let result: CategoryResult?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 12) {
                GradientIcon(category, size: 46)
                Text(category.title).font(.headline)
                Text(category.subtitle)
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack {
                    Text((result?.totalSize ?? 0).formattedBytes)
                        .font(.title2.weight(.bold).monospacedDigit())
                    Spacer()
                    Text("Details")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "chevron.right").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 170, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

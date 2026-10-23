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
            case .done(let freed, let failed): done(freed: freed, failed: failed)
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

    private func done(freed: Int64, failed: Int) -> some View {
        VStack(spacing: 20) {
            Spacer()
            GradientIcon(symbol: "checkmark", gradient: Theme.safe, size: 110)
            Text("Nice and clean!")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(freed.formattedBytes) moved to the Trash. Empty it when you're sure.")
                .foregroundStyle(.white.opacity(0.75))
            if failed > 0 {
                Text("\(failed) item(s) couldn't be moved, most likely because they're in use.")
                    .font(.callout).foregroundStyle(.orange)
            }
            HStack {
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

import SwiftUI

/// The hero page. One ring carries the whole story: a quiet outline at idle,
/// one honest segment per category while scanning, a single settled Fjord ring
/// with the total once results are in (DIRECTION.md › The signature moment).
struct SmartScanView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showReview = false

    var body: some View {
        VStack(spacing: DS.Space.xxl) {
            switch model.phase {
            case .idle: idle
            case .scanning: scanning
            case .results: results
            case .cleaning: cleaning
            case .done(let summary): done(summary)
            }
        }
        .padding(DS.Inset.hero)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dsAnimation(.smooth, value: model.phase)
        .sheet(isPresented: $showReview) { ReviewSheet().environmentObject(model) }
    }

    // MARK: The ring

    private var segments: [DSScanSegment] {
        DSScanSegment.segments(for: JunkCategory.smartScan,
                                       scanning: model.scanningCategories,
                                       finished: Set(model.results.keys))
    }

    private func ring<Center: View>(working: Bool, settled: Bool, @ViewBuilder center: () -> Center) -> some View {
        DSScanRing(segments: segments, isWorking: working, settled: settled, diameter: 220, lineWidth: 12, center: center)
    }

    // MARK: States

    private var idle: some View {
        VStack(spacing: DS.Space.xxl) {
            Spacer(minLength: 0)
            ring(working: false, settled: false) {
                Image(systemName: DS.Icon.scan)
                    .font(.system(size: 44, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Color.brand)
            }
            VStack(spacing: DS.Space.sm) {
                Text("Let's tidy up your Mac")
                    .font(DS.Font.heroTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Smart Scan checks for system junk, app leftovers, duplicate photos and browser caches in one go. Nothing is removed until you review it.")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: DS.Layout.readableWidth)
            }
            VStack(spacing: DS.Space.sm) {
                Button("Smart Scan") { model.startSmartScan() }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                Text("⌘R").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    .accessibilityHidden(true)
            }
            HStack(spacing: DS.Space.md) {
                ForEach(JunkCategory.smartScan) { category in
                    HStack(spacing: DS.Space.sm) {
                        DSTile(category, size: .small)
                        Text(category.title).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private var scanning: some View {
        VStack(spacing: DS.Space.xxl) {
            Spacer(minLength: 0)
            ring(working: true, settled: false) {
                if let category = model.scanningCategory {
                    VStack(spacing: DS.Space.sm) {
                        DSTile(category, size: .large)
                        Text(category.title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                    }
                    .id(category)
                    .dsTransition(.dsPop)
                }
            }
            .dsAnimation(.smooth, value: model.scanningCategory)
            VStack(spacing: DS.Space.sm) {
                Text(model.scanningCategory?.scanningMessage ?? String(localized: "Scanning…"))
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(model.scanStatus)
                    .dsPath(DS.Font.pathBody)
                    .frame(maxWidth: DS.Layout.readableWidth)
                    .accessibilityLabel(String(localized: "Now checking \(model.scanStatus)"))
            }
            Button("Stop") { model.cancelScan() }
                .buttonStyle(.dsSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
        }
    }

    private var results: some View {
        VStack(spacing: DS.Space.xxl) {
            ring(working: false, settled: true) {
                VStack(spacing: DS.Space.xxs) {
                    DSByteCount(model.smartScanTotal)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("found").font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                }
                .padding(.horizontal, DS.Space.xl)
            }

            VStack(spacing: DS.Space.xs) {
                Text(model.smartScanSelected > 0
                     ? String(localized: "\(model.smartScanSelected.formattedBytes) selected to clean")
                     : String(localized: "Nothing selected yet"))
                    .font(DS.Font.sectionTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                if model.smartScanSelected > 0 {
                    Text(reclaimNote(selected: model.smartScanSelected, reclaimable: model.smartScanReclaimable))
                        .font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: DS.Layout.readableWidth)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.lg), count: JunkCategory.smartScan.count),
                      spacing: DS.Space.lg) {
                ForEach(Array(JunkCategory.smartScan.enumerated()), id: \.element) { index, category in
                    let result = model.result(for: category)
                    DSCategoryCard(category: category, size: result?.totalSize ?? 0, count: result?.items.count ?? 0,
                                   status: .init(result: result, isScanning: model.scanningCategories.contains(category))) {
                        model.section = .category(category)
                    }
                    .modifier(RiseIn(index: index))
                }
            }
            .frame(maxWidth: DS.Layout.contentMaxWidth)

            Spacer(minLength: 0)

            HStack(spacing: DS.Space.md) {
                Button("Start Over") { model.reset() }
                    .buttonStyle(.dsSecondary)
                Button(String(localized: "Review \(model.smartScanSelected.formattedBytes)…")) { showReview = true }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.smartScanSelected == 0)
            }
        }
    }

    private var cleaning: some View {
        VStack(spacing: DS.Space.xxl) {
            Spacer(minLength: 0)
            DSScanRing(segments: [], isWorking: true, settled: false, diameter: 220, lineWidth: 12,
                       label: String(localized: "Moving files to the Trash")) {
                Image(systemName: DS.Icon.trash)
                    .font(.system(size: 40, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Text("Moving files to the Trash…")
                .font(DS.Font.sectionTitle)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: 0)
        }
    }

    private func done(_ summary: CleanupSummary) -> some View {
        let clean = summary.failures.isEmpty
        return VStack(spacing: DS.Space.xl) {
            Spacer(minLength: 0)
            DSEmptyState(symbol: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                         tint: clean ? DS.Color.success : DS.Color.warning,
                         title: clean ? String(localized: "Nice and clean!")
                             : (summary.trashedCount > 0 ? String(localized: "Mostly clean") : String(localized: "Nothing was moved")),
                         message: summary.reclaimableBytes < summary.trashedBytes
                             ? String(localized: "\(summary.trashedBytes.formattedBytes) moved to the Trash. About \(summary.reclaimableBytes.formattedBytes) comes back once you empty it; the rest was shared with other files.")
                             : String(localized: "\(summary.trashedBytes.formattedBytes) moved to the Trash. The space comes back once you empty it."))
                .fixedSize(horizontal: false, vertical: true)
                .dsTransition(.dsPop)
            if !clean {
                FailureList(failures: summary.failures)
                    .frame(maxWidth: DS.Layout.readableWidth)
            }
            if let message = model.putBackMessage {
                DSBanner(.info, title: message)
                    .frame(maxWidth: DS.Layout.readableWidth)
            }
            HStack(spacing: DS.Space.md) {
                if let id = summary.recordID, model.putBackMessage == nil {
                    Button("Undo") { model.putBack(id) }
                        .buttonStyle(.dsSecondary)
                        .help("Puts everything from this cleanup back where it was")
                }
                Button("Open Trash") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                .buttonStyle(.dsSecondary)
                Button("Done") { model.reset() }
                    .buttonStyle(.dsPrimary)
                    .keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Tiles rise into place one after another, 40 ms apart, when results arrive.
private struct RiseIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : DS.Space.sm)
            .onAppear {
                let delay = Double(min(index, DS.Motion.staggerLimit)) * DS.Motion.stagger + DS.Duration.base
                withAnimation(DS.Motion.smooth.animation(reduceMotion: reduceMotion).delay(delay)) { shown = true }
            }
    }
}

/// "You'll get about X back once you empty the Trash", honest about clones.
func reclaimNote(selected: Int64, reclaimable: Int64) -> String {
    reclaimable < selected
        ? String(localized: "About \(reclaimable.formattedBytes) of that comes back once you empty the Trash; the rest is shared with other files (APFS clones or hard links).")
        : String(localized: "The space comes back once you empty the Trash.")
}

/// Items a cleanup couldn't move, with the reason for each.
struct FailureList: View {
    let failures: [Cleaner.Failure]
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Button {
                withMotion(.smooth) { expanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: DS.Icon.warning).foregroundStyle(DS.Color.warning)
                    Text(failures.count == 1 ? String(localized: "1 item couldn't be moved")
                                             : String(localized: "\(failures.count) items couldn't be moved"))
                        .font(DS.Font.bodyEmphasized)
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.Font.captionEmphasized)
                        .foregroundStyle(DS.Color.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides the list" : "Shows each item and why")

            if expanded {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DS.Space.sm) {
                        ForEach(failures, id: \.self) { failure in
                            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                                Text(failure.url.abbreviatedPath).dsPath()
                                Spacer()
                                Text(failure.reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .frame(maxHeight: 160)
                .dsTransition(.dsRise)
            }
        }
        .dsCard()
    }
}

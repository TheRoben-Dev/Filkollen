#if DEBUG
import Combine
import SwiftUI

/// Debug-only window (Debug › Design Gallery, ⌥⌘G) showing every design token
/// and component, in light and dark side by side. Increased Contrast follows
/// System Settings › Accessibility › Display, so toggle it there to check it.
struct DesignGalleryView: View {
    enum Page: String, CaseIterable, Identifiable {
        case color = "Colour", type = "Type", space = "Spacing", shape = "Shape & Depth", motion = "Motion", icons = "Icons", components = "Components"
        var id: String { rawValue }
    }

    @State private var page: Page

    init(page: Page = .color) {
        _page = State(initialValue: page)
    }

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: Binding($page)) { page in
                Text(page.rawValue).tag(page)
            }
            .navigationSplitViewColumnWidth(DS.Layout.sidebarIdeal)
        } detail: {
            ScrollView {
                HStack(alignment: .top, spacing: DS.Space.none) {
                    column(.light)
                    column(.dark)
                }
            }
            .background(DS.Color.backgroundUnderPage)
        }
        .frame(minWidth: DS.Layout.windowDefaultWidth, minHeight: DS.Layout.windowMinHeight)
        .dsAccent()
    }

    private func column(_ scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            Text(scheme == .light ? "Light" : "Dark").font(DS.Font.title)
            switch page {
            case .color: GalleryColors()
            case .type: GalleryType()
            case .space: GallerySpacing()
            case .shape: GalleryShape()
            case .motion: GalleryMotion()
            case .icons: GalleryIcons()
            case .components: GalleryComponents()
            }
        }
        .padding(DS.Inset.page)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(DS.Color.backgroundWindow)
        .foregroundStyle(DS.Color.textPrimary)
        .environment(\.colorScheme, scheme)
    }
}

private struct GallerySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title).font(DS.Font.headline).foregroundStyle(DS.Color.textSecondary)
            content
        }
    }
}

// MARK: - Colour

private struct GalleryColors: View {
    private let semantic: [(String, Color)] = [
        ("backgroundWindow", DS.Color.backgroundWindow), ("backgroundUnderPage", DS.Color.backgroundUnderPage),
        ("backgroundContent", DS.Color.backgroundContent), ("surface", DS.Color.surface),
        ("surfaceRaised", DS.Color.surfaceRaised), ("surfaceSunken", DS.Color.surfaceSunken),
        ("border", DS.Color.border), ("separator", DS.Color.separator),
    ]
    private let status: [(String, Color)] = [
        ("brand (Champagne)", DS.Color.brand), ("success", DS.Color.success), ("warning", DS.Color.warning),
        ("danger", DS.Color.danger), ("info", DS.Color.info),
    ]

    var body: some View {
        GallerySection(title: "Background and surface") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DS.Space.md)], spacing: DS.Space.md) {
                ForEach(semantic, id: \.0) { swatch($0.0, $0.1) }
            }
        }
        GallerySection(title: "Text") {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("textPrimary: Moves 412 items to the Trash").foregroundStyle(DS.Color.textPrimary)
                Text("textSecondary: You can put them back").foregroundStyle(DS.Color.textSecondary)
                Text("textTertiary: Last scanned 2 days ago").foregroundStyle(DS.Color.textTertiary)
                Text("textQuaternary: placeholder").foregroundStyle(DS.Color.textQuaternary)
            }
            .dsCard()
        }
        GallerySection(title: "Accent, brand and status (as text and fill)") {
            ForEach(status, id: \.0) { name, color in
                HStack(spacing: DS.Space.md) {
                    DS.shape(DS.Radius.control).fill(color).frame(width: 44, height: 28)
                    Text(name).foregroundStyle(color).font(DS.Font.bodyEmphasized)
                    Spacer()
                    Text("On fill").font(DS.Font.captionEmphasized).foregroundStyle(DS.Color.textOnFill)
                        .padding(DS.Inset.badge).background(color, in: DS.shape(DS.Radius.badge))
                }
            }
            HStack(spacing: DS.Space.md) {
                Text("Control tint").foregroundStyle(.tint).font(DS.Font.bodyEmphasized)
                Toggle("Toggle", isOn: .constant(true)).toggleStyle(.switch).labelsHidden()
                Button("Default") {}.keyboardShortcut(.defaultAction)
            }
        }
        GallerySection(title: "Protection: calm to alert") {
            HStack(spacing: DS.Space.md) {
                ForEach(DS.ProtectionState.allCases, id: \.self) { state in
                    VStack(spacing: DS.Space.sm) {
                        Image(systemName: state.symbol).font(DS.Font.numericLarge).foregroundStyle(state.color)
                        Text(state.title).font(DS.Font.captionEmphasized).foregroundStyle(state.color)
                    }
                    .frame(maxWidth: .infinity)
                    .dsCard()
                }
            }
        }
        GallerySection(title: "Category families") {
            ForEach(DS.CategoryFamily.allCases, id: \.self) { family in
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    Text(family.title).font(DS.Font.bodyEmphasized)
                    HStack(spacing: DS.Space.md) {
                        ForEach(JunkCategory.allCases.filter { $0.family == family }) { category in
                            HStack(spacing: DS.Space.sm) {
                                DSTile(category, size: .medium)
                                Text(category.title).font(DS.Font.caption).lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DS.shape(DS.Radius.control).fill(color)
                .overlay(DS.shape(DS.Radius.control).strokeBorder(DS.Color.border))
                .frame(height: 44)
            Text(name).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }
    }
}

// MARK: - Type

private struct GalleryType: View {
    private let styles: [(String, Font, String)] = [
        ("display", DS.Font.display, "6,4 GB"),
        ("numericLarge", DS.Font.numericLarge, "1 204 MB"),
        ("numericMedium", DS.Font.numericMedium, "35,5 MB"),
        ("heroTitle", DS.Font.heroTitle, "Let's tidy up your Mac"),
        ("title", DS.Font.title, "App Leftovers"),
        ("sectionTitle", DS.Font.sectionTitle, "Ready to clean"),
        ("headline", DS.Font.headline, "com.adobe.acc"),
        ("body", DS.Font.body, "Files left behind by apps you removed"),
        ("callout", DS.Font.callout, "About 6,04 GB comes back once you empty the Trash."),
        ("caption", DS.Font.caption, "Last scanned 2 days ago"),
        ("badge", DS.Font.badge, "Keep"),
        ("numericCaption", DS.Font.numericCaption, "412 items · 1 840 MB"),
    ]

    var body: some View {
        GallerySection(title: "Scale") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(styles, id: \.0) { name, font, sample in
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(sample).font(font)
                        Text(name).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("~/Library/Application Support/Adobe/CoreSync/plugins/livetype/.r/.12345.otf").dsPath()
                    Text("path").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                .frame(maxWidth: 320, alignment: .leading)
            }
        }
        GallerySection(title: "Monospaced digits: these don't move") {
            CountingSample()
        }
    }
}

private struct CountingSample: View {
    @State private var value: Int64 = 1_000_000_000
    private let tick = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    var body: some View {
        Text(value.formattedBytes)
            .font(DS.Font.display)
            .onReceive(tick) { _ in value = value > 9_000_000_000 ? 1_000_000_000 : value + 87_654_321 }
    }
}

// MARK: - Spacing

private struct GallerySpacing: View {
    private let steps: [(String, CGFloat)] = [
        ("xxs", DS.Space.xxs), ("xs", DS.Space.xs), ("sm", DS.Space.sm), ("md", DS.Space.md), ("lg", DS.Space.lg),
        ("xl", DS.Space.xl), ("xxl", DS.Space.xxl), ("xxxl", DS.Space.xxxl), ("huge", DS.Space.huge), ("giant", DS.Space.giant),
    ]

    var body: some View {
        GallerySection(title: "Space (4-pt scale)") {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(steps, id: \.0) { name, value in
                    HStack(spacing: DS.Space.md) {
                        Text(name).font(DS.Font.caption).frame(width: 44, alignment: .leading)
                        DS.shape(DS.Radius.badge).fill(.tint).frame(width: value, height: DS.Space.md)
                        Text("\(Int(value))").font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
        }
        GallerySection(title: "Container insets") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                Text("card").dsCard()
                Text("row").padding(DS.Inset.row).dsElevation(.surface, radius: DS.Radius.row)
                Text("badge").font(DS.Font.badge).padding(DS.Inset.badge).dsElevation(.surface, radius: DS.Radius.badge)
            }
        }
        GallerySection(title: "Layout") {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Window min \(Int(DS.Layout.windowMinWidth)) × \(Int(DS.Layout.windowMinHeight)), default \(Int(DS.Layout.windowDefaultWidth)) × \(Int(DS.Layout.windowDefaultHeight))")
                Text("Sidebar \(Int(DS.Layout.sidebarMin))–\(Int(DS.Layout.sidebarMax)), ideal \(Int(DS.Layout.sidebarIdeal)); inspector \(Int(DS.Layout.inspectorWidth))")
                Text("Readable column \(Int(DS.Layout.readableWidth)); content max \(Int(DS.Layout.contentMaxWidth))")
            }
            .font(DS.Font.numericCallout)
            .foregroundStyle(DS.Color.textSecondary)
        }
    }
}

// MARK: - Shape and depth

private struct GalleryShape: View {
    private let radii: [(String, CGFloat)] = [
        ("badge", DS.Radius.badge), ("small", DS.Radius.small), ("control", DS.Radius.control),
        ("row", DS.Radius.row), ("card", DS.Radius.card), ("hero", DS.Radius.hero),
    ]

    var body: some View {
        GallerySection(title: "Radius (continuous)") {
            HStack(spacing: DS.Space.md) {
                ForEach(radii, id: \.0) { name, radius in
                    VStack(spacing: DS.Space.xs) {
                        DS.shape(radius).fill(DS.Color.surfaceRaised)
                            .overlay(DS.shape(radius).strokeBorder(DS.Color.border))
                            .frame(width: 56, height: 56)
                        Text(name).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
        }
        GallerySection(title: "Elevation") {
            HStack(spacing: DS.Space.lg) {
                ForEach(DS.Elevation.allCases, id: \.self) { level in
                    Text(String(describing: level))
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .dsCard(level)
                }
            }
        }
        GallerySection(title: "Materials (Reduce Transparency makes them solid)") {
            ZStack {
                LinearGradient(colors: [DS.Color.brand, JunkCategory.duplicatePhotos.dsTint], startPoint: .leading, endPoint: .trailing)
                HStack(spacing: DS.Space.md) {
                    Text("overlay").padding(DS.Inset.card).dsMaterial(.overlay, in: DS.shape(DS.Radius.card))
                    Text("chrome").padding(DS.Inset.card).dsMaterial(.chrome, in: DS.shape(DS.Radius.card))
                    Text("bar").padding(DS.Inset.card).dsMaterial(.bar, in: DS.shape(DS.Radius.card))
                    Text("glass").padding(DS.Inset.card).dsGlass(in: DS.shape(DS.Radius.card))
                }
            }
            .frame(height: 120)
            .clipShape(DS.shape(DS.Radius.card))
        }
    }
}

// MARK: - Motion

private struct GalleryMotion: View {
    @State private var flipped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GallerySection(title: reduceMotion ? "Springs (Reduce Motion is on: crossfades)" : "Springs") {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(DS.Motion.allCases, id: \.self) { motion in
                    HStack(spacing: DS.Space.md) {
                        Text(String(describing: motion)).font(DS.Font.caption).frame(width: 60, alignment: .leading)
                        GeometryReader { geo in
                            Circle().fill(.tint)
                                .frame(width: DS.Space.lg, height: DS.Space.lg)
                                .offset(x: flipped && !reduceMotion ? geo.size.width - DS.Space.lg : 0)
                                .opacity(reduceMotion && flipped ? 0.4 : 1)
                                .dsAnimation(motion, value: flipped)
                        }
                        .frame(height: DS.Space.lg)
                        Text("\(Int(motion.response * 1000)) ms").font(DS.Font.numericCaption).foregroundStyle(DS.Color.textSecondary)
                    }
                }
                Button("Play") { flipped.toggle() }
            }
        }
        GallerySection(title: "Transitions") {
            HStack(spacing: DS.Space.md) {
                if flipped {
                    Text("dsRise").dsCard().dsTransition(.dsRise)
                    Text("dsPop").dsCard().dsTransition(.dsPop)
                }
            }
            .frame(height: 60)
            .dsAnimation(.smooth, value: flipped)
        }
    }
}

// MARK: - Components

private struct GalleryComponents: View {
    @State private var scanning = false
    @State private var done: Set<JunkCategory> = []
    @State private var total: Int64 = 0
    @State private var chipA = true
    @State private var chipB = false
    @State private var selected = true

    private let home = FileManager.default.homeDirectoryForCurrentUser

    private var settled: Bool { !scanning && done.count == JunkCategory.smartScan.count }

    var body: some View {
        GallerySection(title: "Buttons: normal, disabled, loading") {
            ForEach([DSButtonStyle.Kind.primary, .secondary, .destructive, .plain], id: \.self) { kind in
                HStack(spacing: DS.Space.md) {
                    Button(String(describing: kind).capitalized) {}.buttonStyle(.ds(kind))
                    Button("Disabled") {}.buttonStyle(.ds(kind)).disabled(true)
                    Button("Working") {}.buttonStyle(.ds(kind, loading: true))
                }
            }
            HStack(spacing: DS.Space.md) {
                Button("Review 6,2 GB…") {}.buttonStyle(.ds(.primary, size: .large))
                DSIconButton("Quick Look", symbol: DS.Icon.quickLook) {}
                DSIconButton("Show in Finder", symbol: DS.Icon.revealInFinder) {}
                DSIconButton("Disabled", symbol: DS.Icon.trash) {}.disabled(true)
            }
        }
        GallerySection(title: "Badges") {
            HStack(spacing: DS.Space.sm) {
                DSBadge(.keep); DSBadge(.lowConfidence); DSBadge(.inUse("Spotify")); DSBadge(.quarantined)
            }
            HStack(spacing: DS.Space.sm) {
                DSBadge(.unsigned); DSBadge(.missing); DSBadge(.notarized)
            }
        }
        GallerySection(title: "Chips") {
            HStack(spacing: DS.Space.sm) {
                DSChip(title: "Selected", symbol: "checkmark.circle", count: 412, isOn: $chipA)
                DSChip(title: "Needs a look", symbol: "eye", count: 3, isOn: $chipB)
            }
        }
        GallerySection(title: "Scan ring and counting") {
            HStack(alignment: .center, spacing: DS.Space.xxl) {
                DSScanRing(
                    segments: DSScanSegment.segments(for: JunkCategory.smartScan, scanning: scanning ? Set(JunkCategory.smartScan).subtracting(done) : [], finished: done),
                    isWorking: scanning, settled: settled, diameter: 180, lineWidth: 12
                ) { EmptyView() }
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    DSByteCount(total).dsAnimation(.gentle, value: total)
                    Text("you can safely reclaim").font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    HStack {
                        Button("Scan") { runDemo() }.buttonStyle(.dsPrimary).disabled(scanning)
                        Button("Reset") { done = []; total = 0 }.buttonStyle(.dsSecondary)
                    }
                }
            }
            DSLinearProgress(value: 0.62)
            DSLinearProgress(value: nil)
        }
        GallerySection(title: "Category cards") {
            HStack(spacing: DS.Space.md) {
                DSCategoryCard(category: .systemJunk, size: 4_000_000_000, count: 6, status: .ready) {}
                DSCategoryCard(category: .appLeftovers, size: 1_290_000_000, count: 4, status: .needsLook(1)) {}
                DSCategoryCard(category: .duplicatePhotos, size: 0, count: 0, status: .scanning) {}
            }
        }
        GallerySection(title: "File rows and placeholders") {
            VStack(spacing: DS.Space.none) {
                DSFileRow(item: fixture("Library/Caches/com.spotify.client", inUse: "Spotify"), isSelected: .constant(false), quickLook: { _ in })
                DSFileRow(item: fixture("Pictures/Iceland 2024/IMG_4312.HEIC", keeper: true), isSelected: .constant(false), quickLook: { _ in })
                DSFileRow(item: fixture("Library/Application Support/Spotify", low: true), isSelected: $selected, quickLook: { _ in })
                DSPlaceholderRow()
                DSPlaceholderRow()
            }
            .dsElevation()
        }
        GallerySection(title: "Banners and empty state") {
            DSBanner(.warning, title: "The threat database is 9 days old", message: "Update it before scanning to catch recent malware.")
            DSBanner(kind: .error, title: "2 items couldn't be moved", message: "Microsoft Teams is running.") {
                Button("Show") {}.buttonStyle(.dsPlain)
            }
            DSEmptyState(symbol: "tray", badge: "checkmark.circle.fill", tint: DS.Color.success,
                         title: "Nothing to clean here", message: "Filkollen found no app leftovers. Nice and tidy.") {
                Button("Scan Again") {}.buttonStyle(.dsSecondary)
            }
            .frame(height: 260)
            .dsElevation()
        }
        GallerySection(title: "Toast") {
            DSToastView(toast: DSToastMessage(text: "Moved 2,3 GB to the Trash", actionTitle: "Undo", action: {}), dismiss: {})
        }
    }

    private func fixture(_ path: String, keeper: Bool = false, low: Bool = false, inUse: String? = nil) -> JunkItem {
        var item = JunkItem(url: home.appendingPathComponent(path), size: 1_840_000_000, category: .systemJunk, group: "g")
        item.isKeeper = keeper
        item.confidence = low ? .low : nil
        item.inUseBy = inUse
        return item
    }

    private func runDemo() {
        done = []
        total = 0
        scanning = true
        for (i, category) in JunkCategory.smartScan.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7 * Double(i + 1)) {
                done.insert(category)
                if done.count == JunkCategory.smartScan.count {
                    scanning = false
                    total = 6_412_000_000
                }
            }
        }
    }
}

// MARK: - Icons

private struct GalleryIcons: View {
    private let actions: [(String, String)] = [
        ("quickLook", DS.Icon.quickLook), ("revealInFinder", DS.Icon.revealInFinder), ("trash", DS.Icon.trash),
        ("restore", DS.Icon.restore), ("quarantine", DS.Icon.quarantine), ("deletePermanently", DS.Icon.deletePermanently),
        ("refresh", DS.Icon.refresh), ("info", DS.Icon.info), ("warning", DS.Icon.warning),
        ("success", DS.Icon.success), ("scan", DS.Icon.scan),
    ]

    var body: some View {
        GallerySection(title: "Category tiles: small, medium, large") {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(JunkCategory.allCases) { category in
                    HStack(spacing: DS.Space.md) {
                        ForEach(DS.Icon.TileSize.allCases, id: \.self) { DSTile(category, size: $0) }
                        Text(category.title).font(DS.Font.callout)
                    }
                }
            }
        }
        GallerySection(title: "Action symbols (hierarchical)") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DS.Space.md)], alignment: .leading, spacing: DS.Space.md) {
                ForEach(actions, id: \.0) { name, symbol in
                    Label(name, systemImage: symbol).symbolRenderingMode(.hierarchical).font(DS.Font.callout)
                }
            }
        }
    }
}
#endif

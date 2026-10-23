import AppKit
import QuickLookThumbnailing
import SwiftUI

// MARK: - File icons

/// Finder icons, cached per path so long lists don't hit NSWorkspace on every redraw.
@MainActor
enum DSFileIconCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 2_000
        return cache
    }()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

/// The real Finder icon for a file, or a Quick Look thumbnail for images.
struct DSFileIcon: View {
    let url: URL
    var size: CGFloat = DS.Icon.TileSize.small.side
    var thumbnail = false

    @State private var preview: NSImage?

    var body: some View {
        Group {
            if let preview {
                Image(nsImage: preview).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(DS.shape(DS.Radius.small))
            } else {
                Image(nsImage: DSFileIconCache.icon(for: url)).resizable().scaledToFit()
                    .frame(width: size, height: size)
            }
        }
        .accessibilityHidden(true)
        .task(id: thumbnail ? url : nil) {
            guard thumbnail else { return }
            let request = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: size, height: size),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
            )
            preview = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}

// MARK: - File row

/// One file in a review or category list: checkbox, Finder icon, name,
/// middle-truncated path, safety badges and size. Cheap enough for 10k rows in
/// a `List`/`LazyVStack` (no materials, no shadows, cached icons).
struct DSFileRow: View {
    let item: JunkItem
    @Binding var isSelected: Bool
    var showsThumbnail = false
    /// Show the parent folder instead of `item.detail` under the name.
    var showsPath = true
    var quickLook: ((URL) -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Toggle(isOn: $isSelected) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(item.isKeeper)
                .accessibilityLabel(String(localized: "Clean \(item.name)"))

            DSFileIcon(url: item.url, size: showsThumbnail ? DS.Icon.TileSize.medium.side : DS.Icon.TileSize.small.side,
                       thumbnail: showsThumbnail)

            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                HStack(spacing: DS.Space.sm) {
                    Text(item.name)
                        .font(DS.Font.body)
                        .foregroundStyle(isSelected || item.isKeeper ? DS.Color.textPrimary : DS.Color.textSecondary)
                        .lineLimit(1).truncationMode(.middle)
                    badges
                }
                Text(showsPath ? item.url.deletingLastPathComponent().abbreviatedPath : item.detail)
                    .dsPath()
            }

            Spacer(minLength: DS.Space.sm)

            Text(item.size.formattedBytes)
                .font(DS.Font.numericCallout)
                .foregroundStyle(DS.Color.textSecondary)

            HStack(spacing: DS.Space.xxs) {
                if let quickLook {
                    DSIconButton(String(localized: "Quick Look \(item.name)"), symbol: DS.Icon.quickLook) { quickLook(item.url) }
                }
                DSIconButton(String(localized: "Show \(item.name) in Finder"), symbol: DS.Icon.revealInFinder) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
            .opacity(hovering ? 1 : 0.55)
        }
        .padding(DS.Inset.row)
        .background(hovering ? DS.Color.surfaceSunken : .clear, in: DS.shape(DS.Radius.row))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var badges: some View {
        if item.isKeeper { DSBadge(.keep) }
        if item.confidence == .low { DSBadge(.lowConfidence) }
        if item.inUseBy != nil { DSBadge(.inUse(item.inUseBy)) }
    }
}

// MARK: - Category tile

/// A Smart Scan result tile: tile icon, title, size, item count and a status
/// line, with a subtle hover lift. The whole tile is one button.
struct DSCategoryCard: View {
    enum Status: Equatable {
        case notScanned, scanning, ready, needsLook(Int), clean
    }

    let category: JunkCategory
    var size: Int64
    var count: Int
    var status: Status
    let open: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                HStack(alignment: .top) {
                    DSTile(category, size: .medium)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(DS.Font.captionEmphasized)
                        .foregroundStyle(DS.Color.textTertiary)
                        .opacity(hovering ? 1 : 0)
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(category.title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(2)
                    Text(category.family.title).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                DSByteCount(size, font: DS.Font.numericMedium)
                    .foregroundStyle(DS.Color.textPrimary)
                HStack(spacing: DS.Space.xs) {
                    statusView
                    Spacer(minLength: 0)
                    if count > 0 {
                        Text(String(localized: "\(count) items"))
                            .font(DS.Font.numericCaption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard(hovering && isEnabled ? .raised : .surface)
            .offset(y: hovering && isEnabled ? -2 : 0)
            .contentShape(DS.shape(DS.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsAnimation(.snappy, value: hovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(category.title), \(size.formattedBytes), \(statusText)"))
        .accessibilityHint(String(localized: "Shows what was found"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .scanning:
            ProgressView().controlSize(.mini)
            Text(statusText).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        case .ready:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Color.success).imageScale(.small)
            Text(statusText).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        case .needsLook:
            Image(systemName: "eye.circle.fill").foregroundStyle(DS.Color.warning).imageScale(.small)
            Text(statusText).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        case .clean:
            Image(systemName: "sparkles").foregroundStyle(DS.Color.success).imageScale(.small)
            Text(statusText).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        case .notScanned:
            Text(statusText).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var statusText: String {
        switch status {
        case .notScanned: return String(localized: "Not scanned")
        case .scanning: return String(localized: "Scanning…")
        case .ready: return String(localized: "Ready")
        case .needsLook(let n): return String(localized: "\(n) need a look")
        case .clean: return String(localized: "Nothing to clean")
        }
    }
}

extension DSCategoryCard.Status {
    /// Status for a category from its scan result.
    init(result: CategoryResult?, isScanning: Bool) {
        if isScanning { self = .scanning; return }
        guard let result else { self = .notScanned; return }
        if result.items.isEmpty { self = .clean; return }
        let flagged = result.items.filter { $0.confidence == .low || $0.inUseBy != nil }.count
        self = flagged > 0 ? .needsLook(flagged) : .ready
    }
}

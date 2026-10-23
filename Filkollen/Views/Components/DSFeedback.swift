import AppKit
import Combine
import SwiftUI

// MARK: - Badge

/// A small pill that changes what's safe to do with an item. Every badge has a
/// symbol and a word, so meaning never rides on colour alone.
struct DSBadge: View {
    enum Kind {
        /// The duplicate copy Filkollen keeps.
        case keep
        /// A guess-based match that needs a look; never pre-selected.
        case lowConfidence
        /// A running app is probably using it.
        case inUse(String?)
        case quarantined
        case unsigned
        /// The stored copy has gone missing.
        case missing
        case notarized
        case custom(String, symbol: String, tint: Color)
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .labelStyle(BadgeLabelStyle())
        .font(DS.Font.badge)
        .foregroundStyle(tint)
        .padding(DS.Inset.badge)
        .background(tint.opacity(0.14), in: DS.shape(DS.Radius.badge))
        .overlay(DS.shape(DS.Radius.badge).strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        .fixedSize()
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        switch kind {
        case .keep: return String(localized: "Keep")
        case .lowConfidence: return String(localized: "Low confidence")
        case .inUse: return String(localized: "In use")
        case .quarantined: return String(localized: "Quarantined")
        case .unsigned: return String(localized: "Unsigned")
        case .missing: return String(localized: "Missing")
        case .notarized: return String(localized: "Notarized")
        case .custom(let title, _, _): return title
        }
    }

    private var symbol: String {
        switch kind {
        case .keep: return "checkmark.seal.fill"
        case .lowConfidence: return "questionmark.circle.fill"
        case .inUse: return "bolt.horizontal.circle.fill"
        case .quarantined: return "lock.shield.fill"
        case .unsigned: return "exclamationmark.triangle.fill"
        case .missing: return "questionmark.folder.fill"
        case .notarized: return "checkmark.shield.fill"
        case .custom(_, let symbol, _): return symbol
        }
    }

    private var tint: Color {
        switch kind {
        case .keep, .notarized: return DS.Color.success
        case .lowConfidence, .missing: return DS.Color.textSecondary
        case .inUse, .unsigned: return DS.Color.warning
        case .quarantined: return DS.Color.info
        case .custom(_, _, let tint): return tint
        }
    }

    private var help: String {
        switch kind {
        case .keep: return String(localized: "This copy is kept. Filkollen never selects it.")
        case .lowConfidence: return String(localized: "No removed app was confirmed for this folder. Check it before cleaning.")
        case .inUse(let app): return app.map { String(localized: "Probably in use by \($0). Quit it before cleaning.") }
            ?? String(localized: "Probably in use by a running app.")
        case .quarantined: return String(localized: "Locked in Filkollen's quarantine so it can't run.")
        case .unsigned: return String(localized: "Not signed by an identified developer.")
        case .missing: return String(localized: "The stored copy is no longer in the quarantine folder.")
        case .notarized: return String(localized: "Checked by Apple for known malware.")
        case .custom(let title, _, _): return title
        }
    }

    private var accessibilityText: String {
        if case .inUse(let app?) = kind { return String(localized: "In use by \(app)") }
        return title
    }
}

private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: DS.Space.xxs + 1) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

// MARK: - Section header

struct DSSectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.sm) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                if let subtitle {
                    Text(subtitle).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
            }
            Spacer(minLength: DS.Space.sm)
            trailing
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
    }
}

extension DSSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Page header

/// The header every content page starts with: tile, title, explanation, and
/// an optional figure and actions on the right.
struct DSPageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    var tile: DSTile?
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.lg) {
            if let tile { tile }
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(DS.Font.title).foregroundStyle(DS.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.lg)
            accessory
        }
    }
}

extension DSPageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String, tile: DSTile? = nil) {
        self.init(title: title, subtitle: subtitle, tile: tile) { EmptyView() }
    }
}

// MARK: - Empty and error states

/// A composed SF Symbol illustration with warm copy and an optional action.
struct DSEmptyState<Actions: View>: View {
    let symbol: String
    var badge: String?
    var tint: Color = DS.Color.textTertiary
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: symbol)
                    .font(.system(size: DS.Icon.TileSize.large.side, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: DS.Icon.TileSize.medium.side * 0.75, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DS.Color.textOnFill, tint)
                        .background(Circle().fill(DS.Color.backgroundWindow).padding(-2))
                        .offset(x: DS.Space.sm, y: DS.Space.xs)
                }
            }
            .accessibilityHidden(true)
            VStack(spacing: DS.Space.xs) {
                Text(title).font(DS.Font.sectionTitle).foregroundStyle(DS.Color.textPrimary)
                if let message {
                    Text(message).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: DS.Layout.readableWidth)
            actions
        }
        .padding(DS.Inset.hero)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

extension DSEmptyState where Actions == EmptyView {
    init(symbol: String, badge: String? = nil, tint: Color = DS.Color.textTertiary, title: String, message: String? = nil) {
        self.init(symbol: symbol, badge: badge, tint: tint, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Banner

/// An inline message at the top of a page: info, success, warning or error.
struct DSBanner<Actions: View>: View {
    enum Kind { case info, success, warning, error }

    let kind: Kind
    let title: String
    var message: String?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .font(DS.Font.headline)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(DS.Font.headline).foregroundStyle(DS.Color.textPrimary)
                if let message {
                    Text(message).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: DS.Space.sm)
            actions
        }
        .padding(DS.Inset.card)
        .background(tint.opacity(0.08), in: DS.shape(DS.Radius.card))
        .overlay(DS.shape(DS.Radius.card).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(kindLabel): \(title)"))
    }

    private var tint: Color {
        switch kind {
        case .info: return DS.Color.info
        case .success: return DS.Color.success
        case .warning: return DS.Color.warning
        case .error: return DS.Color.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var kindLabel: String {
        switch kind {
        case .info: return String(localized: "Note")
        case .success: return String(localized: "Done")
        case .warning: return String(localized: "Warning")
        case .error: return String(localized: "Error")
        }
    }
}

extension DSBanner where Actions == EmptyView {
    init(_ kind: Kind, title: String, message: String? = nil) {
        self.init(kind: kind, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Filter chip

/// A toggleable filter, styled to sit next to native segmented controls.
struct DSChip: View {
    let title: String
    var symbol: String?
    var count: Int?
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: DS.Space.xs) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
                if let count {
                    Text(count.formatted()).font(DS.Font.numericCaption)
                        .foregroundStyle(isOn ? DS.Color.textOnFill.opacity(0.85) : DS.Color.textSecondary)
                }
            }
            .font(DS.Font.callout)
            .padding(DS.Inset.button)
            .foregroundStyle(isOn ? DS.Color.textOnFill : DS.Color.textPrimary)
            .background {
                if isOn {
                    DS.shape(DS.Radius.control).fill(.tint)
                } else {
                    DS.shape(DS.Radius.control).fill(hovering ? DS.Color.surfaceRaised : DS.Color.surface)
                }
            }
            .overlay(DS.shape(DS.Radius.control).strokeBorder(isOn ? .clear : DS.Color.border, lineWidth: 1))
            .contentShape(DS.shape(DS.Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .dsAnimation(.snappy, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - Toast

/// A short confirmation with an optional action: "Moved 2,3 GB to the Trash · Undo".
struct DSToastMessage: Identifiable, Equatable {
    let id = UUID()
    var symbol = DS.Icon.success
    var tint = DS.Color.success
    let text: String
    var actionTitle: String?
    var action: (() -> Void)?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
}

/// Holds the toast currently showing. One per window; put it in the environment.
@MainActor
final class DSToastCenter: ObservableObject {
    @Published private(set) var current: DSToastMessage?
    private var dismissTask: Task<Void, Never>?

    func show(_ toast: DSToastMessage) {
        withMotion(.smooth) { current = toast }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: toast.text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(DS.Duration.toast * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        withMotion(.smooth) { current = nil }
    }
}

struct DSToastView: View {
    let toast: DSToastMessage
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: toast.symbol).foregroundStyle(toast.tint).symbolRenderingMode(.hierarchical)
            Text(toast.text).font(DS.Font.bodyEmphasized).foregroundStyle(DS.Color.textPrimary)
            if let title = toast.actionTitle, let action = toast.action {
                Divider().frame(height: DS.Space.lg)
                Button(title) {
                    action()
                    dismiss()
                }
                .buttonStyle(.dsPlain)
            }
            DSIconButton(String(localized: "Dismiss"), symbol: "xmark", action: dismiss)
        }
        .padding(DS.Inset.toast)
        .dsGlass(in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(DS.Color.border, lineWidth: 1))
        .shadow(color: DS.Color.shadow, radius: DS.Elevation.floating.shadowRadius, y: DS.Elevation.floating.shadowY)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Shows the center's toast floating at the bottom of this view.
    func dsToasts(_ center: DSToastCenter) -> some View {
        overlay(alignment: .bottom) {
            ToastHost(center: center)
        }
    }
}

private struct ToastHost: View {
    @ObservedObject var center: DSToastCenter

    var body: some View {
        ZStack {
            if let toast = center.current {
                DSToastView(toast: toast, dismiss: center.dismiss)
                    .padding(.bottom, DS.Space.xxl)
                    .dsTransition(.dsRise)
                    .id(toast.id)
            }
        }
        .dsAnimation(.smooth, value: center.current)
    }
}

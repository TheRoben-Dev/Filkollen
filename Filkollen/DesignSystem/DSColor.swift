import AppKit
import SwiftUI

/// Filkollen's design system. Every view takes colour, type, spacing, shape,
/// depth and motion from here instead of writing literals. See
/// docs/ARCHITECTURE.md › Design system and docs/design/DIRECTION.md.
enum DS {}

// MARK: - Color

extension DS {
    /// Semantic colours. Text, separators and backgrounds come from AppKit's
    /// dynamic system colours, so light, dark and Increased Contrast are free.
    /// Brand, status and category colours live in Assets.xcassets › DesignSystem
    /// with all four variants (light, dark, and both with Increased Contrast).
    enum Color {
        // Background layers, back to front.
        /// Onyx in the default dark theme, warm ivory in light. Page backgrounds use
        /// `DSBackdrop`, which adds the faint champagne glow on top of this.
        static let canvas = asset("Canvas")
        /// The sidebar and other chrome that sits a step behind the canvas.
        static let canvasSunken = asset("CanvasSunken")
        static let backgroundWindow = asset("Canvas")
        static let backgroundUnderPage = SwiftUI.Color(nsColor: .underPageBackgroundColor)
        static let backgroundContent = SwiftUI.Color(nsColor: .controlBackgroundColor)

        // Surfaces that sit on the window background (see `DS.Elevation`).
        static let surface = asset("Surface")
        static let surfaceRaised = asset("SurfaceRaised")
        static let surfaceSunken = asset("SurfaceSunken")
        static let border = asset("Border")
        static let shadow = asset("Shadow")

        // Text.
        static let textPrimary = SwiftUI.Color(nsColor: .labelColor)
        static let textSecondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let textQuaternary = SwiftUI.Color(nsColor: .quaternaryLabelColor)
        /// Text on a filled status or category colour.
        static let textOnFill = SwiftUI.Color.white
        /// Text and glyphs on a champagne fill (primary buttons, selected chips):
        /// ink on the bright dark-mode gold, white on the deep light-mode gold.
        static let textOnAccent = asset("OnAccent")

        static let separator = SwiftUI.Color(nsColor: .separatorColor)

        /// Filkollen's accent: champagne gold. Every control is tinted with it
        /// (see `DS.AccentModifier`).
        static let brand = asset("Champagne")

        // Status. Light values are at least 4.5:1 on the light window background and dark values on
        // the dark window background, so they work as text (DesignTokenTests).
        static let success = asset("Success")
        static let warning = asset("Warning")
        /// Threats, Delete Permanently and Empty Trash only. Never routine junk.
        static let danger = asset("Danger")
        static let info = asset("Info")

        private static func asset(_ name: String) -> SwiftUI.Color {
            SwiftUI.Color("DesignSystem/\(name)", bundle: .main)
        }

        static func named(_ name: String) -> SwiftUI.Color { asset(name) }
    }
}

// MARK: - Protection palette

extension DS {
    /// Calm to alert. The same layout in every state; only colour, symbol and words change.
    enum ProtectionState: CaseIterable {
        case protected, attention, threat

        var color: SwiftUI.Color {
            switch self {
            case .protected: return DS.Color.named("ProtectionSafe")
            case .attention: return DS.Color.named("ProtectionAttention")
            case .threat: return DS.Color.named("ProtectionThreat")
            }
        }

        var symbol: String {
            switch self {
            case .protected: return "checkmark.shield.fill"
            case .attention: return "exclamationmark.shield.fill"
            case .threat: return "xmark.shield.fill"
            }
        }

        var title: String {
            switch self {
            case .protected: return String(localized: "Protected")
            case .attention: return String(localized: "Needs attention")
            case .threat: return String(localized: "Threat found")
            }
        }
    }
}

// MARK: - Category families

extension DS {
    /// Category tints come in three families so hue carries meaning, not a rainbow.
    enum CategoryFamily: CaseIterable {
        /// Apps rebuild it on their own. Cool and quiet.
        case regenerates
        /// Belonged to something that's gone or done.
        case leftBehind
        /// The user's own data: warm, "have a look first".
        case yourFiles

        var title: String {
            switch self {
            case .regenerates: return String(localized: "Rebuilt automatically")
            case .leftBehind: return String(localized: "Left behind")
            case .yourFiles: return String(localized: "Your own files")
            }
        }

        var explanation: String {
            switch self {
            case .regenerates: return String(localized: "Apps recreate these when they need them, so removing them is safe. They may come back over time.")
            case .leftBehind: return String(localized: "Left over from apps, installs or devices that are gone or finished. They don't come back.")
            case .yourFiles: return String(localized: "These are your own files. Check them before you remove anything; Filkollen never picks a kept copy.")
            }
        }
    }
}

extension JunkCategory {
    var family: DS.CategoryFamily {
        switch self {
        case .systemJunk, .browserCaches, .developerJunk: return .regenerates
        case .appLeftovers, .oldInstallers, .iosBackups: return .leftBehind
        case .duplicatePhotos, .duplicateFiles, .largeFiles: return .yourFiles
        }
    }

    /// The category's tile colour, from its family.
    var dsTint: Color {
        switch self {
        case .systemJunk: return DS.Color.named("CategorySystemJunk")
        case .browserCaches: return DS.Color.named("CategoryBrowserCaches")
        case .developerJunk: return DS.Color.named("CategoryDeveloperJunk")
        case .appLeftovers: return DS.Color.named("CategoryAppLeftovers")
        case .oldInstallers: return DS.Color.named("CategoryOldInstallers")
        case .iosBackups: return DS.Color.named("CategoryIOSBackups")
        case .duplicatePhotos: return DS.Color.named("CategoryDuplicatePhotos")
        case .duplicateFiles: return DS.Color.named("CategoryDuplicateFiles")
        case .largeFiles: return DS.Color.named("CategoryLargeFiles")
        }
    }

    /// One symbol family (filled, no circled variants) for tiles and the sidebar.
    var dsSymbol: String {
        switch self {
        case .systemJunk: return "trash.fill"
        case .appLeftovers: return "shippingbox.fill"
        case .duplicatePhotos: return "photo.on.rectangle.angled"
        case .duplicateFiles: return "doc.on.doc.fill"
        case .largeFiles: return "archivebox.fill"
        case .developerJunk: return "hammer.fill"
        case .oldInstallers: return "shippingbox.and.arrow.backward.fill"
        case .iosBackups: return "iphone"
        case .browserCaches: return "globe"
        }
    }
}

// MARK: - Theme and accent

extension DS {
    /// Dark ("Noir") is Filkollen's default look; people can opt into following
    /// the system appearance in Settings › General › Appearance.
    enum Theme: String, CaseIterable, Identifiable {
        case dark, system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dark: return String(localized: "Dark")
            case .system: return String(localized: "Match System")
            }
        }

        static var current: Theme {
            Theme(rawValue: UserDefaults.standard.string(forKey: Pref.theme) ?? "") ?? .dark
        }

        /// Sets the app-wide appearance, so windows, sheets, alerts, menus and the
        /// menu bar panel all follow the theme.
        @MainActor static func apply(_ theme: Theme = .current) {
            NSApp.appearance = theme == .dark ? NSAppearance(named: .darkAqua) : nil
        }
    }

    /// Applied once at each scene root: every control is tinted champagne.
    struct AccentModifier: ViewModifier {
        func body(content: Content) -> some View {
            content.tint(DS.Color.brand)
        }
    }
}

extension View {
    func dsAccent() -> some View { modifier(DS.AccentModifier()) }
}

// MARK: - Backdrop

/// The page background: the canvas with a faint champagne glow from the top,
/// like light falling on a dark lacquered surface. Static, so it costs nothing
/// while scrolling.
struct DSBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            DS.Color.canvas
            RadialGradient(colors: [DS.Color.brand.opacity(scheme == .dark ? 0.17 : 0.08), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 720)
        }
        .accessibilityHidden(true)
    }
}

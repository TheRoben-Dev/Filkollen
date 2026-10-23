import SwiftUI

// MARK: - Radius

extension DS {
    /// Corner radius scale. Always continuous corners (`DS.shape`).
    enum Radius {
        static let badge: CGFloat = 4
        static let small: CGFloat = 6
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let card: CGFloat = 14
        static let hero: CGFloat = 20
    }

    static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: - Elevation

extension DS {
    /// Three depth levels with recipes that work in both themes.
    enum Elevation: CaseIterable {
        /// Cards, tiles, groups: a surface fill and a hairline border.
        case surface
        /// Hovered tiles, popovers, the inspector: adds a soft shadow.
        case raised
        /// Toasts and floating panels: stronger shadow.
        case floating

        var fill: SwiftUI.Color {
            switch self {
            case .surface: return DS.Color.surface
            case .raised, .floating: return DS.Color.surfaceRaised
            }
        }

        var shadowRadius: CGFloat {
            switch self {
            case .surface: return 1
            case .raised: return 8
            case .floating: return 18
            }
        }

        var shadowY: CGFloat {
            switch self {
            case .surface: return 0.5
            case .raised: return 2
            case .floating: return 6
            }
        }

        /// How much of `DS.Color.shadow` to use. Dark mode leans on the border instead.
        func shadowOpacity(_ scheme: ColorScheme) -> Double {
            switch (self, scheme) {
            case (.surface, .dark): return 0
            case (.surface, _): return 0.6
            case (.raised, .dark): return 0.5
            case (.raised, _): return 0.9
            case (.floating, _): return 1
            }
        }
    }

    struct ElevationModifier: ViewModifier {
        let level: Elevation
        let radius: CGFloat
        @Environment(\.colorScheme) private var scheme

        func body(content: Content) -> some View {
            content
                .background(level.fill, in: DS.shape(radius))
                .overlay(DS.shape(radius).strokeBorder(DS.Color.border, lineWidth: 1))
                .shadow(color: DS.Color.shadow.opacity(level.shadowOpacity(scheme)),
                        radius: level.shadowRadius, y: level.shadowY)
        }
    }
}

extension View {
    /// Fill, hairline border and shadow for a depth level. Pad the content first.
    func dsElevation(_ level: DS.Elevation = .surface, radius: CGFloat = DS.Radius.card) -> some View {
        modifier(DS.ElevationModifier(level: level, radius: radius))
    }

    /// A standard card: card padding plus the surface level.
    func dsCard(_ level: DS.Elevation = .surface, insets: EdgeInsets = DS.Inset.card) -> some View {
        padding(insets).dsElevation(level)
    }
}

// MARK: - Materials

extension DS {
    /// Where blur is allowed. Rules (DIRECTION.md › Depth and materials):
    /// - only on chrome (sidebar, toolbar, menu bar panel, sheets) and small
    ///   transient overlays (toasts);
    /// - never behind scrolling content: bottom bars are solid `.bar`;
    /// - Reduce Transparency swaps every material for a solid surface.
    enum MaterialRole {
        /// Toasts and floating controls.
        case overlay
        /// Toolbars and headers that float over static content.
        case chrome
        /// Solid bottom bars over scrolling lists.
        case bar

        var material: Material? {
            switch self {
            case .overlay: return .regularMaterial
            case .chrome: return .bar
            case .bar: return nil
            }
        }
    }

    struct MaterialModifier<S: Shape>: ViewModifier {
        let role: MaterialRole
        let shape: S
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        func body(content: Content) -> some View {
            if let material = role.material, !reduceTransparency {
                content.background(material, in: shape)
            } else {
                content.background(DS.Color.backgroundWindow, in: shape)
            }
        }
    }
}

extension View {
    /// The background for a material role, with the Reduce Transparency fallback built in.
    func dsMaterial(_ role: DS.MaterialRole) -> some View {
        modifier(DS.MaterialModifier(role: role, shape: Rectangle()))
    }

    func dsMaterial<S: Shape>(_ role: DS.MaterialRole, in shape: S) -> some View {
        modifier(DS.MaterialModifier(role: role, shape: shape))
    }

    /// Liquid Glass on macOS 26 and later for floating controls; the material
    /// role's fallback everywhere else. Content inside stays solid and legible.
    @ViewBuilder
    func dsGlass<S: Shape>(in shape: S, fallback: DS.MaterialRole = .overlay) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            modifier(DS.GlassModifier(shape: shape, fallback: fallback))
        } else {
            dsMaterial(fallback, in: shape)
        }
        #else
        dsMaterial(fallback, in: shape)
        #endif
    }
}

#if compiler(>=6.2)
extension DS {
    @available(macOS 26.0, *)
    struct GlassModifier<S: Shape>: ViewModifier {
        let shape: S
        let fallback: MaterialRole
        @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

        func body(content: Content) -> some View {
            if reduceTransparency {
                content.dsMaterial(fallback, in: shape)
            } else {
                content.glassEffect(.regular, in: shape)
            }
        }
    }
}
#endif

import SwiftUI

extension DS {
    /// Iconography: SF Symbols only, hierarchical rendering by default, sizes
    /// tied to text styles. Category and tool tiles come in three sizes.
    enum Icon {
        enum TileSize: CaseIterable {
            /// Sidebar rows and compact lists.
            case small
            /// List rows, cards and result tiles.
            case medium
            /// Page and sheet headers.
            case large

            var side: CGFloat {
                switch self {
                case .small: return 20
                case .medium: return 32
                case .large: return 56
                }
            }

            /// Glyph size relative to the tile, as a text style so it scales with it.
            var glyph: SwiftUI.Font {
                switch self {
                case .small: return .system(size: 11, weight: .semibold)
                case .medium: return .system(size: 16, weight: .semibold)
                case .large: return .system(size: 26, weight: .semibold)
                }
            }

            var radius: CGFloat {
                switch self {
                case .small: return DS.Radius.small - 1
                case .medium: return DS.Radius.control
                case .large: return DS.Radius.card
                }
            }
        }

        /// Symbols for actions used across screens, so the same action always
        /// has the same glyph.
        static let quickLook = "eye"
        static let revealInFinder = "arrow.right.circle"
        static let trash = "trash"
        static let restore = "arrow.uturn.backward"
        static let quarantine = "lock.shield"
        static let deletePermanently = "xmark.bin"
        static let refresh = "arrow.clockwise"
        static let info = "info.circle"
        static let warning = "exclamationmark.triangle.fill"
        static let success = "checkmark.circle.fill"
        static let scan = "sparkles"
    }
}

/// A category or tool tile: an enamelled tint with a top light and a bright
/// hairline. White glyph on category colours, ink on champagne.
/// Decorative; every use sits next to a title that says the same thing.
struct DSTile: View {
    let symbol: String
    let tint: Color
    var size: DS.Icon.TileSize = .medium

    var body: some View {
        DS.shape(size.radius)
            .fill(tint)
            .overlay(
                DS.shape(size.radius)
                    .fill(LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center))
            )
            .overlay(
                DS.shape(size.radius)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
            )
            .frame(width: size.side, height: size.side)
            .overlay(
                Image(systemName: symbol)
                    .font(size.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint == DS.Color.brand ? DS.Color.textOnAccent : DS.Color.textOnFill)
            )
            .accessibilityHidden(true)
    }
}

extension DSTile {
    init(_ category: JunkCategory, size: DS.Icon.TileSize = .medium) {
        self.init(symbol: category.dsSymbol, tint: category.dsTint, size: size)
    }
}

extension Image {
    /// The default symbol treatment: hierarchical, sized by the surrounding text style.
    func dsSymbol() -> some View {
        symbolRenderingMode(.hierarchical)
    }
}

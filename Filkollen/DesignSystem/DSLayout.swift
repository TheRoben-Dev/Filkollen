import SwiftUI

extension DS {
    /// 4-pt spacing scale. Use these for stack spacing and padding; nothing else.
    enum Space {
        static let none: CGFloat = 0
        /// Hairline gaps inside one element (title over subtitle).
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
        static let huge: CGFloat = 40
        static let giant: CGFloat = 48
    }

    /// Standard sizes for windows, columns and content.
    enum Layout {
        static let windowMinWidth: CGFloat = 940
        static let windowMinHeight: CGFloat = 620
        static let windowDefaultWidth: CGFloat = 1180
        static let windowDefaultHeight: CGFloat = 760

        static let sidebarMin: CGFloat = 200
        static let sidebarIdeal: CGFloat = 220
        static let sidebarMax: CGFloat = 260
        static let inspectorWidth: CGFloat = 280

        /// A centred column of reading text (explanations, empty states).
        static let readableWidth: CGFloat = 560
        /// Widest a page's content grows on large displays before it centres.
        static let contentMaxWidth: CGFloat = 1040

        static let menuBarWidth: CGFloat = 340
        static let sheetWidth: CGFloat = 720
        static let sheetMinHeight: CGFloat = 560
        static let settingsWidth: CGFloat = 560

        /// Minimum hit target for icon-only buttons.
        static let minHitTarget: CGFloat = 28
    }

    /// Padding per container type, so every page, card and row of the same kind matches.
    enum Inset {
        static let page = EdgeInsets(top: Space.xxl, leading: Space.xxl, bottom: Space.xxl, trailing: Space.xxl)
        static let hero = EdgeInsets(top: Space.xxxl, leading: Space.xxxl, bottom: Space.xxxl, trailing: Space.xxxl)
        static let card = EdgeInsets(top: Space.lg, leading: Space.lg, bottom: Space.lg, trailing: Space.lg)
        static let tile = EdgeInsets(top: Space.lg, leading: Space.lg, bottom: Space.lg, trailing: Space.lg)
        static let row = EdgeInsets(top: Space.sm, leading: Space.md, bottom: Space.sm, trailing: Space.md)
        static let sheet = EdgeInsets(top: Space.xxl, leading: Space.xxl, bottom: Space.xl, trailing: Space.xxl)
        static let menuBar = EdgeInsets(top: Space.md, leading: Space.md, bottom: Space.md, trailing: Space.md)
        static let bar = EdgeInsets(top: Space.md, leading: Space.xxl, bottom: Space.md, trailing: Space.xxl)
        static let toast = EdgeInsets(top: Space.sm, leading: Space.lg, bottom: Space.sm, trailing: Space.lg)
        static let badge = EdgeInsets(top: Space.xxs, leading: 6, bottom: Space.xxs, trailing: 6)
        static let button = EdgeInsets(top: 6, leading: Space.md, bottom: 6, trailing: Space.md)
        static let buttonLarge = EdgeInsets(top: 10, leading: Space.xl, bottom: 10, trailing: Space.xl)
    }
}

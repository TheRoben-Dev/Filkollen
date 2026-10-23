import SwiftUI

extension DS {
    /// The type scale. SF Pro for words, SF Pro Rounded only for the big numbers
    /// people care about, monospaced digits for every size and count so numbers
    /// don't jitter while they change.
    enum Font {
        /// The headline total on Smart Scan ("6,4 GB").
        static let display = SwiftUI.Font.system(size: 44, weight: .bold, design: .rounded).monospacedDigit()
        /// Category totals, ring percentage, page-level figures.
        static let numericLarge = SwiftUI.Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
        /// Card and tile figures.
        static let numericMedium = SwiftUI.Font.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit()

        /// Hero headings (onboarding, empty Smart Scan). 26 pt on macOS.
        static let heroTitle = SwiftUI.Font.largeTitle.weight(.bold)
        /// Page titles. 22 pt on macOS. Not rounded, like Finder and System Settings.
        static let title = SwiftUI.Font.title.weight(.semibold)
        /// Section and sheet titles. 17 pt.
        static let sectionTitle = SwiftUI.Font.title2.weight(.semibold)
        static let headline = SwiftUI.Font.headline
        static let body = SwiftUI.Font.body
        static let bodyEmphasized = SwiftUI.Font.body.weight(.medium)
        static let callout = SwiftUI.Font.callout
        static let caption = SwiftUI.Font.caption
        static let captionEmphasized = SwiftUI.Font.caption.weight(.semibold)
        /// Badges and pills. Small caps-like weight without shouting in capitals.
        static let badge = SwiftUI.Font.caption2.weight(.semibold)

        /// Sizes and counts inside running text.
        static let numeric = SwiftUI.Font.body.monospacedDigit()
        static let numericCallout = SwiftUI.Font.callout.monospacedDigit()
        static let numericCaption = SwiftUI.Font.caption.monospacedDigit()

        /// File paths: SF Mono, with middle truncation at the call site.
        static let path = SwiftUI.Font.system(.caption, design: .monospaced)
        static let pathBody = SwiftUI.Font.system(.callout, design: .monospaced)
    }
}

extension Text {
    /// A file path: monospaced, one line, truncated in the middle so the file name survives.
    func dsPath(_ font: SwiftUI.Font = DS.Font.path) -> some View {
        self.font(font)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(DS.Color.textSecondary)
    }
}

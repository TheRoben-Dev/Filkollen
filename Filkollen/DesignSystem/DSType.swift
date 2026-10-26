import SwiftUI

extension DS {
    /// The type scale. New York (the system serif) for titles and the big
    /// figures, which gives the app its quiet, editorial feel; SF Pro for
    /// everything people read or click; monospaced digits for every size and
    /// count so numbers don't jitter while they change.
    enum Font {
        /// The headline total on Smart Scan ("6,4 GB").
        static let display = SwiftUI.Font.system(size: 46, weight: .regular, design: .serif).monospacedDigit()
        /// Category totals, ring percentage, page-level figures.
        static let numericLarge = SwiftUI.Font.system(size: 28, weight: .medium, design: .serif).monospacedDigit()
        /// Card and tile figures.
        static let numericMedium = SwiftUI.Font.system(size: 20, weight: .semibold, design: .serif).monospacedDigit()

        /// Hero headings (onboarding, empty Smart Scan). 28 pt serif.
        static let heroTitle = SwiftUI.Font.system(size: 28, weight: .semibold, design: .serif)
        /// Page titles. 22 pt serif.
        static let title = SwiftUI.Font.system(.title, design: .serif).weight(.semibold)
        /// Section and sheet titles. 17 pt serif.
        static let sectionTitle = SwiftUI.Font.system(.title2, design: .serif).weight(.semibold)
        static let headline = SwiftUI.Font.headline
        /// Section labels: small, letter-spaced capitals in champagne. Pair with
        /// `.dsEyebrow()`, which adds the tracking and case.
        static let eyebrow = SwiftUI.Font.caption.weight(.semibold)
        static let body = SwiftUI.Font.body
        static let bodyEmphasized = SwiftUI.Font.body.weight(.medium)
        /// Large primary buttons (Smart Scan, Review…). 15 pt semibold.
        static let buttonLarge = SwiftUI.Font.title3.weight(.semibold)
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

extension Text {
    /// A section label: letter-spaced capitals in the accent colour.
    func dsEyebrow() -> some View {
        self.font(DS.Font.eyebrow)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(DS.Color.brand)
    }
}

extension DS {
    /// "1 item" / "12 items", localized.
    static func itemCount(_ n: Int) -> String {
        n == 1 ? String(localized: "1 item") : String(localized: "\(n) items")
    }
}

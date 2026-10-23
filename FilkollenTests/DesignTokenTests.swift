import AppKit
import XCTest
@testable import Filkollen

/// Every colour token resolves in all four appearances and meets WCAG AA.
final class DesignTokenTests: XCTestCase {
    private let appearances: [NSAppearance.Name] = [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    /// Used as text and as fills behind white text.
    private let textTokens = ["Fjord", "Success", "Warning", "Danger", "Info",
                              "ProtectionSafe", "ProtectionAttention", "ProtectionThreat"]
    private let categoryTokens = ["CategorySystemJunk", "CategoryBrowserCaches", "CategoryDeveloperJunk",
                                  "CategoryAppLeftovers", "CategoryOldInstallers", "CategoryIOSBackups",
                                  "CategoryDuplicatePhotos", "CategoryDuplicateFiles", "CategoryLargeFiles"]
    private let surfaceTokens = ["Surface", "SurfaceRaised", "SurfaceSunken", "Border", "Shadow"]

    private func resolve(_ color: NSColor, in name: NSAppearance.Name) -> NSColor {
        var resolved = color
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private func token(_ name: String) throws -> NSColor {
        try XCTUnwrap(NSColor(named: "DesignSystem/\(name)", bundle: .main), "Missing colour \(name)")
    }

    private func luminance(_ c: NSColor) -> Double {
        func channel(_ v: CGFloat) -> Double {
            let v = Double(v)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent) + 0.7152 * channel(c.greenComponent) + 0.0722 * channel(c.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testAllTokensExist() throws {
        for name in textTokens + categoryTokens + surfaceTokens {
            _ = try token(name)
        }
        XCTAssertNotNil(NSColor(named: "AccentColor", bundle: .main))
    }

    func testStatusColoursAreReadableAsText() throws {
        for name in textTokens {
            let color = try token(name)
            for appearance in appearances {
                let fg = resolve(color, in: appearance)
                let window = resolve(.windowBackgroundColor, in: appearance)
                let ratio = contrast(fg, window)
                XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(name) on window background in \(appearance.rawValue): \(ratio)")
            }
        }
    }

    func testWhiteGlyphsOnCategoryTilesMeetNonTextContrast() throws {
        let white = NSColor.white.usingColorSpace(.sRGB)!
        for name in categoryTokens {
            let color = try token(name)
            for appearance in appearances {
                let ratio = contrast(resolve(color, in: appearance), white)
                XCTAssertGreaterThanOrEqual(ratio, 4.0, "White on \(name) in \(appearance.rawValue): \(ratio)")
            }
        }
    }

    func testIncreasedContrastIsStronger() throws {
        let white = NSColor.white.usingColorSpace(.sRGB)!
        for name in textTokens {
            let color = try token(name)
            let normal = contrast(resolve(color, in: .aqua), white)
            let high = contrast(resolve(color, in: .accessibilityHighContrastAqua), white)
            XCTAssertGreaterThan(high, normal, "\(name) should gain contrast with Increased Contrast")
        }
    }

    func testCategoriesUseThreeFamilies() {
        let families = Dictionary(grouping: JunkCategory.allCases, by: \.family)
        XCTAssertEqual(families.count, 3)
        XCTAssertTrue(families.values.allSatisfy { $0.count == 3 })
        XCTAssertEqual(Set(JunkCategory.allCases.map(\.dsSymbol)).count, JunkCategory.allCases.count)
    }

    func testMotionStaysUnderFourHundredMillisecondsForUIResponses() {
        XCTAssertLessThanOrEqual(DS.Motion.snappy.response, 0.4)
        XCTAssertLessThanOrEqual(DS.Motion.smooth.response, 0.4)
    }

    func testSpacingIsOnTheFourPointGrid() {
        let scale = [DS.Space.xs, DS.Space.sm, DS.Space.md, DS.Space.lg, DS.Space.xl,
                     DS.Space.xxl, DS.Space.xxxl, DS.Space.huge, DS.Space.giant]
        XCTAssertTrue(scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }
}

import SwiftUI
import XCTest
@testable import Filkollen

/// Snapshot-style smoke tests: every core component renders a non-empty image
/// in light and dark, and the status logic that drives the badges is right.
@MainActor
final class ComponentRenderTests: XCTestCase {
    private let item = JunkItem(url: URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist"),
                                size: 4_200_000, category: .appLeftovers, group: "com.example.app",
                                detail: "Application Support", inUseBy: "Example", confidence: .low)

    private func render<V: View>(_ view: V, file: StaticString = #filePath, line: UInt = #line) {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).frame(width: 420))
            renderer.scale = 1
            guard let image = renderer.cgImage else {
                return XCTFail("No image for \(V.self) in \(scheme)", file: file, line: line)
            }
            XCTAssertGreaterThan(image.width, 0, file: file, line: line)
            XCTAssertGreaterThan(image.height, 0, file: file, line: line)
        }
    }

    func testComponentsRender() {
        render(DSFileRow(item: item, isSelected: .constant(false)))
        render(DSCategoryCard(category: .systemJunk, size: 1_000_000, count: 12, status: .needsLook(2)) {})
        render(DSScanRing(segments: DSScanSegment.segments(for: JunkCategory.smartScan, scanning: [], finished: [.systemJunk]),
                          isWorking: true, settled: false, diameter: 200) { Text("50%") })
        render(DSBanner(.warning, title: "Old database", message: "Update it"))
        render(DSEmptyState(symbol: "sparkles", title: "Nothing here"))
        render(HStack { DSBadge(.keep); DSBadge(.inUse("Safari")); DSBadge(.quarantined) })
        render(Button("Quarantine") {}.buttonStyle(.dsPrimary))
    }

    func testCategoryStatusFlagsItemsThatNeedALook() {
        let flagged = CategoryResult(category: .appLeftovers, items: [item])
        XCTAssertEqual(DSCategoryCard.Status(result: flagged, isScanning: false), .needsLook(1))
        XCTAssertEqual(DSCategoryCard.Status(result: nil, isScanning: true), .scanning)
        XCTAssertEqual(DSCategoryCard.Status(result: nil, isScanning: false), .notScanned)
        XCTAssertEqual(DSCategoryCard.Status(result: CategoryResult(category: .appLeftovers, items: []), isScanning: false), .clean)
    }

    func testScanSegmentsFillOnlyWhenFinished() {
        let segments = DSScanSegment.segments(for: [.systemJunk, .appLeftovers], scanning: [.appLeftovers],
                                              finished: [.systemJunk, .appLeftovers])
        XCTAssertEqual(segments.map(\.progress), [1, 0])
    }
}

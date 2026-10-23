import XCTest
@testable import Filkollen

final class DiskUsageTests: XCTestCase {
    func testTreemapAreasAreProportionalAndInside() {
        let sizes: [Double] = [600, 300, 200, 100, 50, 25, 25]
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)
        let rects = Treemap.layout(sizes, in: bounds)
        let total = sizes.reduce(0, +)
        for (size, rect) in zip(sizes, rects) {
            XCTAssertEqual(Double(rect.width * rect.height), size / total * 120_000, accuracy: 1)
            XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect), "\(rect)")
        }
        // No overlaps.
        for i in rects.indices { for j in rects.indices where j > i {
            XCTAssertLessThan(rects[i].intersection(rects[j]).width * rects[i].intersection(rects[j]).height, 0.01)
        } }
    }

    func testTreemapEdgeCases() {
        XCTAssertEqual(Treemap.layout([], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [])
        XCTAssertEqual(Treemap.layout([0, 0], in: CGRect(x: 0, y: 0, width: 10, height: 10)), [.zero, .zero])
        XCTAssertEqual(Treemap.layout([5], in: CGRect(x: 0, y: 0, width: 10, height: 4)), [CGRect(x: 0, y: 0, width: 10, height: 4)])
    }

    func testChildrenAreSizedLargestFirstAndSkipSymlinks() throws {
        let fx = try Fixture()
        let dir = try fx.dir("Documents/usage")
        try fx.file("big.bin", in: dir, bytes: 200_000)
        try fx.file("folder/small.bin", in: dir, bytes: 10_000)
        try fx.symlink("link", to: fx.outside, in: dir)
        let entries = DiskUsage.children(of: dir)
        XCTAssertEqual(entries.map(\.name), ["big.bin", "folder"])
        XCTAssertTrue(entries[1].isFolder)
    }
}

import XCTest
@testable import Filkollen

final class ExclusionsTests: XCTestCase {
    func testExcludesFolderAndEverythingInside() {
        let list = ["/Users/me/Projects"]
        XCTAssertTrue(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Projects"), in: list))
        XCTAssertTrue(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Projects/a/b.zip"), in: list))
        XCTAssertFalse(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/ProjectsOld/a"), in: list))
        XCTAssertFalse(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Downloads/a"), in: list))
    }
}

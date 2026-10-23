import XCTest
@testable import Filkollen

final class DiagnosticsTests: XCTestCase {
    func testScrubsHomeAndUserName() {
        let text = "Refused /Users/roben/Library/Caches/x for roben"
        XCTAssertEqual(Diagnostics.scrub(text, home: "/Users/roben", user: "roben"),
                       "Refused ~/Library/Caches/x for <user>")
    }

    func testReportHasNoHomePath() {
        let report = Diagnostics.report(since: 60)
        XCTAssertTrue(report.hasPrefix("Filkollen "))
        XCTAssertFalse(report.contains(NSHomeDirectory()))
    }
}

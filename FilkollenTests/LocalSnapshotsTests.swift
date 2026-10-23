import XCTest
@testable import Filkollen

final class LocalSnapshotsTests: XCTestCase {
    func testParsesTmutilOutput() {
        let text = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-23-101500.local
        com.apple.TimeMachine.2026-10-23-111503.local
        garbage line
        """
        let list = LocalSnapshots.parse(text)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.name, "com.apple.TimeMachine.2026-10-23-111503.local", "newest first")
        XCTAssertNotNil(list.first?.date)
    }
}

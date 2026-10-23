import XCTest
@testable import Filkollen

final class CleanupHistoryTests: XCTestCase {
    private var fx: Fixture!
    private var history: CleanupHistory!

    override func setUpWithError() throws {
        fx = try Fixture()
        history = CleanupHistory(url: fx.root.appendingPathComponent("history.json"), safety: fx.safety)
    }
    override func tearDown() { fx = nil }

    /// Cleans through the real Cleaner, with a fake Trash inside the fixture.
    private func clean(_ urls: [URL]) throws -> (Cleaner.Outcome, [JunkItem]) {
        let trash = try fx.dir(".Trash")
        let items = urls.map { JunkItem(url: $0, size: 16, category: .systemJunk, group: "g") }
        let outcome = Cleaner.moveToTrash(items, safety: fx.safety, isRunning: { _ in false }, trash: { url in
            let dest = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        })
        return (outcome, items)
    }

    func testRecordAndPutBackEverything() throws {
        let a = try fx.file("Library/Caches/com.x.a/blob")
        let b = try fx.file("Library/Caches/com.x.b/blob")
        let (outcome, items) = try clean([a, b])
        let record = try XCTUnwrap(history.record(outcome, items: items, source: "System Junk"))
        XCTAssertEqual(record.items.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))

        XCTAssertTrue(history.putBack(record.id).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.path))
        XCTAssertTrue(history.records()[0].restorable.isEmpty)
        XCTAssertEqual(history.totals().items, 2)
    }

    func testPutBackOneAndReportConflicts() throws {
        let a = try fx.file("Library/Caches/com.x.a/blob")
        let b = try fx.file("Library/Logs/old.log")
        let (outcome, items) = try clean([a, b])
        let record = try XCTUnwrap(history.record(outcome, items: items, source: "Smart Scan"))

        XCTAssertTrue(history.putBack(record.id, only: [a.path]).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.path))

        // Something new took b's place: don't overwrite it.
        try fx.file("Library/Logs/old.log", contents: Data("new".utf8))
        XCTAssertEqual(history.putBack(record.id), [b.path: .originalExists])
    }

    func testEmptiedTrashIsReported() throws {
        let a = try fx.file("Library/Caches/com.x.a/blob")
        let (outcome, items) = try clean([a])
        let record = try XCTUnwrap(history.record(outcome, items: items, source: "System Junk"))
        try FileManager.default.removeItem(atPath: record.items[0].trashed)
        XCTAssertEqual(history.putBack(record.id), [a.path: .goneFromTrash])
    }

    func testNeverPutsBackIntoAProtectedPlace() throws {
        // A tampered history entry pointing into the Keychains folder is refused.
        let trashed = try fx.file(".Trash/login.keychain-db")
        let outcome = Cleaner.Outcome(trashed: [], trashLocations: [fx.home.appendingPathComponent("Library/Keychains/login.keychain-db"): trashed])
        let record = try XCTUnwrap(history.record(outcome, items: [], source: "x"))
        guard case .refused = history.putBack(record.id).values.first else { return XCTFail("must refuse") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashed.path))
    }

    func testKeepsTheNewest() throws {
        let trashed = try fx.file(".Trash/x")
        let outcome = Cleaner.Outcome(trashLocations: [fx.home.appendingPathComponent("Library/Caches/x"): trashed])
        for i in 0..<(CleanupHistory.limit + 5) {
            history.record(outcome, items: [], source: "\(i)", now: Date(timeIntervalSince1970: Double(i)))
        }
        let all = history.records()
        XCTAssertEqual(all.count, CleanupHistory.limit)
        XCTAssertEqual(all.first?.source, "\(CleanupHistory.limit + 4)")
    }
}

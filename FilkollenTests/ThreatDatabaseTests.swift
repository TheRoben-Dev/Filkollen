import XCTest
@testable import Filkollen

final class ThreatDatabaseTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private let digests = (1...50).map { ThreatDatabase.Digest(UInt64($0), 0, 0, UInt64($0) * 3) }

    private func makeDB() -> ThreatDatabase {
        ThreatDatabase(storeURL: fx.home.appendingPathComponent("Library/Application Support/db.bin"))
    }

    func testStoreThenLoadPassesAndFindsDigests() throws {
        let db = makeDB()
        try FileManager.default.createDirectory(at: db.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try db.store(digests)
        try db.load()
        XCTAssertTrue(db.contains(digests[17]))
        XCTAssertFalse(db.contains(ThreatDatabase.Digest(999, 0, 0, 0)))
        XCTAssertEqual(db.count, 50)
    }

    func testTamperedTableFailsChecksum() throws {
        let db = makeDB()
        try FileManager.default.createDirectory(at: db.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try db.store(digests)
        // Swap in a different (still sorted, still whole) table without updating the sidecar.
        let other = Array(digests.dropLast())
        try other.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: db.storeURL)
        XCTAssertThrowsError(try db.load()) { XCTAssertEqual($0 as? ThreatDatabase.IntegrityError, .checksumMismatch) }
    }

    func testValidateCatchesTruncationAndOrder() {
        let good = digests.withUnsafeBufferPointer { Data(buffer: $0) }
        XCTAssertNil(ThreatDatabase.validate(good, sidecar: nil))
        XCTAssertEqual(ThreatDatabase.validate(good.dropLast(5), sidecar: nil), .truncated)
        XCTAssertEqual(ThreatDatabase.validate(Data(), sidecar: nil), .empty)
        let shuffled = Array(digests.reversed()).withUnsafeBufferPointer { Data(buffer: $0) }
        XCTAssertEqual(ThreatDatabase.validate(shuffled, sidecar: nil), .unsorted)
        let dupes = (digests + [digests.last!]).withUnsafeBufferPointer { Data(buffer: $0) }
        XCTAssertEqual(ThreatDatabase.validate(dupes, sidecar: nil), .unsorted)
    }
}

final class ProtectionFreshnessTests: XCTestCase {
    func testStaleAfterAWeek() {
        let now = Date()
        XCTAssertTrue(ProtectionModel.isStale(nil, now: now))
        XCTAssertFalse(ProtectionModel.isStale(now.addingTimeInterval(-6 * 86_400), now: now))
        XCTAssertTrue(ProtectionModel.isStale(now.addingTimeInterval(-8 * 86_400), now: now))
    }

    func testClamAVSignatureDatePicksNewestFile() throws {
        let fx = try Fixture()
        let dir = try fx.dir("clamav")
        let old = try fx.file("main.cvd", in: dir, modified: Date().addingTimeInterval(-30 * 86_400))
        let new = try fx.file("daily.cld", in: dir, modified: Date().addingTimeInterval(-2 * 86_400))
        _ = old
        let date = try XCTUnwrap(ClamAV.signaturesDate(in: [dir.path, "/nonexistent"]))
        let expected = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: new.path)[.modificationDate] as? Date)
        XCTAssertEqual(date.timeIntervalSince1970, expected.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(ClamAV.signaturesDate(in: ["/nonexistent"]))
    }
}

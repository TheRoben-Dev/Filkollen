import XCTest
@testable import Filkollen

final class QuarantineTests: XCTestCase {
    private var fx: Fixture!
    private var dir: URL!

    override func setUpWithError() throws {
        fx = try Fixture()
        dir = try fx.dir("Library/Application Support/Filkollen/Quarantine")
    }
    override func tearDown() { fx = nil }

    private func threat(_ name: String = "evil.command", contents: String = "#!/bin/sh\necho hi\n") throws -> Threat {
        let url = try fx.file("Downloads/\(name)", contents: Data(contents.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return Threat(url: url, size: Int64(contents.utf8.count), engine: .malwareBazaar, identifier: String(repeating: "a", count: 64))
    }

    func testIsolateLocksTheFileAndRecordsItsHash() throws {
        let t = try threat()
        let entry = try Quarantine.isolate(t, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: t.url.path))
        let perms = try FileManager.default.attributesOfItem(atPath: entry.storedPath)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o400)
        XCTAssertEqual(entry.originalPermissions, 0o755)
        XCTAssertEqual(entry.sha256?.count, 64)
        XCTAssertEqual(entry.sha256, Quarantine.sha256(of: URL(fileURLWithPath: entry.storedPath)))
        XCTAssertEqual(Quarantine.entries(in: dir), [entry])
        XCTAssertFalse(entry.isMissing)
    }

    func testRestorePutsItBackWithItsPermissions() throws {
        let t = try threat()
        let entry = try Quarantine.isolate(t, in: dir)
        try Quarantine.restore(entry, in: dir)
        let perms = try FileManager.default.attributesOfItem(atPath: t.url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o755)
        XCTAssertTrue(Quarantine.entries(in: dir).isEmpty)
    }

    func testRestoreRefusesToOverwrite() throws {
        let t = try threat()
        let entry = try Quarantine.isolate(t, in: dir)
        try fx.file("Downloads/evil.command", contents: Data("new".utf8))
        XCTAssertThrowsError(try Quarantine.restore(entry, in: dir))
        XCTAssertEqual(Quarantine.entries(in: dir).count, 1)
    }

    func testDeleteOnlyRemovesSlotsInsideTheQuarantineFolder() throws {
        let entry = try Quarantine.isolate(try threat(), in: dir)
        let victim = try fx.file("Documents/keep/me.txt")
        // A tampered manifest entry pointing elsewhere must not delete anything.
        let forged = Quarantine.Entry(id: UUID(), originalPath: "/x", storedPath: victim.path, engine: .clamAV,
                                      identifier: "x", size: 1, date: Date(), originalPermissions: 0o644)
        XCTAssertThrowsError(try Quarantine.delete(forged, in: dir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim.path))

        try Quarantine.delete(entry, in: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.storedPath))
        XCTAssertTrue(Quarantine.entries(in: dir).isEmpty)
    }

    func testOlderThanAndExport() throws {
        let old = try Quarantine.isolate(try threat("a.sh"), in: dir, now: Date().addingTimeInterval(-40 * 86_400))
        _ = try Quarantine.isolate(try threat("b.sh"), in: dir)
        XCTAssertEqual(Quarantine.entries(olderThan: Date().addingTimeInterval(-30 * 86_400), in: dir), [old])

        let report = fx.home.appendingPathComponent("Desktop/report.json")
        try Quarantine.exportReport(to: report, in: dir)
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: report)) as? [[String: Any]]
        XCTAssertEqual(json?.count, 2)
        XCTAssertNotNil(json?.first?["sha256"])
    }

    func testOldManifestWithoutHashStillLoads() throws {
        let legacy = """
        [{"id":"\(UUID().uuidString)","originalPath":"/a","storedPath":"/b","engine":"ClamAV","identifier":"x",
          "size":1,"date":0,"originalPermissions":420}]
        """
        try Data(legacy.utf8).write(to: dir.appendingPathComponent("manifest.json"))
        let entries = Quarantine.entries(in: dir)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].sha256)
        XCTAssertTrue(entries[0].isMissing)
    }
}

import XCTest
@testable import Filkollen

final class DownloadsWatcherTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private let evil = Data("not really malware, just a known hash".utf8)

    private func database(containing data: Data...) throws -> ThreatDatabase {
        let db = ThreatDatabase(storeURL: fx.root.appendingPathComponent("db.bin"))
        let digests = try data.map { d -> ThreatDatabase.Digest in
            let url = fx.root.appendingPathComponent(UUID().uuidString)
            try d.write(to: url)
            return try XCTUnwrap(MalwareScanner.sha256(url))
        }
        try db.store(digests.sorted())
        return db
    }

    func testEntriesSkipPartialDownloadsAndInertFiles() throws {
        try fx.file("Downloads/tool.dmg")
        try fx.file("Downloads/tool.dmg.crdownload")
        try fx.file("Downloads/photo.jpg")
        try fx.dir("Downloads/Folder")
        let names = DownloadsWatcher.entries(in: fx.home.appendingPathComponent("Downloads")).map(\.url.lastPathComponent)
        XCTAssertEqual(names, ["tool.dmg"])
    }

    func testCheckNowReportsOnlyNewMatches() throws {
        let db = try database(containing: evil)
        let found = LockedBox<[Threat]>([])
        let watcher = DownloadsWatcher(folder: fx.home.appendingPathComponent("Downloads"), database: db) { found.value += $0 }

        try fx.file("Downloads/invoice.pkg", contents: evil)
        try fx.file("Downloads/fine.zip", contents: Data("harmless".utf8))
        watcher.checkNow()
        XCTAssertEqual(found.value.map(\.name), ["invoice.pkg"])
        XCTAssertEqual(found.value.first?.engine, .malwareBazaar)

        // Already checked and unchanged: not reported again.
        watcher.checkNow()
        XCTAssertEqual(found.value.count, 1)
        // The watcher only reports; the file stays where it is.
        XCTAssertTrue(FileManager.default.fileExists(atPath: fx.home.appendingPathComponent("Downloads/invoice.pkg").path))
    }

    func testNoDatabaseMeansNoReports() throws {
        let db = ThreatDatabase(storeURL: fx.root.appendingPathComponent("missing.bin"))
        let found = LockedBox<[Threat]>([])
        let watcher = DownloadsWatcher(folder: fx.home.appendingPathComponent("Downloads"), database: db) { found.value += $0 }
        try fx.file("Downloads/invoice.pkg", contents: evil)
        watcher.checkNow()
        XCTAssertTrue(found.value.isEmpty)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ value: T) { _value = value }
    var value: T {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

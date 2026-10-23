import XCTest
@testable import Filkollen

final class CleanerTests: XCTestCase {
    private var fx: Fixture!

    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    /// Stands in for the real Trash: moves into a folder inside the fixture.
    private func fakeTrash() throws -> (Cleaner.Trasher, URL) {
        let bin = try fx.dir("bin", in: fx.root)
        let trash: Cleaner.Trasher = { url in
            let dest = bin.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: dest)
            return dest
        }
        return (trash, bin)
    }

    private func item(_ url: URL, size: Int64 = 100) -> JunkItem {
        JunkItem(url: url, size: size, category: .systemJunk, group: "test")
    }

    /// Items as AppModel hands them over: screened and with their scan-time location recorded.
    private func scanned(_ urls: [URL]) -> [JunkItem] {
        AppModel.screened(urls.map { item($0) }, category: .systemJunk, safety: fx.safety)
    }

    func testTrashesAllowedItemsAndReportsBytes() throws {
        let (trash, bin) = try fakeTrash()
        let a = try fx.dir("Library/Caches/com.vendor.a")
        let b = try fx.file("Library/Logs/b.log")
        let outcome = Cleaner.moveToTrash(scanned([a, b]), safety: fx.safety, trash: trash)

        XCTAssertEqual(outcome.trashed, [a, b])
        XCTAssertEqual(outcome.trashedBytes, 200)
        XCTAssertTrue(outcome.failures.isEmpty)
        XCTAssertEqual(outcome.trashLocations.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: bin.path).count, 2)
    }

    func testScreeningDropsRefusedItems() throws {
        let ok = try fx.dir("Library/Caches/com.vendor.a")
        let apple = try fx.dir("Library/Caches/com.apple.finder")
        let keychain = try fx.file("Library/Keychains/login.keychain-db")
        let kept = scanned([ok, apple, keychain])
        XCTAssertEqual(kept.map(\.url), [ok])
        XCTAssertNotNil(kept.first?.resolvedPath)
    }

    func testRefusesProtectedItemsAtDeleteTimeEvenIfAScannerReturnedThem() throws {
        let (trash, _) = try fakeTrash()
        let keychain = try fx.file("Library/Keychains/login.keychain-db")
        let outside = try fx.file("x", in: fx.outside)
        let outcome = Cleaner.moveToTrash([item(keychain), item(outside)], safety: fx.safety, trash: trash)

        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertTrue(outcome.failures.allSatisfy { $0.reason.hasPrefix("Protected") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: keychain.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testFolderSwappedForSymlinkAfterScanIsRefused() throws {
        let (trash, _) = try fakeTrash()
        let fm = FileManager.default
        let victim = try fx.file("victim/data", in: fx.outside)
        let parent = try fx.dir("Library/Caches/vendor")
        let target = try fx.file("Library/Caches/vendor/data")
        let items = scanned([target])
        XCTAssertEqual(items.count, 1)

        // Between scan and clean, the parent is replaced by a link to somewhere else.
        try fm.removeItem(at: parent)
        try fm.createSymbolicLink(at: parent, withDestinationURL: victim.deletingLastPathComponent())
        let outcome = Cleaner.moveToTrash(items, safety: fx.safety, trash: trash)

        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertTrue(fm.fileExists(atPath: victim.path))
    }

    func testLinkRetargetedWithinHomeAfterScanIsRefused() throws {
        let (trash, _) = try fakeTrash()
        let fm = FileManager.default
        let parent = try fx.dir("Library/Caches/vendor")
        let target = try fx.file("Library/Caches/vendor/data")
        let elsewhere = try fx.file("Library/Caches/other/data")
        let items = scanned([target])

        try fm.removeItem(at: parent)
        try fm.createSymbolicLink(at: parent, withDestinationURL: elsewhere.deletingLastPathComponent())
        let outcome = Cleaner.moveToTrash(items, safety: fx.safety, trash: trash)

        XCTAssertEqual(outcome.failures.first?.reason, "Its location changed since the scan")
        XCTAssertTrue(fm.fileExists(atPath: elsewhere.path))
    }

    func testVanishedItemsCountAsDone() throws {
        let (trash, _) = try fakeTrash()
        let gone = fx.home.appendingPathComponent("Library/Caches/gone")
        let outcome = Cleaner.moveToTrash([item(gone)], safety: fx.safety, trash: trash)
        XCTAssertEqual(outcome.trashed, [gone])
        XCTAssertEqual(outcome.alreadyGone, 1)
        XCTAssertEqual(outcome.trashedBytes, 0)
        XCTAssertEqual(CleanupSummary(outcome).trashedCount, 0)
    }

    func testDanglingSymlinkCanBeTrashed() throws {
        let (trash, _) = try fakeTrash()
        let link = try fx.symlink("Library/Caches/dangling", to: fx.home.appendingPathComponent("Library/Caches/nowhere"))
        let outcome = Cleaner.moveToTrash(scanned([link]), safety: fx.safety, trash: trash)
        XCTAssertEqual(outcome.trashed, [link])
        XCTAssertEqual(outcome.alreadyGone, 0)
    }

    func testFailuresAreReportedPerItemAsPartialSuccess() throws {
        let ok = try fx.file("Library/Caches/ok")
        let locked = try fx.file("Library/Caches/locked")
        let trash: Cleaner.Trasher = { url in
            if url.lastPathComponent == "locked" {
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
            try FileManager.default.removeItem(at: url)
            return nil
        }
        let outcome = Cleaner.moveToTrash(scanned([ok, locked]), safety: fx.safety, trash: trash)

        XCTAssertTrue(outcome.isPartial)
        XCTAssertEqual(outcome.trashed, [ok])
        XCTAssertEqual(outcome.failures, [Cleaner.Failure(url: locked, reason: "Permission denied")])
        let summary = CleanupSummary(outcome)
        XCTAssertEqual(summary.trashedCount, 1)
        XCTAssertEqual(summary.failures.count, 1)
    }

    func testErrorDescriptions() {
        XCTAssertEqual(Cleaner.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(EBUSY))), "In use")
        XCTAssertEqual(Cleaner.describe(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))), "Permission denied")
        XCTAssertEqual(Cleaner.describe(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)),
                       "It disappeared before it could be moved")
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 3328,
                              userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertEqual(Cleaner.describe(wrapped), "Locked or permission denied")
    }
}

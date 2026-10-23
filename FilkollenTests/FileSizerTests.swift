import XCTest
@testable import Filkollen

final class FileSizerTests: XCTestCase {
    private var fx: Fixture!
    private let fm = FileManager.default
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testAllocatedSizeIsAtLeastLogicalSize() throws {
        let file = try fx.file("Library/Caches/a/blob", bytes: 10_000)
        let m = FileSizer.measure(file)
        XCTAssertGreaterThanOrEqual(m.allocated, 10_000)
        XCTAssertEqual(m.reclaimable, m.allocated)
        XCTAssertEqual(FileSizer.measure(file.deletingLastPathComponent()), m)
    }

    func testHardLinksInsideTheFolderAreCountedOnce() throws {
        let dir = try fx.dir("Library/Caches/links")
        let a = try fx.file("a", in: dir, bytes: 50_000)
        try fm.linkItem(at: a, to: dir.appendingPathComponent("b"))
        let single = FileSizer.fileSize(a)
        let m = FileSizer.measure(dir)
        XCTAssertEqual(m.allocated, single)
        XCTAssertEqual(m.reclaimable, single, "every link is inside, so deleting the folder frees it")
    }

    func testHardLinkWithALinkOutsideFreesNothing() throws {
        let dir = try fx.dir("Library/Caches/links")
        let a = try fx.file("a", in: dir, bytes: 50_000)
        try fm.linkItem(at: a, to: fx.outside.appendingPathComponent("keep"))
        let m = FileSizer.measure(dir)
        XCTAssertGreaterThan(m.allocated, 0)
        XCTAssertEqual(m.reclaimable, 0)
    }

    func testSymlinksCountAsNothing() throws {
        let target = try fx.file("Library/Caches/real/blob", bytes: 50_000)
        let link = try fx.symlink("Library/Caches/link", to: target.deletingLastPathComponent())
        XCTAssertEqual(FileSizer.measure(link), FileSizer.Measurement())
    }

    func testAPFSClonesAreNotReclaimable() throws {
        let original = try fx.file("original.bin", in: fx.outside, bytes: 200_000)
        let dir = try fx.dir("Library/Caches/clones")
        let clone = dir.appendingPathComponent("clone.bin")
        try fm.copyItem(at: original, to: clone) // clonefile on APFS
        guard (try clone.resourceValues(forKeys: [.mayShareFileContentKey])).mayShareFileContent == true else {
            throw XCTSkip("Not on APFS, no clone was made")
        }
        let m = FileSizer.measure(dir)
        XCTAssertGreaterThan(m.allocated, 0)
        XCTAssertEqual(m.reclaimable, 0)
    }

    func testDuplicateThatIsACloneOfTheKeeperFreesNothing() throws {
        let photo = Data((0..<90_000).map { UInt8(truncatingIfNeeded: $0 &* 13) })
        let original = try fx.file("Pictures/IMG_1.jpg", contents: photo)
        let clone = fx.home.appendingPathComponent("Downloads/IMG_1.jpg")
        try fm.copyItem(at: original, to: clone)
        let copy = try fx.file("Desktop/IMG_1.jpg", contents: photo)
        guard (try clone.resourceValues(forKeys: [.mayShareFileContentKey])).mayShareFileContent == true else {
            throw XCTSkip("Not on APFS, no clone was made")
        }
        let old = Date().addingTimeInterval(-86_400 * 10)
        try fm.setAttributes([.creationDate: old], ofItemAtPath: original.path)
        try fm.setAttributes([.creationDate: Date()], ofItemAtPath: clone.path)
        try fm.setAttributes([.creationDate: Date()], ofItemAtPath: copy.path)

        let items = DuplicatePhotoScanner(context: fx.context()).scan(progress: { _ in })
        let byFolder = Dictionary(uniqueKeysWithValues: items.map { ($0.url.deletingLastPathComponent().lastPathComponent, $0) })
        XCTAssertEqual(byFolder["Pictures"]?.isKeeper, true)
        XCTAssertEqual(byFolder["Downloads"]?.reclaimableSize, 0)
        XCTAssertTrue(byFolder["Downloads"]?.detail.contains("clone") == true)
        XCTAssertEqual(byFolder["Desktop"]?.reclaimableSize, byFolder["Desktop"]?.size)
    }
}

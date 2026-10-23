import XCTest
@testable import Filkollen

private let noProgress: @Sendable (String) -> Void = { _ in }

final class DuplicateFilesTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private func data(_ bytes: Int, seed: Int = 3) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ seed) })
    }

    private func setCreated(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: url.path)
    }

    func testKeeperPrefersTheCopyWithItsLivePhotoVideo() throws {
        let photo = data(90_000)
        let lone = try fx.file("Downloads/IMG_0042.HEIC", contents: photo)
        let paired = try fx.file("Pictures/Import/IMG_0042.HEIC", contents: photo)
        try fx.file("Pictures/Import/IMG_0042.MOV", contents: data(5000, seed: 9))
        try setCreated(lone, daysAgo: 40)  // older, but on its own
        try setCreated(paired, daysAgo: 2)

        let items = DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress)
        let keeper = try XCTUnwrap(items.first(where: \.isKeeper))
        XCTAssertEqual(keeper.url.deletingLastPathComponent().lastPathComponent, "Import")
        XCTAssertTrue(keeper.detail.contains("Live Photo video"))
        // The video itself is never part of a photo duplicate group.
        XCTAssertFalse(items.contains { $0.url.pathExtension == "MOV" })
    }

    func testRawCompanionIsNotedOnARemovableCopy() throws {
        let jpeg = data(70_000)
        let keep = try fx.file("Pictures/DSC_1.JPG", contents: jpeg)
        try fx.file("Pictures/DSC_1.NEF", contents: data(9000, seed: 5))
        let copy = try fx.file("Desktop/DSC_1.JPG", contents: jpeg)
        try fx.file("Desktop/DSC_1.NEF", contents: data(9000, seed: 5))
        try setCreated(keep, daysAgo: 10)
        try setCreated(copy, daysAgo: 1)

        let items = DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress)
        let removable = try XCTUnwrap(items.first { $0.url.lastPathComponent == "DSC_1.JPG" && !$0.isKeeper })
        XCTAssertTrue(removable.detail.contains("RAW original"))
        XCTAssertTrue(removable.detail.contains("stays"))
    }

    func testFilesModeFindsLargeNonImagesAndPreselectsNothing() throws {
        let video = data(2_000_000)
        try fx.file("Movies/clip.mp4", contents: video)
        try fx.file("Downloads/clip (1).mp4", contents: video)
        try fx.file("Documents/a.pdf", contents: data(4000))      // below the floor
        try fx.file("Downloads/a.pdf", contents: data(4000))
        try fx.file("Documents/big.jpg", contents: video)         // images belong to photo mode
        try fx.file("Downloads/big.jpg", contents: video)

        let items = DuplicatePhotoScanner(context: fx.context(), mode: .files).scan(progress: noProgress)
        XCTAssertEqual(Set(items.map(\.url.pathExtension)), ["mp4"])
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.category == .duplicateFiles && !$0.isSelected })
        XCTAssertEqual(items.filter(\.isKeeper).count, 1)
    }

    func testFilesModeSkipsDependencyFolders() throws {
        let blob = data(1_200_000)
        try fx.file("Documents/app/node_modules/x/lib.wasm", contents: blob)
        try fx.file("Documents/other/node_modules/x/lib.wasm", contents: blob)
        XCTAssertTrue(DuplicatePhotoScanner(context: fx.context(), mode: .files).scan(progress: noProgress).isEmpty)
    }

    func testFilesModeSmallFloorIsInjectable() throws {
        try fx.file("Documents/a.txt", contents: data(4000))
        try fx.file("Downloads/a.txt", contents: data(4000))
        let items = DuplicatePhotoScanner(context: fx.context(), mode: .files, minFileBytes: 1000).scan(progress: noProgress)
        XCTAssertEqual(items.count, 2)
    }
}

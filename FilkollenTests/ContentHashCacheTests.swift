import XCTest
@testable import Filkollen

final class ContentHashCacheTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testCachesAcrossInstancesAndInvalidatesOnChange() throws {
        let store = fx.root.appendingPathComponent("cache.plist")
        let file = try fx.file("Pictures/a.jpg", bytes: 200_000)
        let id = try XCTUnwrap(FileIdentity(file))

        let first = ContentHashCache(url: store)
        let full = first.hash(.full, of: file, identity: id)
        XCTAssertNotNil(full)
        XCTAssertEqual(first.misses, 1)
        first.save(keeping: [id.key])

        let second = ContentHashCache(url: store)
        XCTAssertEqual(second.hash(.full, of: file, identity: id), full)
        XCTAssertEqual(second.hits, 1)
        XCTAssertEqual(second.misses, 0)

        // Rewritten with different bytes and a new mtime: the cached hash must not be reused.
        try Data(repeating: 9, count: 200_000).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        let changed = try XCTUnwrap(FileIdentity(file))
        XCTAssertNotEqual(second.hash(.full, of: file, identity: changed), full)
    }

    func testTiersHashTheRightBytes() throws {
        var bytes = Data(repeating: 1, count: 300_000)
        let file = try fx.file("x", in: fx.outside, contents: bytes)
        let size = Int64(bytes.count)
        let head = ContentHashCache.compute(.head, of: file, size: size)
        let tail = ContentHashCache.compute(.tail, of: file, size: size)
        XCTAssertEqual(head, tail, "uniform file: first and last 64 KB are identical")

        bytes[bytes.count - 1] = 2
        try bytes.write(to: file)
        XCTAssertEqual(ContentHashCache.compute(.head, of: file, size: size), head)
        XCTAssertNotEqual(ContentHashCache.compute(.tail, of: file, size: size), tail)
    }

    func testSaveDropsFilesNotSeen() throws {
        let store = fx.root.appendingPathComponent("cache.plist")
        let a = try fx.file("a", in: fx.outside, bytes: 1000)
        let b = try fx.file("b", in: fx.outside, bytes: 1000)
        let cache = ContentHashCache(url: store)
        let ia = try XCTUnwrap(FileIdentity(a)), ib = try XCTUnwrap(FileIdentity(b))
        _ = cache.hash(.head, of: a, identity: ia)
        _ = cache.hash(.head, of: b, identity: ib)
        cache.save(keeping: [ia.key])

        let reloaded = ContentHashCache(url: store)
        _ = reloaded.hash(.head, of: b, identity: ib)
        XCTAssertEqual(reloaded.misses, 1)
    }

    func testParallelMapKeepsOrder() {
        XCTAssertEqual(parallelMap(Array(0..<1000)) { $0 * 2 }, Array(0..<1000).map { $0 * 2 })
    }
}

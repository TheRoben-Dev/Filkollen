import XCTest
@testable import Filkollen

final class ExclusionsTests: XCTestCase {
    func testExcludesFolderAndEverythingInside() {
        let list = ["/Users/me/Projects"]
        XCTAssertTrue(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Projects"), in: list))
        XCTAssertTrue(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Projects/a/b.zip"), in: list))
        XCTAssertFalse(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/ProjectsOld/a"), in: list))
        XCTAssertFalse(Exclusions.isExcluded(URL(fileURLWithPath: "/Users/me/Downloads/a"), in: list))
    }

    func testAddAppendsOnceAndIsCaseInsensitive() {
        let saved = Pref.defaults.string(forKey: Pref.excludedPaths)
        defer { Pref.defaults.set(saved, forKey: Pref.excludedPaths) }
        Pref.defaults.set("", forKey: Pref.excludedPaths)
        let folder = URL(fileURLWithPath: "/tmp/filkollen-ignore-\(UUID().uuidString)")
        Exclusions.add(folder)
        Exclusions.add(folder)
        Exclusions.add(folder.appendingPathComponent("child"))
        XCTAssertEqual(Exclusions.paths.count, 1)
        XCTAssertTrue(Exclusions.isExcluded(URL(fileURLWithPath: folder.path.uppercased() + "/x")))
    }
}

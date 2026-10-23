import XCTest
@testable import Filkollen

final class DeveloperScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private func populate() throws {
        try fx.file("Library/Developer/Xcode/Archives/2026-01-02/App 1.xcarchive/Info.plist", bytes: 5_000)
        try fx.file("Library/Developer/Xcode/iOS DeviceSupport/17.4 (21E219)/Symbols/x", bytes: 20_000)
        try fx.file("Library/Developer/Xcode/iOS DeviceSupport/18.0 (22A3354)/Symbols/x", bytes: 20_000)
        try fx.file("Library/Developer/CoreSimulator/Caches/dyld/x", bytes: 9_000)
        try fx.file("Library/Caches/Homebrew/downloads/x.tar.gz", bytes: 9_000)
        try fx.file(".npm/_cacache/content-v2/x", bytes: 9_000)
        try fx.file(".cargo/registry/cache/index/x.crate", bytes: 9_000)
        try fx.file(".cargo/bin/cargo", bytes: 9_000) // tools, never touched
        try fx.file("go/pkg/mod/github.com/x/y.go", bytes: 9_000)
        try fx.file(".gradle/caches/x", bytes: 9_000)
    }

    func testFindsEachSourceWithAnExplanation() throws {
        try populate()
        let items = DeveloperScanner(context: fx.context()).scan(progress: { _ in })
        let groups = Set(items.map(\.group))
        XCTAssertEqual(groups, ["Xcode Archives", "Device Support", "Simulator Caches", "Homebrew", "npm", "Cargo", "Go", "Gradle"])
        XCTAssertEqual(items.filter { $0.group == "Device Support" }.count, 2, "one item per OS version")
        XCTAssertTrue(items.allSatisfy { !$0.detail.isEmpty })
        XCTAssertFalse(items.contains { $0.url.path.contains(".cargo/bin") })
    }

    func testArchivesAndGoModulesAreNotPreselected() throws {
        try populate()
        let items = DeveloperScanner(context: fx.context()).scan(progress: { _ in })
        XCTAssertEqual(items.first { $0.group == "Xcode Archives" }?.isSelected, false)
        XCTAssertEqual(items.first { $0.url.lastPathComponent == "mod" }?.isSelected, false)
        XCTAssertEqual(items.first { $0.group == "Homebrew" }?.isSelected, true)
    }

    func testXcodeRunningLeavesItsItemsUnselected() throws {
        try populate()
        let xcode = ScanContext.RunningApp(bundleID: "com.apple.dt.Xcode", name: "Xcode", executable: "Xcode")
        let items = DeveloperScanner(context: fx.context(running: [xcode])).scan(progress: { _ in })
        for item in items where ["Device Support", "Simulator Caches"].contains(item.group) {
            XCTAssertFalse(item.isSelected, item.name)
            XCTAssertEqual(item.inUseBy, "Xcode")
        }
        XCTAssertEqual(items.first { $0.group == "Homebrew" }?.isSelected, true)
    }

    func testSystemJunkNoLongerListsDeveloperCaches() throws {
        try populate()
        try fx.file("Library/Caches/com.vendor.app/x", bytes: 9_000)
        let names = CacheScanner(context: fx.context()).scan(progress: { _ in }).map(\.name)
        XCTAssertFalse(names.contains("Homebrew"))
        XCTAssertTrue(names.contains("com.vendor.app"))
    }

    func testEverySourceIsAllowedBySafetyGuardButNotItsParents() throws {
        let safety = fx.safety
        for source in DeveloperScanner.sources {
            let url = fx.home.appendingPathComponent(source.path)
            let target = source.mode == .children ? url.appendingPathComponent("entry") : url
            XCTAssertTrue(safety.evaluate(target).isAllowed, source.path)
        }
        for parent in ["Library/Developer", "Library/Developer/Xcode", "Library/Caches", ".cargo/registry/..", "Library/pnpm"] {
            XCTAssertFalse(safety.evaluate(fx.raw(fx.home.path + "/" + parent)).isAllowed, parent)
        }
    }
}

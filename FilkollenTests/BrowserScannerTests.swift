import XCTest
@testable import Filkollen

final class BrowserScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private func populate() throws {
        let chrome = "Library/Application Support/Google/Chrome"
        try fx.file("\(chrome)/Default/Preferences", bytes: 100)
        try fx.file("\(chrome)/Default/Cache/Cache_Data/f_000001", bytes: 20_000)
        try fx.file("\(chrome)/Default/Code Cache/js/x", bytes: 20_000)
        try fx.file("\(chrome)/Default/History", bytes: 20_000)            // never
        try fx.file("\(chrome)/Default/Cookies", bytes: 20_000)            // never
        try fx.file("\(chrome)/Default/Login Data", bytes: 20_000)         // never
        try fx.file("\(chrome)/Profile 1/Preferences", bytes: 100)
        try fx.file("\(chrome)/Profile 1/GPUCache/data_0", bytes: 20_000)
        try fx.file("\(chrome)/GrShaderCache/x", bytes: 20_000)
        try fx.file("Library/Caches/Google/Chrome/Default/Cache/x", bytes: 20_000)
        try fx.file("Library/Caches/Firefox/Profiles/abcd.default-release/cache2/entries/x", bytes: 20_000)
        try fx.file("Library/Application Support/Firefox/Profiles/abcd.default-release/places.sqlite", bytes: 20_000) // never
        try fx.file("Library/Caches/com.apple.Safari/Cache.db", bytes: 20_000)
        try fx.file("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/123/report.pdf", bytes: 20_000)
    }

    func testOnlyCacheFoldersAreReported() throws {
        try populate()
        let items = BrowserScanner(context: fx.context()).scan(progress: { _ in })
        let names = Set(items.map(\.name))
        XCTAssertEqual(names, ["Cache", "Code Cache", "GPUCache", "GrShaderCache", "Chrome", "cache2", "com.apple.Safari", "Mail Downloads"])
        XCTAssertEqual(Set(items.map(\.group)), ["Google Chrome", "Firefox", "Safari", "Mail Downloads"])
        for item in items {
            XCTAssertFalse(["History", "Cookies", "Login Data", "places.sqlite", "Preferences"].contains(item.name))
        }
        XCTAssertTrue(items.allSatisfy(\.isSelected))
        XCTAssertTrue(AppModel.screened(items, category: .browserCaches, safety: fx.safety).count == items.count,
                      "every reported folder passes SafetyGuard")
    }

    func testRunningBrowserIsLeftUnselected() throws {
        try populate()
        let running = [ScanContext.RunningApp(bundleID: "com.apple.Safari", name: "Safari", executable: "Safari")]
        let items = BrowserScanner(context: fx.context(running: running)).scan(progress: { _ in })
        let safari = try XCTUnwrap(items.first { $0.group == "Safari" })
        XCTAssertFalse(safari.isSelected)
        XCTAssertEqual(safari.inUseBy, "Safari")
        XCTAssertEqual(safari.requiresClosed, ["com.apple.Safari"])
        XCTAssertTrue(items.first { $0.group == "Google Chrome" }?.isSelected == true)
    }

    func testCleanerRefusesWhileTheBrowserRuns() throws {
        try populate()
        let items = AppModel.screened(BrowserScanner(context: fx.context()).scan(progress: { _ in }),
                                      category: .browserCaches, safety: fx.safety)
        let outcome = Cleaner.moveToTrash(items, safety: fx.safety, isRunning: { $0 == "com.apple.Safari" },
                                          trash: { try FileManager.default.removeItem(at: $0); return nil })
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures.first?.url.lastPathComponent, "com.apple.Safari")
        XCTAssertTrue(outcome.failures.first?.reason.hasPrefix("Quit") == true)
        XCTAssertEqual(outcome.trashed.count, items.count - 1)
    }

    func testSystemJunkSkipsBrowserFolders() throws {
        try populate()
        let names = CacheScanner(context: fx.context()).scan(progress: { _ in }).map(\.name)
        XCTAssertFalse(names.contains("Google"))
        XCTAssertFalse(names.contains("Firefox"))
        XCTAssertFalse(names.contains("com.apple.Safari"))
    }
}

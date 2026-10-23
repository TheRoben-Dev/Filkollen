import XCTest
@testable import Filkollen

final class AppUninstallerTests: XCTestCase {
    func testBelongsMatchesBundleIDForms() {
        let id = "com.vendor.editor"
        let names: Set<String> = ["editor"]
        for entry in ["com.vendor.editor", "com.Vendor.Editor.plist", "com.vendor.editor.helper",
                      "ABCDE12345.com.vendor.editor", "group.com.vendor.editor", "com.vendor.editor.savedState",
                      "com.vendor.editor.0A1B2C3D-0000-1111-2222-333344445555.plist", "com.vendor.editor.binarycookies"] {
            XCTAssertTrue(AppUninstaller.belongs(entry, to: id, names: names, plainNames: false), entry)
        }
        XCTAssertTrue(AppUninstaller.belongs("Editor", to: id, names: names, plainNames: true))
    }

    func testBelongsRejectsNeighbours() {
        let id = "com.vendor.editor"
        let names: Set<String> = ["editor"]
        for entry in ["com.vendor.editorpro", "com.vendor", "com.vendor.other", "com.other.editor",
                      "Editor Pro", "com.vendor.edito.plist", "group.com.vendor.editorpro", "ABCDE12345.com.vendor.editorpro"] {
            XCTAssertFalse(AppUninstaller.belongs(entry, to: id, names: names, plainNames: true), entry)
        }
        // Plain names only where asked for.
        XCTAssertFalse(AppUninstaller.belongs("Editor", to: id, names: names, plainNames: false))
    }

    func testRemnantsFindsSupportFilesAndTheAppInHome() throws {
        let fx = try Fixture()
        let appURL = try fx.app("Editor", bundleID: "com.vendor.editor")
        try fx.file("Library/Application Support/com.vendor.editor/data.db", bytes: 4096)
        try fx.file("Library/Application Support/Editor/settings.json", bytes: 512)
        try fx.file("Library/Caches/com.vendor.editor/cache.bin", bytes: 4096)
        try fx.file("Library/Preferences/com.vendor.editor.plist")
        try fx.file("Library/Preferences/Editor") // plain names aren't matched in Preferences
        try fx.dir("Library/Containers/com.vendor.editor.helper")
        try fx.file("Library/Containers/com.vendor.editor.helper/Data/x", bytes: 128)
        try fx.file("Library/Application Support/com.vendor.other/keep.db", bytes: 4096)
        try fx.file("Library/Application Support/Google/keep", bytes: 64)

        let uninstaller = AppUninstaller(context: fx.context())
        let app = try uninstaller.app(at: appURL)
        XCTAssertTrue(app.canTrashBundle)
        let found = Set(uninstaller.remnants(of: app).map { $0.url.lastPathComponent })

        XCTAssertEqual(found, ["Editor.app", "com.vendor.editor", "Editor", "com.vendor.editor.plist", "com.vendor.editor.helper"])
        XCTAssertTrue(uninstaller.remnants(of: app).allSatisfy { $0.requiresClosed == ["com.vendor.editor"] })
    }

    func testAppOutsideHomeIsNeverListedAsTrashable() throws {
        let fx = try Fixture()
        let appURL = try fx.app("Editor", bundleID: "com.vendor.editor", in: fx.outside)
        let uninstaller = AppUninstaller(context: fx.context())
        let app = try uninstaller.app(at: appURL)
        XCTAssertFalse(app.canTrashBundle)
        XCTAssertFalse(uninstaller.remnants(of: app).contains { $0.url == appURL })
        // And SafetyGuard would refuse it anyway.
        guard case .refused = fx.safety.evaluate(appURL) else { return XCTFail("app outside home must be refused") }
    }

    func testLaunchAgentNeedsMatchingLabel() throws {
        let fx = try Fixture()
        let appURL = try fx.app("Editor", bundleID: "com.vendor.editor")
        let good = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.vendor.editor.updater"], format: .xml, options: 0)
        let other = try PropertyListSerialization.data(fromPropertyList: ["Label": "com.someone.else"], format: .xml, options: 0)
        try fx.file("Library/LaunchAgents/com.vendor.editor.updater.plist", contents: good)
        try fx.file("Library/LaunchAgents/com.vendor.editor.legacy.plist", contents: other)

        let uninstaller = AppUninstaller(context: fx.context())
        let names = uninstaller.remnants(of: try uninstaller.app(at: appURL)).map(\.url.lastPathComponent)
        XCTAssertTrue(names.contains("com.vendor.editor.updater.plist"))
        XCTAssertFalse(names.contains("com.vendor.editor.legacy.plist"))
    }

    func testAppleAndNonAppsAreRefused() throws {
        let fx = try Fixture()
        let apple = try fx.app("Notes", bundleID: "com.apple.Notes")
        let uninstaller = AppUninstaller(context: fx.context())
        XCTAssertThrowsError(try uninstaller.app(at: apple)) { XCTAssertEqual($0 as? AppUninstaller.Refusal, .apple) }
        let folder = try fx.dir("Documents/NotAnApp")
        XCTAssertThrowsError(try uninstaller.app(at: folder)) { XCTAssertEqual($0 as? AppUninstaller.Refusal, .notAnApp) }
        XCTAssertFalse(uninstaller.installedApps().contains { $0.bundleID == "com.apple.Notes" })
    }

    func testInstalledAppsListsFixtureApps() throws {
        let fx = try Fixture()
        try fx.app("Zed", bundleID: "dev.zed.Zed")
        try fx.app("Alpha", bundleID: "com.example.alpha")
        let names = AppUninstaller(context: fx.context()).installedApps().map(\.name)
        XCTAssertEqual(names, ["Alpha", "Zed"])
    }

    func testCleanerRefusesWhileAppRuns() throws {
        let fx = try Fixture()
        let appURL = try fx.app("Editor", bundleID: "com.vendor.editor")
        try fx.file("Library/Caches/com.vendor.editor/c", bytes: 64)
        let uninstaller = AppUninstaller(context: fx.context())
        let items = AppModel.screened(uninstaller.remnants(of: try uninstaller.app(at: appURL)), category: .appLeftovers, safety: fx.safety)
        XCTAssertFalse(items.isEmpty)
        let outcome = Cleaner.moveToTrash(items, safety: fx.safety, isRunning: { $0 == "com.vendor.editor" }, trash: { _ in
            XCTFail("must not trash while running"); return nil
        })
        XCTAssertEqual(outcome.failures.count, items.count)
    }
}

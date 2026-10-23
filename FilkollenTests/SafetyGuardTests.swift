import XCTest
@testable import Filkollen

final class SafetyGuardTests: XCTestCase {
    private var fx: Fixture!
    private var safety: SafetyGuard!

    override func setUpWithError() throws {
        fx = try Fixture()
        safety = fx.safety
    }

    override func tearDown() {
        fx = nil
        safety = nil
    }

    private func assertAllowed(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let decision = safety.evaluate(url)
        XCTAssertTrue(decision.isAllowed, "expected allowed: \(url.path) → \(decision)", file: file, line: line)
    }

    private func assertRefused(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        let decision = safety.evaluate(url)
        XCTAssertFalse(decision.isAllowed, "expected refused: \(url.path)", file: file, line: line)
    }

    private func assertRefused(_ path: String, file: StaticString = #filePath, line: UInt = #line) {
        assertRefused(fx.raw(path), file: file, line: line)
    }

    // MARK: Basics

    func testAllowsOrdinaryCacheEntries() throws {
        assertAllowed(try fx.dir("Library/Caches/com.vendor.app"))
        assertAllowed(try fx.file("Library/Logs/vendor/app.log"))
        assertAllowed(try fx.file("Downloads/Installer.dmg"))
        // Doesn't have to exist yet.
        assertAllowed(fx.home.appendingPathComponent("Library/Caches/not-created-yet"))
    }

    func testRefusesOutsideHomeAndTemp() throws {
        assertRefused("/")
        assertRefused("/etc/hosts")
        assertRefused("/System/Library/CoreServices")
        assertRefused("/Applications/Safari.app")
        assertRefused("/Library/Caches/com.vendor.app")
        assertRefused(try fx.file("thing", in: fx.outside))
    }

    func testRefusesHomeItselfAndProtectedRoots() {
        for rel in ["", "Library", "Library/Caches", "Library/Logs", "Library/Application Support",
                    "Library/Preferences", "Library/Containers", "Library/Group Containers",
                    "Pictures", "Desktop", "Documents", "Downloads", "Movies", "Music", "Applications"] {
            assertRefused(fx.home.appendingPathComponent(rel))
        }
    }

    func testRefusesDirectChildrenOfLibrary() {
        assertRefused(fx.home.appendingPathComponent("Library/SomethingNew"))
        assertRefused(fx.home.appendingPathComponent("Library/Fonts"))
    }

    func testTrailingSlashesDontBypassProtectedRoots() {
        assertRefused(fx.home.path + "/")
        assertRefused(fx.home.path + "/Library/")
        assertRefused(fx.home.path + "/Library/Caches/")
        assertRefused(fx.home.path + "/Library/Caches//")
        assertAllowed(fx.raw(fx.home.path + "/Library/Caches/foo/"))
    }

    func testRefusesNonFileAndRelativeInput() {
        XCTAssertFalse(safety.evaluate(URL(string: "https://example.com/x")!).isAllowed)
        XCTAssertNil(SafetyGuard.canonicalPath("Library/Caches/x"))
    }

    // MARK: Traversal

    func testDotDotTraversalOutOfHomeIsRefused() {
        assertRefused(fx.home.path + "/Library/Caches/../../../outside")
        assertRefused(fx.home.path + "/Library/Caches/../../..")
        assertRefused(fx.home.path + "/Library/Caches/..")
        assertRefused(fx.home.path + "/Library/Caches/../Keychains/login.keychain-db")
    }

    func testDotDotThroughMissingComponentsIsRefused() {
        // Its meaning would depend on what gets created there later.
        assertRefused(fx.home.path + "/Library/Caches/missing/../../Keychains")
        assertRefused(fx.home.path + "/Library/Caches/missing/..")
    }

    func testDotDotWithinAllowedAreaResolves() throws {
        try fx.dir("Library/Caches/a")
        try fx.file("Library/Caches/b/file")
        assertAllowed(fx.raw(fx.home.path + "/Library/Caches/a/../b/file"))
    }

    // MARK: Symlinks and aliases

    func testSymlinkPointingOutsideHomeIsRefused() throws {
        let target = try fx.file("secret", in: fx.outside)
        assertRefused(try fx.symlink("Library/Caches/evil", to: target))
    }

    func testSymlinkedParentPointingOutsideHomeIsRefused() throws {
        try fx.file("victim", in: fx.outside)
        try fx.symlink("Library/Caches/dir", to: fx.outside)
        assertRefused(fx.home.appendingPathComponent("Library/Caches/dir/victim"))
    }

    func testSymlinkIntoKeychainsIsRefused() throws {
        try fx.file("Library/Keychains/login.keychain-db")
        assertRefused(try fx.symlink("Library/Caches/kc", to: fx.home.appendingPathComponent("Library/Keychains")))
        assertRefused(fx.home.appendingPathComponent("Library/Caches/kc/login.keychain-db"))
    }

    func testSymlinkToProtectedRootIsRefused() throws {
        assertRefused(try fx.symlink("Library/Caches/docs", to: fx.home.appendingPathComponent("Documents")))
    }

    func testSymlinkWithinAllowedAreaIsAllowed() throws {
        let target = try fx.dir("Library/Caches/real")
        assertAllowed(try fx.symlink("Library/Caches/link", to: target))
    }

    func testSymlinkedHomeStillMatches() throws {
        // A guard configured with a path through a symlink must still recognise its home.
        let alias = try fx.symlink("home-link", to: fx.home, in: fx.root)
        let viaLink = SafetyGuard(home: alias, temp: fx.temp)
        XCTAssertTrue(viaLink.evaluate(try fx.dir("Library/Caches/x")).isAllowed)
        XCTAssertFalse(viaLink.evaluate(fx.home.appendingPathComponent("Library/Keychains/x")).isAllowed)
    }

    func testFinderAliasIsJudgedAsTheFileItIs() throws {
        // An alias is a small bookmark file; trashing it never touches its target.
        let target = try fx.file("secret", in: fx.outside)
        let alias = fx.home.appendingPathComponent("Downloads/secret alias")
        let data = try target.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        try URL.writeBookmarkData(data, to: alias)
        assertAllowed(alias)
    }

    // MARK: Firmlinks

    func testDataVolumeFirmlinkPathsAreNormalized() throws {
        let caches = try fx.dir("Library/Caches/x")
        let real = SafetyGuard.canonicalPath(caches.path)!
        let viaData = "/System/Volumes/Data" + real
        XCTAssertEqual(SafetyGuard.canonicalPath(viaData).map(SafetyGuard.fold), SafetyGuard.fold(real))
        assertAllowed(fx.raw(viaData))

        let keychains = SafetyGuard.canonicalPath(fx.home.appendingPathComponent("Library/Keychains").path)!
        assertRefused("/System/Volumes/Data" + keychains + "/login.keychain-db")
        assertRefused("/System/Volumes/Data" + SafetyGuard.canonicalPath(fx.home.path)!)
        assertRefused("/System/Volumes/Data/etc/hosts")
    }

    // MARK: Case and Unicode

    func testCaseVariantsDontBypassRules() {
        let h = fx.home.path
        assertRefused(h + "/library/keychains/login.keychain-db")
        assertRefused(h + "/LIBRARY/Keychains")
        assertRefused(h + "/library")
        assertRefused(h + "/library/caches")
        assertRefused(h + "/Library/mobile documents/com~apple~CloudDocs/file.txt")
        assertRefused(h + "/Pictures/Photos Library.PHOTOSLIBRARY/originals/a.heic")
        assertRefused(h + "/Library/Caches/COM.APPLE.Safari")
        assertRefused(h + "/.trash/x")
    }

    func testUnicodeNormalizationVariants() throws {
        let nfd = "Ro\u{0308}ben"   // "Röben", decomposed
        let nfc = "R\u{00F6}ben"    // "Röben", precomposed
        let fx = try Fixture(homeName: nfd)
        let nfcHome = fx.root.appendingPathComponent(nfc)
        let safety = SafetyGuard(home: nfcHome, temp: fx.temp)

        let cacheNFD = try fx.dir("Library/Caches/x")
        XCTAssertTrue(safety.evaluate(cacheNFD).isAllowed)
        XCTAssertTrue(safety.evaluate(nfcHome.appendingPathComponent("Library/Caches/x")).isAllowed)
        XCTAssertFalse(safety.evaluate(nfcHome.appendingPathComponent("Library/Keychains/x")).isAllowed)
        XCTAssertFalse(safety.evaluate(fx.home.appendingPathComponent("Library")).isAllowed)

        // Protected names in the other normal form.
        let cafe = "Cafe\u{0301}.photoslibrary"
        XCTAssertFalse(safety.evaluate(fx.home.appendingPathComponent("Pictures/\(cafe)/x.jpg")).isAllowed)
    }

    // MARK: Protected data

    func testICloudAndCloudStorageAreRefused() {
        assertRefused(fx.home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/file.txt"))
        assertRefused(fx.home.appendingPathComponent("Library/Mobile Documents"))
        assertRefused(fx.home.appendingPathComponent("Library/CloudStorage/Dropbox/x"))
    }

    func testKeychainsAreRefused() {
        assertRefused(fx.home.appendingPathComponent("Library/Keychains"))
        assertRefused(fx.home.appendingPathComponent("Library/Keychains/login.keychain-db"))
        assertRefused(fx.home.appendingPathComponent("Library/Keychains/ABC-123/keychain-2.db"))
    }

    func testPhotosLibraryRefusedAtAnyDepth() throws {
        assertRefused(fx.home.appendingPathComponent("Pictures/Photos Library.photoslibrary"))
        assertRefused(fx.home.appendingPathComponent("Pictures/Photos Library.photoslibrary/originals/0/a.heic"))
        assertRefused(try fx.file("Desktop/a/b/c/Old.photoslibrary/database/x"))
        assertRefused(fx.home.appendingPathComponent("Pictures/iPhoto Library.photolibrary/x"))
    }

    func testMailStoreAndOtherAppDataRefused() {
        for rel in ["Library/Mail/V10/x.emlx", "Library/Messages/chat.db", "Library/Safari/History.db",
                    "Library/Application Support/AddressBook/x", "Library/Application Support/MobileSync/Backup/x",
                    "Library/Autosave Information/doc.rtf", ".ssh/id_ed25519", ".Trash/old.zip", ".Trash"] {
            assertRefused(fx.home.appendingPathComponent(rel))
        }
    }

    func testFilkollensOwnDataIsRefused() {
        assertRefused(fx.home.appendingPathComponent("Library/Application Support/Filkollen/Quarantine/x"))
    }

    func testAppleItemsAreRefused() {
        for rel in ["Library/Caches/com.apple.Safari", "Library/Preferences/com.apple.finder.plist",
                    "Library/Containers/com.apple.mail/Data/x", "Library/Group Containers/group.com.apple.notes",
                    "Library/Group Containers/UBF8T346G9.com.apple.office", "Library/Logs/com.apple.xpc.launchd/x"] {
            assertRefused(fx.home.appendingPathComponent(rel))
        }
        assertAllowed(fx.home.appendingPathComponent("Library/Caches/com.spotify.client"))
    }

    func testAppBundleInternalsRefusedButWholeBundleAllowed() {
        assertAllowed(fx.home.appendingPathComponent("Applications/Foo.app"))
        assertRefused(fx.home.appendingPathComponent("Applications/Foo.app/Contents/Resources/en.lproj"))
        assertRefused(fx.home.appendingPathComponent("Applications/Foo.app/Contents/MacOS/Foo"))
    }

    // MARK: Temp

    func testOnlyTheTFolderOfTempIsAllowed() throws {
        assertAllowed(try fx.file("old.tmp", in: fx.temp))
        assertRefused(fx.temp)
        assertRefused(try fx.file("cache.db", in: fx.root.appendingPathComponent("vf/C")))
        assertRefused(fx.root.appendingPathComponent("vf"))
    }

    func testSharedGuardUsesRealTemp() {
        let t = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertTrue(SafetyGuard.isAllowed(t.appendingPathComponent("filkollen-test-\(UUID().uuidString)")))
        XCTAssertFalse(SafetyGuard.isAllowed(t.deletingLastPathComponent().appendingPathComponent("C/x")))
        XCTAssertFalse(SafetyGuard.isAllowed(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")))
    }
}

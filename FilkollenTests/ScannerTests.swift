import XCTest
@testable import Filkollen

private let noProgress: @Sendable (String) -> Void = { _ in }

final class Messages: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func append(_ m: String) { lock.withLock { list.append(m) } }
    var all: [String] { lock.withLock { list } }
}

final class CacheScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testFindsCachesLogsAndDerivedData() throws {
        try fx.file("Library/Caches/com.vendor.app/blob", bytes: 10_000)
        try fx.file("Library/Logs/Vendor/app.log", bytes: 5_000)
        try fx.file("Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x.o", bytes: 20_000)
        let items = CacheScanner(context: fx.context()).scan(progress: noProgress)

        XCTAssertEqual(Set(items.map(\.name)), ["com.vendor.app", "Vendor", "MyApp-abc"])
        XCTAssertEqual(Set(items.map(\.group)), ["User Caches", "User Logs", "Xcode Derived Data"])
        XCTAssertTrue(items.allSatisfy { $0.size > 0 && $0.isSelected })
        XCTAssertEqual(items.map(\.size), items.map(\.size).sorted(by: >), "sorted largest first")
    }

    func testSkipsEmptyItems() throws {
        try fx.dir("Library/Caches/empty-folder")
        try fx.file("Library/Caches/zero", bytes: 0)
        try fx.file("Library/Caches/real/x", bytes: 4_000)
        let items = CacheScanner(context: fx.context()).scan(progress: noProgress)
        XCTAssertEqual(items.map(\.name), ["real"])
    }

    func testAppleCachesAreScreenedOut() throws {
        try fx.file("Library/Caches/com.apple.finder/x", bytes: 4_000)
        try fx.file("Library/Caches/com.vendor.app/x", bytes: 4_000)
        let raw = CacheScanner(context: fx.context()).scan(progress: noProgress)
        let shown = AppModel.screened(raw, category: .systemJunk, safety: fx.safety)
        XCTAssertEqual(shown.map(\.name), ["com.vendor.app"])
    }

    func testRunningAppsCachesAreUnselectedAndFlagged() throws {
        try fx.file("Library/Caches/com.spotify.client/data", bytes: 8_000)
        try fx.file("Library/Caches/com.spotify.client.ShipIt/data", bytes: 8_000)
        try fx.file("Library/Caches/Slack/x", bytes: 8_000)
        try fx.file("Library/Caches/Adobe/Acrobat/x", bytes: 8_000)
        try fx.file("Library/Caches/com.idle.app/data", bytes: 8_000)
        let running: [ScanContext.RunningApp] = [
            .init(bundleID: "com.spotify.client", name: "Spotify", executable: "Spotify"),
            .init(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", executable: "Slack"),
            .init(bundleID: "com.adobe.Reader", name: "Adobe Acrobat Reader", executable: "AdobeReader"),
        ]
        let items = CacheScanner(context: fx.context(running: running)).scan(progress: noProgress)
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })

        for name in ["com.spotify.client", "com.spotify.client.ShipIt", "Slack", "Adobe"] {
            XCTAssertEqual(byName[name]?.isSelected, false, name)
            XCTAssertNotNil(byName[name]?.inUseBy, name)
        }
        XCTAssertEqual(byName["com.idle.app"]?.isSelected, true)
        XCTAssertNil(byName["com.idle.app"]?.inUseBy)
    }

    func testOnlyOldTempFilesAreListed() throws {
        let now = Date()
        try fx.file("old.tmp", in: fx.temp, bytes: 4_000, modified: now.addingTimeInterval(-5 * 86_400))
        try fx.file("fresh.tmp", in: fx.temp, bytes: 4_000, modified: now.addingTimeInterval(-1 * 86_400))
        let items = CacheScanner(context: fx.context(now: now)).scan(progress: noProgress)
            .filter { $0.group == "Temporary Files" }
        XCTAssertEqual(items.map(\.name), ["old.tmp"])

        // The clock is injected: ten days later both are old.
        let later = CacheScanner(context: fx.context(now: now.addingTimeInterval(10 * 86_400))).scan(progress: noProgress)
        XCTAssertEqual(Set(later.filter { $0.group == "Temporary Files" }.map(\.name)), ["old.tmp", "fresh.tmp"])
    }

    func testUnreadableFolderDoesntBreakTheScan() throws {
        let locked = try fx.dir("Library/Caches/locked")
        try fx.file("Library/Caches/locked/inner", bytes: 4_000)
        try fx.file("Library/Caches/fine/x", bytes: 4_000)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let items = CacheScanner(context: fx.context()).scan(progress: noProgress)
        XCTAssertTrue(items.contains { $0.name == "fine" })
    }

    func testCancellationFlagStopsEveryScanner() throws {
        try fx.file("Library/Caches/com.vendor.app/blob", bytes: 10_000)
        try fx.file("Library/Application Support/com.gone.app/x", bytes: 4_000)
        try fx.file("Pictures/a.jpg", bytes: 5_000)
        try fx.file("Downloads/a.jpg", bytes: 5_000)
        try fx.file("Movies/big.mov", bytes: 300_000)
        let context = fx.context(largeFileMinBytes: 100_000)
        context.cancellation.set()
        XCTAssertTrue(CacheScanner(context: context).scan(progress: noProgress).isEmpty)
        XCTAssertTrue(LeftoverScanner(context: context).scan(progress: noProgress).isEmpty)
        XCTAssertTrue(DuplicatePhotoScanner(context: context).scan(progress: noProgress).isEmpty)
        XCTAssertTrue(LargeFileScanner(context: context).scan(progress: noProgress).isEmpty)
    }

    func testProgressShowsCountAndRate() throws {
        for i in 0..<5 { try fx.file("Library/Caches/c\(i)/x", bytes: 4_000) }
        let messages = Messages()
        _ = CacheScanner(context: fx.context()).scan(progress: { messages.append($0) })
        XCTAssertTrue(messages.all.contains { $0.contains("items ·") && $0.contains("/s") })
    }

    func testMissingFoldersYieldNothing() throws {
        let empty = try Fixture()
        try FileManager.default.removeItem(at: empty.home.appendingPathComponent("Library"))
        XCTAssertTrue(CacheScanner(context: empty.context()).scan(progress: noProgress).isEmpty)
    }

    func testHonoursCancellation() async throws {
        try fx.file("Library/Caches/com.vendor.app/blob", bytes: 10_000)
        let context = fx.context()
        let task = Task.detached { () -> [JunkItem] in
            while !Task.isCancelled { await Task.yield() }
            return CacheScanner(context: context).scan(progress: noProgress)
        }
        task.cancel()
        let items = await task.value
        XCTAssertTrue(items.isEmpty)
    }
}

final class LeftoverScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testBundleIDExtraction() {
        XCTAssertEqual(LeftoverScanner.bundleID(from: "com.vendor.app"), "com.vendor.app")
        XCTAssertEqual(LeftoverScanner.bundleID(from: "com.vendor.app.plist"), "com.vendor.app")
        XCTAssertEqual(LeftoverScanner.bundleID(from: "com.vendor.app.savedState"), "com.vendor.app")
        XCTAssertEqual(LeftoverScanner.bundleID(from: "com.vendor.app.binarycookies"), "com.vendor.app")
        XCTAssertEqual(LeftoverScanner.bundleID(from: "group.com.vendor.app"), "com.vendor.app")
        XCTAssertEqual(LeftoverScanner.bundleID(from: "ABCDE12345.com.vendor.app"), "com.vendor.app")
        XCTAssertNil(LeftoverScanner.bundleID(from: "com.apple.Safari"))
        XCTAssertNil(LeftoverScanner.bundleID(from: "group.com.apple.notes"))
        XCTAssertNil(LeftoverScanner.bundleID(from: "Spotify"))
        XCTAssertNil(LeftoverScanner.bundleID(from: "com.vendor"))
        XCTAssertNil(LeftoverScanner.bundleID(from: ".GlobalPreferences.plist"))
        XCTAssertNil(LeftoverScanner.bundleID(from: "loginwindow.plist"))
    }

    func testFindsOnlyFilesOfUninstalledApps() throws {
        try fx.app("Installed", bundleID: "com.installed.app")
        try fx.file("Library/Application Support/com.gone.app/data.db", bytes: 4_000)
        try fx.file("Library/Preferences/com.gone.app.plist", bytes: 500)
        try fx.file("Library/Caches/com.installed.app/x", bytes: 4_000)
        try fx.file("Library/Caches/com.installed.app.helper/x", bytes: 4_000)
        try fx.file("Library/Application Support/Spotify/x", bytes: 4_000)
        try fx.file("Library/Containers/com.running.app/Data/x", bytes: 4_000)
        try fx.file("Library/Application Support/com.apple.sharedfilelist/x", bytes: 4_000)

        let running = [ScanContext.RunningApp(bundleID: "com.running.app", name: "Running", executable: nil)]
        let items = LeftoverScanner(context: fx.context(running: running)).scan(progress: noProgress)

        XCTAssertEqual(Set(items.map(\.group)), ["com.gone.app"])
        XCTAssertEqual(Set(items.map(\.detail)), ["Application Support", "Preferences"])
    }

    func testPlainNameLeftoversAreOffByDefault() throws {
        try fx.file("Library/Application Support/Spotify/x", bytes: 4_000)
        XCTAssertTrue(LeftoverScanner(context: fx.context()).scan(progress: noProgress).isEmpty)
    }

    func testPlainNameLeftoversWithConfidence() throws {
        try fx.app("Visual Studio Code", bundleID: "com.microsoft.VSCode")
        try fx.file("Library/Application Support/com.spotify.client/x", bytes: 4_000)  // bundle-ID leftover: Spotify is gone
        try fx.file("Library/Application Support/Spotify/x", bytes: 4_000)            // high
        try fx.file("Library/Caches/SomeTool/x", bytes: 4_000)                        // low
        try fx.file("Library/Application Support/Visual Studio Code/x", bytes: 4_000)  // installed app name
        try fx.file("Library/Application Support/CrashReporter/x", bytes: 4_000)       // shared, never
        try fx.file("Library/Application Support/Google/x", bytes: 4_000)              // vendor, never
        var context = fx.context()
        context.plainNameLeftovers = true
        let items = LeftoverScanner(context: context).scan(progress: noProgress)
        let byGroup = Dictionary(grouping: items, by: \.group)

        XCTAssertEqual(byGroup["Spotify"]?.first?.confidence, .high)
        XCTAssertEqual(byGroup["Spotify"]?.first?.isSelected, true)
        XCTAssertEqual(byGroup["SomeTool"]?.first?.confidence, .low)
        XCTAssertEqual(byGroup["SomeTool"]?.first?.isSelected, false)
        XCTAssertNil(byGroup["Visual Studio Code"])
        XCTAssertNil(byGroup["CrashReporter"])
        XCTAssertNil(byGroup["Google"])
        XCTAssertNil(byGroup["com.spotify.client"]?.first?.confidence, "bundle-ID matches aren't guesses")
    }

    func testNameTokens() {
        XCTAssertEqual(LeftoverScanner.nameTokens(ofBundleID: "com.spotify.client"), ["spotify"])
        XCTAssertEqual(LeftoverScanner.nameTokens(ofBundleID: "com.microsoft.VSCode"), ["microsoft", "vscode"])
    }

    func testLaunchServicesHasTheFinalWord() throws {
        try fx.file("Library/Caches/com.elsewhere.app/x", bytes: 4_000)
        var context = fx.context()
        context.isRegisteredApp = { $0 == "com.elsewhere.app" }
        XCTAssertTrue(LeftoverScanner(context: context).scan(progress: noProgress).isEmpty)
    }
}

final class DuplicatePhotoScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private func image(_ bytes: Int, seed: UInt8 = 1, tail: UInt8? = nil) -> Data {
        var data = Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) })
        if let tail { data[data.count - 1] = tail }
        return data
    }

    private func setCreated(_ url: URL, daysAgo: Double) throws {
        try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-daysAgo * 86_400)],
                                              ofItemAtPath: url.path)
    }

    func testGroupsIdenticalImagesAndKeepsTheOldest() throws {
        let photo = image(80_000)
        let original = try fx.file("Pictures/IMG_0001.jpg", contents: photo)
        let copy1 = try fx.file("Downloads/IMG_0001.jpg", contents: photo)
        let copy2 = try fx.file("Desktop/old/IMG_0001 copy.jpg", contents: photo)
        try setCreated(original, daysAgo: 30)
        try setCreated(copy1, daysAgo: 2)
        try setCreated(copy2, daysAgo: 1)

        let items = DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(Set(items.map(\.group)).count, 1)
        let keeper = try XCTUnwrap(items.first { $0.isKeeper })
        XCTAssertEqual(keeper.url.lastPathComponent, original.lastPathComponent)
        XCTAssertEqual(keeper.url.deletingLastPathComponent().lastPathComponent, "Pictures")
        XCTAssertFalse(keeper.isSelected)
        XCTAssertEqual(items.filter(\.isSelected).count, 2)
    }

    func testSameSizeAndSameHeadButDifferentTailAreNotDuplicates() throws {
        try fx.file("Pictures/a.png", contents: image(200_000, tail: 1))
        try fx.file("Pictures/b.png", contents: image(200_000, tail: 2))
        XCTAssertTrue(DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress).isEmpty)
    }

    func testSameHeadAndTailButDifferentMiddleAreNotDuplicates() throws {
        var a = image(400_000), b = image(400_000)
        a[200_000] = 1
        b[200_000] = 2
        try fx.file("Pictures/a.png", contents: a)
        try fx.file("Pictures/b.png", contents: b)
        XCTAssertTrue(DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress).isEmpty)
    }

    func testRescanWithCacheGivesTheSameGroups() throws {
        let photo = image(150_000)
        try fx.file("Pictures/a.jpg", contents: photo)
        try fx.file("Downloads/a.jpg", contents: photo)
        try fx.file("Desktop/other.jpg", contents: image(150_000, seed: 9))
        var context = fx.context()
        context.cacheDirectory = fx.root
        let first = DuplicatePhotoScanner(context: context).scan(progress: noProgress)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fx.root.appendingPathComponent("photo-hash-cache.plist").path))
        let second = DuplicatePhotoScanner(context: context).scan(progress: noProgress)
        XCTAssertEqual(first.map(\.url), second.map(\.url))
        XCTAssertEqual(first.count, 2)
    }

    func testSameSizeDifferentContentAreNotDuplicates() throws {
        try fx.file("Pictures/a.heic", contents: image(10_000, seed: 1))
        try fx.file("Pictures/b.heic", contents: image(10_000, seed: 2))
        XCTAssertTrue(DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress).isEmpty)
    }

    func testIgnoresZeroByteNonImageAndPhotosLibraryFiles() throws {
        try fx.file("Pictures/empty1.jpg", bytes: 0)
        try fx.file("Pictures/empty2.jpg", bytes: 0)
        try fx.file("Documents/a.txt", contents: image(5_000))
        try fx.file("Documents/b.txt", contents: image(5_000))
        try fx.file("Pictures/Photos Library.photoslibrary/originals/x.jpg", contents: image(5_000))
        try fx.file("Pictures/y.jpg", contents: image(5_000))
        XCTAssertTrue(DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress).isEmpty)
    }

    func testExtensionMatchIsCaseInsensitive() throws {
        try fx.file("Pictures/A.JPG", contents: image(5_000))
        try fx.file("Downloads/A.jpeg", contents: image(5_000))
        XCTAssertEqual(DuplicatePhotoScanner(context: fx.context()).scan(progress: noProgress).count, 2)
    }
}

final class LargeFileScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testFindsFilesOverTheThresholdOutsideLibraryAndTrash() throws {
        try fx.file("Movies/big.mov", bytes: 300_000)
        try fx.file("Downloads/small.zip", bytes: 1_000)
        try fx.file("Library/Caches/huge.bin", bytes: 300_000)
        try fx.file(".Trash/huge.bin", bytes: 300_000)
        let items = LargeFileScanner(context: fx.context(largeFileMinBytes: 100_000)).scan(progress: noProgress)

        XCTAssertEqual(items.map(\.name), ["big.mov"])
        XCTAssertEqual(items.first?.group, "Videos")
        XCTAssertEqual(items.first?.isSelected, false, "large files are never pre-selected")
    }

    func testOldFilesAreListedWhenAgeFilterIsOn() throws {
        let now = Date()
        let old = now.addingTimeInterval(-400 * 86_400)
        let oldBig = try fx.file("Documents/old-backup.zip", bytes: Int(LargeFileScanner.oldFileMinBytes) + 10_000, modified: old)
        let oldSmall = try fx.file("Documents/old-note.txt", bytes: 1_000, modified: old)
        for url in [oldBig, oldSmall] {
            var values = URLResourceValues()
            values.contentAccessDate = old
            var u = url
            try u.setResourceValues(values)
        }
        let threshold: Int64 = 500 * 1_048_576
        let sizeOnly = LargeFileScanner(context: fx.context(now: now, largeFileMinBytes: threshold)).scan(progress: noProgress)
        XCTAssertTrue(sizeOnly.isEmpty)

        let withAge = LargeFileScanner(context: fx.context(now: now, largeFileMinBytes: threshold,
                                                           largeFileMinAge: 365 * 86_400)).scan(progress: noProgress)
        XCTAssertEqual(withAge.map(\.name), ["old-backup.zip"])
        XCTAssertEqual(withAge.first?.group, "Archives")
    }

    func testKinds() {
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "mov"), "Videos")
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "dmg"), "Disk Images")
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "zip"), "Archives")
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "pdf"), "Documents")
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "heic"), "Photos & Images")
        XCTAssertEqual(LargeFileScanner.kind(of: nil, ext: "zzzunknown"), "Other")
    }
}

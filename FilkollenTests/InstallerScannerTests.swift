import XCTest
@testable import Filkollen

final class InstallerScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    func testNormalize() {
        XCTAssertEqual(InstallerScanner.normalize("Firefox 131.0.2"), "firefox")
        XCTAssertEqual(InstallerScanner.normalize("GoogleChrome"), "googlechrome")
        XCTAssertEqual(InstallerScanner.normalize("Google Chrome"), "googlechrome")
        XCTAssertEqual(InstallerScanner.normalize("Spotify-1.2.3_arm64"), "spotify")
        XCTAssertEqual(InstallerScanner.normalize("1Password"), "1password")
        XCTAssertEqual(InstallerScanner.normalize("1Password 8"), "1password")
        XCTAssertEqual(InstallerScanner.normalize("VLC (1)"), "vlc")
    }

    func testMatching() {
        let installed = ["firefox": "Firefox", "googlechrome": "Google Chrome", "vlc": "VLC", "docker": "Docker"]
        XCTAssertEqual(InstallerScanner.matchingApp(for: "Firefox 131.0", installed: installed), "Firefox")
        XCTAssertEqual(InstallerScanner.matchingApp(for: "googlechrome", installed: installed), "Google Chrome")
        XCTAssertEqual(InstallerScanner.matchingApp(for: "Docker-arm64", installed: installed), "Docker")
        XCTAssertEqual(InstallerScanner.matchingApp(for: "vlc-3.0.20-universal", installed: installed), "VLC")
        XCTAssertNil(InstallerScanner.matchingApp(for: "vlcfoo", installed: installed), "short names need an exact match")
        XCTAssertNil(InstallerScanner.matchingApp(for: "Thunderbird 128", installed: installed))
    }

    func testFindsInstalledAndOldInstallers() throws {
        let now = Date()
        try fx.app("Firefox", bundleID: "org.mozilla.firefox")
        let recent = now.addingTimeInterval(-2 * 86_400)
        let old = now.addingTimeInterval(-90 * 86_400)
        try fx.file("Downloads/Firefox 131.0.dmg", bytes: 9_000, modified: recent)
        try fx.file("Downloads/Thunderbird 128.dmg", bytes: 9_000, modified: recent)   // not installed, recent: skip
        try fx.file("Downloads/OldTool.pkg", bytes: 9_000, modified: old)              // old: listed, unselected
        try fx.file("Downloads/photos-2019.zip", bytes: 9_000, modified: old)          // old archive: unselected
        try fx.file("Downloads/notes.txt", bytes: 9_000, modified: old)                // not an installer
        let deep = try fx.file("Downloads/a/b/deep.dmg", bytes: 9_000, modified: old)  // too deep
        try FileManager.default.setAttributes([.creationDate: old], ofItemAtPath: deep.path)
        for name in ["Firefox 131.0.dmg", "Thunderbird 128.dmg", "OldTool.pkg", "photos-2019.zip"] {
            let url = fx.home.appendingPathComponent("Downloads/\(name)")
            let date = name.hasPrefix("Old") || name.hasPrefix("photos") ? old : recent
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.contentAccessDate = date
            var u = url
            try u.setResourceValues(values)
        }

        let items = InstallerScanner(context: fx.context(now: now)).scan(progress: { _ in })
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["Firefox 131.0.dmg", "OldTool.pkg", "photos-2019.zip"])
        XCTAssertEqual(byName["Firefox 131.0.dmg"]?.isSelected, true)
        XCTAssertEqual(byName["Firefox 131.0.dmg"]?.group, "Already installed")
        XCTAssertEqual(byName["OldTool.pkg"]?.isSelected, false)
        XCTAssertEqual(byName["photos-2019.zip"]?.isSelected, false)
    }
}

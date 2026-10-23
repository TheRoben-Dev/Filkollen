import XCTest
@testable import Filkollen

final class IOSBackupScannerTests: XCTestCase {
    private var fx: Fixture!
    override func setUpWithError() throws { fx = try Fixture() }
    override func tearDown() { fx = nil }

    private func backup(_ udid: String, device: String, date: Date, encrypted: Bool = false) throws {
        let dir = try fx.dir("Library/Application Support/MobileSync/Backup/\(udid)")
        let info: [String: Any] = ["Device Name": device, "Product Version": "18.1", "Product Type": "iPhone16,1", "Last Backup Date": date]
        try fx.file("Info.plist", in: dir, contents: try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0))
        try fx.file("Manifest.plist", in: dir, contents: try PropertyListSerialization.data(fromPropertyList: ["IsEncrypted": encrypted], format: .xml, options: 0))
        try fx.file("00/0012ab", in: dir, bytes: 30_000)
    }

    func testListsBackupsWithDeviceDetailsUnselected() throws {
        let now = Date()
        try backup("00008110-AAAA", device: "Roben's iPhone", date: now.addingTimeInterval(-86_400), encrypted: true)
        try backup("00008110-AAAA-20240101-120000", device: "Roben's iPhone", date: now.addingTimeInterval(-300 * 86_400))
        try fx.file("Library/iTunes/iPhone Software Updates/iPhone16,1_18.1_Restore.ipsw", bytes: 50_000)
        try fx.file("Downloads/iPad_18.0_Restore.ipsw", bytes: 50_000)

        let items = IOSBackupScanner(context: fx.context()).scan(progress: { _ in })
        let backups = items.filter { $0.group == "Device Backups" }
        XCTAssertEqual(backups.count, 2)
        XCTAssertTrue(backups.allSatisfy { !$0.isSelected })
        XCTAssertTrue(backups.allSatisfy { $0.detail.contains("Roben's iPhone") && $0.detail.contains("iOS 18.1") })
        XCTAssertEqual(backups.filter { $0.detail.contains("latest backup") }.count, 1)
        XCTAssertTrue(backups.first { $0.detail.contains("latest") }?.detail.contains("encrypted") == true)

        let firmware = items.filter { $0.group == "Firmware Files" }
        XCTAssertEqual(firmware.count, 2)
        XCTAssertTrue(firmware.allSatisfy(\.isSelected))
    }

    func testSafetyGuardAllowsWholeBackupsOnly() throws {
        let safety = fx.safety
        let base = fx.home.appendingPathComponent("Library/Application Support/MobileSync")
        XCTAssertTrue(safety.evaluate(base.appendingPathComponent("Backup/00008110-AAAA")).isAllowed)
        XCTAssertFalse(safety.evaluate(base.appendingPathComponent("Backup")).isAllowed)
        XCTAssertFalse(safety.evaluate(base).isAllowed)
        XCTAssertFalse(safety.evaluate(base.appendingPathComponent("Backup/00008110-AAAA/Manifest.db")).isAllowed)
        XCTAssertFalse(safety.evaluate(base.appendingPathComponent("Other/x")).isAllowed)
        XCTAssertFalse(safety.evaluate(fx.raw(base.path.lowercased() + "/backup/x/y")).isAllowed)
        XCTAssertFalse(safety.evaluate(fx.raw(base.path + "/Backup/../Backup")).isAllowed)
    }

    func testBackupThroughSymlinkOutsideIsRefused() throws {
        let dir = try fx.dir("Library/Application Support/MobileSync/Backup")
        try fx.symlink("evil", to: fx.outside, in: dir)
        XCTAssertFalse(fx.safety.evaluate(dir.appendingPathComponent("evil")).isAllowed)
    }
}

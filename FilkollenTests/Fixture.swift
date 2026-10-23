import Foundation
@testable import Filkollen

/// A throwaway folder tree standing in for a home folder and its temp folder.
/// Removed when the fixture is released.
final class Fixture {
    let root: URL
    let home: URL
    let temp: URL
    private let fm = FileManager.default

    init(homeName: String = "home") throws {
        root = fm.temporaryDirectory.appendingPathComponent("FilkollenTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent(homeName, isDirectory: true)
        temp = root.appendingPathComponent("vf/T", isDirectory: true)
        for dir in [home, temp, root.appendingPathComponent("vf/C"), root.appendingPathComponent("outside")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        for sub in ["Library/Caches", "Library/Logs", "Library/Application Support", "Library/Preferences",
                    "Library/Keychains", "Library/Mobile Documents", "Library/Mail", "Pictures",
                    "Downloads", "Desktop", "Documents", ".Trash"] {
            try fm.createDirectory(at: home.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
    }

    deinit {
        // Unlock anything a test made read-only so cleanup can't fail.
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: nil) {
            for case let url as URL in e { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        try? fm.removeItem(at: root)
    }

    var safety: SafetyGuard { SafetyGuard(home: home, temp: temp) }

    /// Outside the fake home and temp: stands in for /etc, /System and other volumes.
    var outside: URL { root.appendingPathComponent("outside") }

    @discardableResult
    func file(_ relative: String, in base: URL? = nil, bytes: Int = 16, contents: Data? = nil,
              modified: Date? = nil) throws -> URL {
        let url = (base ?? home).appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = contents ?? Data((0..<bytes).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) })
        try data.write(to: url)
        if let modified {
            try fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    @discardableResult
    func dir(_ relative: String, in base: URL? = nil) throws -> URL {
        let url = (base ?? home).appendingPathComponent(relative, isDirectory: true)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func symlink(_ relative: String, to destination: URL, in base: URL? = nil) throws -> URL {
        let url = (base ?? home).appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: url, withDestinationURL: destination)
        return url
    }

    /// A scan context rooted in this fixture: fixed clock, no LaunchServices, only fixture apps.
    func context(
        running: [ScanContext.RunningApp] = [],
        now: Date = Date(),
        largeFileMinBytes: Int64 = 1_048_576
    ) -> ScanContext {
        ScanContext(
            home: home,
            temp: temp,
            now: { now },
            runningApps: { running },
            appRoots: [home.appendingPathComponent("Applications")],
            isRegisteredApp: { _ in false },
            tempMinAge: 3 * 24 * 3600,
            largeFileMinBytes: largeFileMinBytes
        )
    }

    /// A minimal app bundle that `Bundle(url:)` can read.
    @discardableResult
    func app(_ name: String, bundleID: String, in base: URL? = nil) throws -> URL {
        let app = (base ?? home.appendingPathComponent("Applications")).appendingPathComponent("\(name).app")
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleExecutable": name]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try file("Contents/Info.plist", in: app, contents: data)
        try file("Contents/MacOS/\(name)", in: app, bytes: 64)
        return app
    }

    /// Builds a URL from a raw path string, without any normalization by URL APIs.
    func raw(_ path: String) -> URL { URL(fileURLWithPath: path) }
}

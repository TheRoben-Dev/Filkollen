import Foundation

enum FileSizer {
    private static let keys: Set<URLResourceKey> = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey,
    ]

    /// On-disk size of a file, or the recursive size of a directory/package.
    static func allocatedSize(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return fileSize(url) }

        guard let enumerator = fm.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += fileSize(file)
        }
        return total
    }

    static func fileSize(_ url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isRegularFile == true else { return 0 }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}

/// Rate-limits progress callbacks so scanners don't flood the main thread.
final class ProgressThrottle: @unchecked Sendable {
    private let handler: @Sendable (String) -> Void
    private var last = Date.distantPast

    init(_ handler: @escaping @Sendable (String) -> Void) { self.handler = handler }

    func report(_ message: String) {
        let now = Date()
        guard now.timeIntervalSince(last) > 0.08 else { return }
        last = now
        handler(message)
    }
}

extension URL {
    /// `~/Library/Caches/foo` style path for display.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

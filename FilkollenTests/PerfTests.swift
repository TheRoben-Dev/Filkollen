import XCTest
@testable import Filkollen

/// Times the real scanners against the real home folder. Read-only (scanners
/// never delete). Skipped unless FILKOLLEN_PERF=1, e.g.
/// `TEST_RUNNER_FILKOLLEN_PERF=1 xcodebuild test -only-testing:FilkollenTests/PerfTests ...`
/// Uses only `Scanner().scan(progress:)` so the same file also runs against older commits.
final class PerfTests: XCTestCase {
    func testLiveScannerTimings() throws {
        guard ProcessInfo.processInfo.environment["FILKOLLEN_PERF"] == "1" else {
            throw XCTSkip("Set FILKOLLEN_PERF=1 to profile against the real home folder")
        }
        let quiet: @Sendable (String) -> Void = { _ in }
        let runs: [(String, () -> [JunkItem])] = [
            ("System Junk", { CacheScanner().scan(progress: quiet) }),
            ("App Leftovers", { LeftoverScanner().scan(progress: quiet) }),
            ("Duplicate Photos (1st)", { DuplicatePhotoScanner().scan(progress: quiet) }),
            ("Duplicate Photos (2nd)", { DuplicatePhotoScanner().scan(progress: quiet) }),
            ("Large Files", { LargeFileScanner().scan(progress: quiet) }),
        ]
        for (name, run) in runs {
            let start = Date()
            let items = run()
            let seconds = Date().timeIntervalSince(start)
            let bytes = items.reduce(Int64(0)) { $0 + $1.size }
            print(String(format: "PERF %@: %d items, %@ in %.2f s", name, items.count, bytes.formattedBytes, seconds))
        }
    }
}

import XCTest
@testable import Filkollen

final class CodeTrustTests: XCTestCase {
    /// Security warns when code checks run on the main thread, as the app never does.
    private func offMain<T>(_ body: @escaping @Sendable () -> T) -> T {
        let box = LockedBox<T?>(nil)
        let done = expectation(description: "checked")
        DispatchQueue.global().async { box.value = body(); done.fulfill() }
        wait(for: [done], timeout: 30)
        return box.value!
    }

    func testAppleBinaryIsApple() {
        XCTAssertEqual(offMain { CodeTrust.evaluate(URL(fileURLWithPath: "/bin/ls")).level }, .apple)
    }

    func testPlainFileIsUnsigned() throws {
        let fx = try Fixture()
        let script = try fx.file("Downloads/run.sh", contents: Data("#!/bin/sh\necho hi\n".utf8))
        let report = offMain { CodeTrust.evaluate(script) }
        XCTAssertEqual(report.level, .unsigned)
        XCTAssertTrue(report.level.isConcerning)
        XCTAssertNil(report.teamID)
    }

    func testOrdering() {
        XCTAssertTrue(CodeTrust.Level.invalid < .unsigned)
        XCTAssertTrue(CodeTrust.Level.adHoc.isConcerning)
        XCTAssertFalse(CodeTrust.Level.developerID.isConcerning)
    }
}

final class StartupItemHeuristicsTests: XCTestCase {
    func testInterpreterTargetsTheScript() {
        let r = StartupItems.runTarget(program: "/bin/bash", arguments: ["/bin/bash", "-l", "/Users/x/.hidden/run.sh"])
        XCTAssertEqual(r.target, "/Users/x/.hidden/run.sh")
        XCTAssertTrue(r.isScript)
        let env = StartupItems.runTarget(program: "/usr/bin/env", arguments: ["/usr/bin/env", "python3", "/opt/tool/agent.py"])
        XCTAssertEqual(env.target, "/opt/tool/agent.py")
        XCTAssertTrue(env.isScript)
        let inline = StartupItems.runTarget(program: "/bin/sh", arguments: ["/bin/sh", "-c", "curl x | sh"])
        XCTAssertEqual(inline.target, "/bin/sh")
        XCTAssertTrue(inline.isScript)
    }

    func testPlainProgramIsItsOwnTarget() {
        let r = StartupItems.runTarget(program: "/Applications/Foo.app/Contents/MacOS/Foo", arguments: [])
        XCTAssertEqual(r.target, "/Applications/Foo.app/Contents/MacOS/Foo")
        XCTAssertFalse(r.isScript)
        XCTAssertNil(StartupItems.runTarget(program: nil, arguments: []).target)
    }

    func testOddLocations() {
        for path in ["/tmp/x", "/private/tmp/a/b", "/Users/Shared/.x/agent", "/Users/me/Library/.cache/run",
                     "/private/var/folders/ab/xyz/T/payload"] {
            XCTAssertTrue(StartupItems.isOddLocation(path), path)
        }
        for path in ["/Applications/Foo.app/Contents/MacOS/Foo", "/usr/local/bin/tool", "/Users/me/Library/Application Support/Foo/agent"] {
            XCTAssertFalse(StartupItems.isOddLocation(path), path)
        }
    }
}

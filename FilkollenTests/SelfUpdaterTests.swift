import XCTest
@testable import Filkollen

final class SelfUpdaterTests: XCTestCase {
    func testOnlyConfiguredWithHTTPSFeedAndKey() {
        XCTAssertFalse(SelfUpdater.isConfigured(nil))
        XCTAssertFalse(SelfUpdater.isConfigured(["SUFeedURL": "", "SUPublicEDKey": ""]))
        XCTAssertFalse(SelfUpdater.isConfigured(["SUFeedURL": "http://example.com/a.xml", "SUPublicEDKey": "k"]))
        XCTAssertFalse(SelfUpdater.isConfigured(["SUFeedURL": "https://example.com/a.xml", "SUPublicEDKey": ""]))
        XCTAssertTrue(SelfUpdater.isConfigured(["SUFeedURL": "https://example.com/a.xml", "SUPublicEDKey": "k"]))
    }

    func testShippedBuildIsDormant() {
        // project.yml leaves both settings empty, so the app makes no update requests.
        XCTAssertFalse(SelfUpdater.isConfigured())
    }
}

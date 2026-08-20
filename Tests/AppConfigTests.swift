import XCTest
@testable import WhatsX

/// AppConfig.normalized enforces the https-only origin contract every network
/// path relies on (Api.makeURL rejects non-https; Realtime refuses ws://).
final class AppConfigTests: XCTestCase {

    func testEmptyStaysEmpty() {
        XCTAssertEqual(AppConfig.normalized(""), "")
        XCTAssertEqual(AppConfig.normalized("   "), "")
        XCTAssertEqual(AppConfig.normalized("/"), "")
    }

    func testBareDomainGainsHTTPS() {
        XCTAssertEqual(AppConfig.normalized("example.com"), "https://example.com")
    }

    func testPlainHTTPIsUpgraded() {
        XCTAssertEqual(AppConfig.normalized("http://example.com"), "https://example.com")
        XCTAssertEqual(AppConfig.normalized("HTTP://Example.com"), "https://Example.com")
    }

    func testHTTPSPreserved() {
        XCTAssertEqual(AppConfig.normalized("https://example.com"), "https://example.com")
    }

    func testTrailingSlashesAndWhitespaceTrimmed() {
        XCTAssertEqual(AppConfig.normalized("https://example.com///"), "https://example.com")
        XCTAssertEqual(AppConfig.normalized("  example.com/  "), "https://example.com")
    }

    func testPortAndPathSurvive() {
        XCTAssertEqual(AppConfig.normalized("example.com:8443"), "https://example.com:8443")
        XCTAssertEqual(AppConfig.normalized("https://example.com/whatsx"), "https://example.com/whatsx")
    }
}

import XCTest
@testable import WhatsX

final class SeriesPointTests: XCTestCase {

    private func decode(_ json: String) throws -> SeriesPoint {
        try JSONDecoder().decode(SeriesPoint.self, from: Data(json.utf8))
    }

    func testBucketBecomesTheIdentity() throws {
        let p = try decode(#"{"bucket": "2025-01-15", "incoming": 3, "outgoing": 5}"#)
        XCTAssertEqual(p.id, "2025-01-15")
        XCTAssertEqual(p.incoming, 3)
        XCTAssertEqual(p.outgoing, 5)
    }

    func testFallbackIdentityIsStableAcrossReads() throws {
        let p = try decode(#"{"incoming": 1, "outgoing": 2}"#)
        // The old implementation minted a new UUID on every access.
        XCTAssertEqual(p.id, p.id)
    }

    func testEqualityIgnoresFallbackIdentity() throws {
        let a = try decode(#"{"incoming": 1, "outgoing": 2}"#)
        let b = try decode(#"{"incoming": 1, "outgoing": 2}"#)
        XCTAssertNotEqual(a.fallbackID, b.fallbackID)
        XCTAssertEqual(a, b)
    }
}

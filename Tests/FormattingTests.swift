import XCTest
@testable import WhatsX

/// The backend emits both plain and fractional ISO-8601 timestamps; every
/// screen funnels them through parseISODate and the helpers below.
final class FormattingTests: XCTestCase {

    func testParsesPlainISO() {
        let date = parseISODate("2025-01-15T10:30:00Z")
        XCTAssertEqual(date?.timeIntervalSince1970, 1_736_937_000)
    }

    func testParsesFractionalISO() {
        let plain = parseISODate("2025-01-15T10:30:00Z")
        let fractional = parseISODate("2025-01-15T10:30:00.500Z")
        XCTAssertNotNil(fractional)
        XCTAssertEqual(fractional!.timeIntervalSince1970 - plain!.timeIntervalSince1970,
                       0.5, accuracy: 0.001)
    }

    func testRejectsGarbageAndNil() {
        XCTAssertNil(parseISODate(nil))
        XCTAssertNil(parseISODate(""))
        XCTAssertNil(parseISODate("15/01/2025"))
    }

    func testFormattersAreNilSafe() {
        XCTAssertEqual(clockTime(nil), "")
        XCTAssertEqual(shortTime(nil), "")
        XCTAssertEqual(dayClockTime(nil), "")
        XCTAssertEqual(clockTime("not-a-date"), "")
    }

    func testMimeTypeFromExtension() {
        XCTAssertEqual(mimeType(for: URL(fileURLWithPath: "/tmp/photo.jpg")), "image/jpeg")
        XCTAssertEqual(mimeType(for: URL(fileURLWithPath: "/tmp/doc.pdf")), "application/pdf")
        XCTAssertEqual(mimeType(for: URL(fileURLWithPath: "/tmp/unknown.zzz9")), "application/octet-stream")
        XCTAssertEqual(mimeType(for: URL(fileURLWithPath: "/tmp/noextension")), "application/octet-stream")
    }
}

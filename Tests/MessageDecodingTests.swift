import XCTest
@testable import WhatsX

/// Message carries a fully hand-written lenient decoder — server payloads
/// with free-form `raw`/`templatePreview` blobs must never fail the thread.
final class MessageDecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> Message {
        try JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    func testTypicalMessageDecodes() throws {
        let m = try decode(#"{"id": "m1", "direction": "outbound", "body": "hi", "createdAt": "2025-01-15T10:30:00Z"}"#)
        XCTAssertEqual(m.id, "m1")
        XCTAssertTrue(m.isOutbound)
        XCTAssertEqual(m.body, "hi")
    }

    func testEmptyObjectDecodesWithDefaults() throws {
        let m = try decode("{}")
        XCTAssertEqual(m.id, "")
        XCTAssertFalse(m.isOutbound)
        XCTAssertNil(m.body)
    }

    func testWrongFieldTypesDegradeInsteadOfThrowing() throws {
        let m = try decode(#"{"id": 123, "body": ["array"], "direction": "inbound", "media": "not-an-object"}"#)
        XCTAssertEqual(m.id, "")
        XCTAssertNil(m.body)
        XCTAssertEqual(m.direction, "inbound")
        XCTAssertNil(m.media)
    }

    func testTemplateFlagRequiresContent() throws {
        let plain = try decode(#"{"id": "m2"}"#)
        XCTAssertFalse(plain.isTemplateMessage)
        let templated = try decode(#"{"id": "m3", "templateName": "welcome"}"#)
        XCTAssertTrue(templated.isTemplateMessage)
    }
}

import XCTest
@testable import WhatsX

/// Meta rejects SDP with bare-LF line endings; every SDP that crosses the
/// wire goes through CallSDP.normalize (same contract as Android/web).
final class CallSDPTests: XCTestCase {

    func testBareLFBecomesCRLF() {
        XCTAssertEqual(CallSDP.normalize("v=0\no=- 1 1 IN IP4 0.0.0.0\n"),
                       "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n")
    }

    func testExistingCRLFIsPreservedNotDoubled() {
        XCTAssertEqual(CallSDP.normalize("v=0\r\ns=-\r\n"), "v=0\r\ns=-\r\n")
    }

    func testMixedEndingsAreUnified() {
        XCTAssertEqual(CallSDP.normalize("a=1\r\nb=2\nc=3"), "a=1\r\nb=2\r\nc=3\r\n")
    }

    func testTrailingCRLFIsAppendedWhenMissing() {
        XCTAssertEqual(CallSDP.normalize("v=0"), "v=0\r\n")
    }

    func testCallRequestEncodesTheExpectedKeys() throws {
        let body = WhatsAppCallRequest(to: "9647701234567", sdp: "v=0\r\n",
                                       displayName: "Test", instanceId: "inst1")
        let json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(body)) as? [String: Any]
        XCTAssertEqual(json?["to"] as? String, "9647701234567")
        XCTAssertEqual(json?["sdp"] as? String, "v=0\r\n")
        XCTAssertEqual(json?["displayName"] as? String, "Test")
        XCTAssertEqual(json?["instanceId"] as? String, "inst1")
    }

    func testPermissionNoticeTurns138017IntoGoodNews() {
        let raw = #"Meta permission request failed: {"error":{"message":"(#138017) Unable to send call permission request as the business account can already call this consumer","code":138017}}"#
        let friendly = CallPermissionNotice.friendly(raw)
        XCTAssertFalse(friendly.contains("138017"))
        XCTAssertFalse(friendly.contains("{"))
        XCTAssertTrue(friendly.contains("✓"))
    }

    func testPermissionNoticeHidesRawJSONDumps() {
        let raw = #"{"error":{"message":"something else entirely","code":1}}"#
        XCTAssertFalse(CallPermissionNotice.friendly(raw).contains("{"))
    }

    func testPermissionNoticeKeepsShortHumanMessages() {
        XCTAssertEqual(CallPermissionNotice.friendly("Server unavailable"), "Server unavailable")
    }

    func testCallResponseToleratesPartialPayloads() throws {
        let full = try JSONDecoder().decode(WhatsAppCallResponse.self,
                                            from: Data(#"{"callId": "c1", "answer": "v=0"}"#.utf8))
        XCTAssertEqual(full.callId, "c1")
        XCTAssertEqual(full.answer, "v=0")

        let bare = try JSONDecoder().decode(WhatsAppCallResponse.self, from: Data("{}".utf8))
        XCTAssertNil(bare.callId)
        XCTAssertNil(bare.answer)
    }
}

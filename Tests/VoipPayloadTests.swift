import XCTest
@testable import WhatsX

final class VoipPayloadTests: XCTestCase {

    func testFullPayloadParses() {
        let call = VoipPayload.parse([
            "type": "voice_call_incoming",
            "callId": "c1",
            "displayName": "Test Clinic",
            "phone": "9647701234567",
            "instanceId": "i1",
            "sdpOffer": "v=0\r\n",
        ])
        XCTAssertEqual(call, VoipPayload.Call(
            callId: "c1", displayName: "Test Clinic", phone: "9647701234567",
            instanceId: "i1", sdpOffer: "v=0\r\n"))
    }

    /// The server may nest the payload under "whatsx" (aps sibling keys).
    func testNestedPayloadParses() {
        let call = VoipPayload.parse([
            "aps": ["alert": ""],
            "whatsx": ["type": "voice_call_incoming", "callId": "c2"],
        ])
        XCTAssertEqual(call?.callId, "c2")
        XCTAssertNil(call?.sdpOffer)
    }

    func testMissingCallIdIsRejected() {
        XCTAssertNil(VoipPayload.parse(["type": "voice_call_incoming"]))
        XCTAssertNil(VoipPayload.parse(["type": "voice_call_incoming", "callId": ""]))
        XCTAssertNil(VoipPayload.parse([:]))
    }

    func testForeignTypeIsRejectedButMissingTypeTolerated() {
        XCTAssertNil(VoipPayload.parse(["type": "something_else", "callId": "c1"]))
        // No type field at all: accept — the callId is the real contract.
        XCTAssertEqual(VoipPayload.parse(["callId": "c3"])?.callId, "c3")
    }

    func testEmptyOptionalFieldsBecomeNil() {
        let call = VoipPayload.parse(["callId": "c4", "displayName": "", "phone": ""])
        XCTAssertNil(call?.displayName)
        XCTAssertNil(call?.phone)
    }

    func testHexTokenEncoding() {
        XCTAssertEqual(VoipPayload.hexToken(Data([0x00, 0xAB, 0xFF, 0x10])), "00abff10")
        XCTAssertEqual(VoipPayload.hexToken(Data()), "")
    }

    func testVoipTokenRequestEncodesDefaults() throws {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(VoipTokenRequest(token: "ab12"))) as? [String: Any])
        XCTAssertEqual(json["token"] as? String, "ab12")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["environment"] as? String, "production")
    }

    func testCallOfferResponseDecodes() throws {
        let full = try JSONDecoder().decode(CallOfferResponse.self,
                                            from: Data(#"{"sdpOffer": "v=0"}"#.utf8))
        XCTAssertEqual(full.sdpOffer, "v=0")
        let empty = try JSONDecoder().decode(CallOfferResponse.self, from: Data("{}".utf8))
        XCTAssertNil(empty.sdpOffer)
    }
}

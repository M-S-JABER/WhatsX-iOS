import XCTest
@testable import WhatsX

final class MessagePushTests: XCTestCase {

    func testFlatPayloadYieldsConversationId() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "أحمد", "body": "رسالة جديدة"]],
            "type": "message_incoming",
            "conversationId": "c42",
        ]
        XCTAssertEqual(MessagePushPayload.conversationId(from: userInfo), "c42")
    }

    func testNestedPayloadYieldsConversationId() {
        let userInfo: [AnyHashable: Any] = [
            "whatsx": ["type": "message_incoming", "conversationId": "c7"],
        ]
        XCTAssertEqual(MessagePushPayload.conversationId(from: userInfo), "c7")
    }

    /// An untyped payload with a conversationId still routes — the type key
    /// is a guard against OTHER typed pushes, not a requirement.
    func testMissingTypeIsTolerated() {
        XCTAssertEqual(MessagePushPayload.conversationId(from: ["conversationId": "c1"]), "c1")
    }

    func testForeignTypeIsRejected() {
        let userInfo: [AnyHashable: Any] = [
            "type": "voice_call_incoming",
            "conversationId": "c1",
        ]
        XCTAssertNil(MessagePushPayload.conversationId(from: userInfo))
    }

    func testMissingOrEmptyConversationIdYieldsNil() {
        XCTAssertNil(MessagePushPayload.conversationId(from: ["type": "message_incoming"]))
        XCTAssertNil(MessagePushPayload.conversationId(from: ["conversationId": ""]))
        XCTAssertNil(MessagePushPayload.conversationId(from: [:]))
    }

    /// A payload that dropped the custom key still routes via aps.thread-id
    /// (the spec sets both to the conversation id).
    func testThreadIdFallback() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "أحمد"], "thread-id": "c9"],
        ]
        XCTAssertEqual(MessagePushPayload.conversationId(from: userInfo), "c9")
    }

    func testExplicitConversationIdWinsOverThreadId() {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["thread-id": "wrong"],
            "conversationId": "right",
        ]
        XCTAssertEqual(MessagePushPayload.conversationId(from: userInfo), "right")
    }

    func testHexTokenEncoding() {
        XCTAssertEqual(VoipPayload.hexToken(Data([0x00, 0xAB, 0xFF])), "00abff")
        XCTAssertEqual(VoipPayload.hexToken(Data()), "")
    }
}

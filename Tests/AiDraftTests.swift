import XCTest
@testable import WhatsX

final class AiDraftTests: XCTestCase {

    // MARK: - Decoding

    func testFullDraftDecodes() throws {
        let json = """
        {"draft": {
            "id": "d1", "conversationId": "c1", "instanceId": "i1",
            "status": "ready", "channel": "lab",
            "draftText": "نتيجة {PATIENT_NAME} جاهزة",
            "sources": ["HbA1c", "CBC"],
            "escalate": true, "escalateReason": "anger",
            "error": null, "instruction": null,
            "createdAt": "2026-08-20T10:00:00Z", "readyAt": "2026-08-20T10:00:05Z",
            "expiresAt": null
        }}
        """
        let env = try JSONDecoder().decode(AiDraftEnvelope.self, from: Data(json.utf8))
        let d = try XCTUnwrap(env.draft)
        XCTAssertEqual(d.id, "d1")
        XCTAssertEqual(d.status, "ready")
        XCTAssertTrue(d.isReady)
        XCTAssertTrue(d.isDisplayable)
        XCTAssertEqual(d.sources, ["HbA1c", "CBC"])
        XCTAssertTrue(d.escalate)
        XCTAssertEqual(d.escalateReason, "anger")
    }

    func testNullDraftEnvelopeDecodes() throws {
        let env = try JSONDecoder().decode(AiDraftEnvelope.self, from: Data(#"{"draft": null}"#.utf8))
        XCTAssertNil(env.draft)
    }

    /// Only scheduled/requesting/ready/failed render anything; every other
    /// status — including ones the server may add later — renders nothing.
    func testDisplayableStatusMatrix() throws {
        func draft(_ status: String) throws -> AiDraft {
            try JSONDecoder().decode(
                AiDraft.self,
                from: Data(#"{"id": "d", "conversationId": "c", "status": "\#(status)"}"#.utf8))
        }
        for status in ["scheduled", "requesting"] {
            XCTAssertTrue(try draft(status).isPending, status)
            XCTAssertTrue(try draft(status).isDisplayable, status)
        }
        XCTAssertTrue(try draft("ready").isReady)
        XCTAssertTrue(try draft("failed").isFailed)
        for status in ["cancelled", "sent_as_is", "edited", "ignored",
                       "regenerated", "discarded", "some_future_status", ""] {
            XCTAssertFalse(try draft(status).isDisplayable, status)
        }
    }

    func testConversationMetadataCarriesEscalation() throws {
        let json = """
        {"id": "c1", "metadata": {"aiEscalate": {"reason": "anger", "at": "2026-08-19T10:00:00Z"}}}
        """
        let conv = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        XCTAssertEqual(conv.metadata?.aiEscalate?.reason, "anger")

        let cleared = try JSONDecoder().decode(
            Conversation.self, from: Data(#"{"id": "c1", "metadata": {}}"#.utf8))
        XCTAssertNil(cleared.metadata?.aiEscalate)
    }

    func testAuthUserPermissions() throws {
        let json = #"{"id": "u1", "username": "op", "effectivePermissions": ["chats.send", "aiDrafts.view"]}"#
        let user = try JSONDecoder().decode(AuthUser.self, from: Data(json.utf8))
        XCTAssertTrue(user.can("aiDrafts.view"))
        XCTAssertFalse(user.can("aiDrafts.use"))

        // Older servers without the field gate every permission off.
        let old = try JSONDecoder().decode(AuthUser.self, from: Data(#"{"id": "u1", "username": "op"}"#.utf8))
        XCTAssertFalse(old.can("aiDrafts.view"))
    }

    // MARK: - Send attribution encoding

    func testSendRequestEncodesAttribution() throws {
        let body = SendMessageRequest(conversationId: "c1", body: "نص",
                                      aiDraft: AiDraftAttribution(draftId: "d1", action: "sent_as_is"))
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(body)) as? [String: Any])
        let aiDraft = try XCTUnwrap(json["aiDraft"] as? [String: Any])
        XCTAssertEqual(aiDraft["draftId"] as? String, "d1")
        XCTAssertEqual(aiDraft["action"] as? String, "sent_as_is")
    }

    /// A reply typed from scratch must OMIT the aiDraft key entirely — its
    /// absence is what the server records as "ignored".
    func testSendRequestOmitsAttributionWhenAbsent() throws {
        let body = SendMessageRequest(conversationId: "c1", body: "نص")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(body)) as? [String: Any])
        XCTAssertNil(json["aiDraft"])
        XCTAssertNil(json["replyToMessageId"])
    }

    // MARK: - Placeholders

    func testPlaceholderSegmentation() {
        let segs = AiDraftPlaceholders.segments(of: "مرحباً {PATIENT_NAME}، رقم زيارتك {VISIT_ID}.")
        XCTAssertEqual(segs, [
            .init(text: "مرحباً ", isPlaceholder: false),
            .init(text: "{PATIENT_NAME}", isPlaceholder: true),
            .init(text: "، رقم زيارتك ", isPlaceholder: false),
            .init(text: "{VISIT_ID}", isPlaceholder: true),
            .init(text: ".", isPlaceholder: false),
        ])
    }

    func testPlaceholderFreeTextIsOneLiteralSegment() {
        XCTAssertEqual(AiDraftPlaceholders.segments(of: "نص عادي"),
                       [.init(text: "نص عادي", isPlaceholder: false)])
        XCTAssertFalse(AiDraftPlaceholders.contains("نص عادي"))
    }

    func testUnknownBraceTokensAreNotPlaceholders() {
        let segs = AiDraftPlaceholders.segments(of: "قيمة {FOO} و{PHONE}")
        XCTAssertEqual(segs, [
            .init(text: "قيمة {FOO} و", isPlaceholder: false),
            .init(text: "{PHONE}", isPlaceholder: true),
        ])
    }

    func testAdjacentPlaceholders() {
        let segs = AiDraftPlaceholders.segments(of: "{REG_NO}{PHONE}")
        XCTAssertEqual(segs, [
            .init(text: "{REG_NO}", isPlaceholder: true),
            .init(text: "{PHONE}", isPlaceholder: true),
        ])
        XCTAssertTrue(AiDraftPlaceholders.contains("{REG_NO}{PHONE}"))
    }

    func testEmptyTextYieldsNoSegments() {
        XCTAssertEqual(AiDraftPlaceholders.segments(of: ""), [])
    }
}

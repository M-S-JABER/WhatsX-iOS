import XCTest
@testable import WhatsX

/// The lenient-decoding helpers are the app's defense against server JSON
/// drift — a malformed field must degrade, never sink a whole screen.
final class LenientDecodingTests: XCTestCase {

    private struct Wrapper: Decodable {
        var count: Int? = nil
        var name: String = "fallback"
        var tags: [String] = []

        private enum CodingKeys: String, CodingKey { case count, name, tags }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            count = c.lenient(Int.self, forKey: .count)
            name = c.lenient(String.self, forKey: .name, default: "fallback")
            tags = c.lossy(String.self, forKey: .tags)
        }
    }

    private func decode(_ json: String) throws -> Wrapper {
        try JSONDecoder().decode(Wrapper.self, from: Data(json.utf8))
    }

    func testLossyArrayDropsMalformedElements() throws {
        let arr = try JSONDecoder().decode(LossyArray<Int>.self,
                                           from: Data("[1, \"x\", 2, null, 3]".utf8))
        XCTAssertEqual(arr.elements, [1, 2, 3])
    }

    func testLenientToleratesTypeMismatch() throws {
        let w = try decode(#"{"count": "twelve", "name": 42, "tags": ["a", 1, "b"]}"#)
        XCTAssertNil(w.count)
        XCTAssertEqual(w.name, "fallback")
        XCTAssertEqual(w.tags, ["a", "b"])
    }

    func testLenientToleratesMissingKeysAndNulls() throws {
        let w = try decode(#"{"count": null, "tags": null}"#)
        XCTAssertNil(w.count)
        XCTAssertEqual(w.name, "fallback")
        XCTAssertEqual(w.tags, [])
    }

    func testLossyToleratesNonArrayValue() throws {
        let w = try decode(#"{"tags": "not-an-array"}"#)
        XCTAssertEqual(w.tags, [])
    }

    func testHappyPathStillDecodes() throws {
        let w = try decode(#"{"count": 5, "name": "ok", "tags": ["x"]}"#)
        XCTAssertEqual(w.count, 5)
        XCTAssertEqual(w.name, "ok")
        XCTAssertEqual(w.tags, ["x"])
    }
}

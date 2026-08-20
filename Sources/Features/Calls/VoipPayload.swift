import Foundation

// VoIP push payload contract with the backend (docs/VOIP_PUSH.md). Kept free
// of PushKit imports so the parsing logic unit-tests everywhere.
//
// Expected dictionary (all string values):
//   {
//     "type": "voice_call_incoming",
//     "callId": "...",                  // required
//     "displayName": "...", "phone": "...", "instanceId": "...",
//     "sdpOffer": "v=0\r\n..."          // optional — omitted when it would
//   }                                   //   push the payload past APNs' 5KB
enum VoipPayload {
    static let incomingType = "voice_call_incoming"

    struct Call: Equatable {
        let callId: String
        var displayName: String? = nil
        var phone: String? = nil
        var instanceId: String? = nil
        var sdpOffer: String? = nil
    }

    /// nil when the payload is not an incoming-call push or lacks a callId.
    static func parse(_ dict: [AnyHashable: Any]) -> Call? {
        // Tolerate both a flat payload and one nested under "whatsx".
        let root = (dict["whatsx"] as? [AnyHashable: Any]) ?? dict
        if let type = root["type"] as? String, type != incomingType { return nil }
        guard let callId = root["callId"] as? String, !callId.isEmpty else { return nil }
        return Call(
            callId: callId,
            displayName: nonEmpty(root["displayName"]),
            phone: nonEmpty(root["phone"]),
            instanceId: nonEmpty(root["instanceId"]),
            sdpOffer: nonEmpty(root["sdpOffer"])
        )
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = value as? String, !s.isEmpty else { return nil }
        return s
    }

    /// APNs device tokens travel as lowercase hex.
    static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

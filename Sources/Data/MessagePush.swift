import Foundation

// Remote message notifications (standard APNs alert pushes) — the contract
// lives in docs/VOIP_PUSH.md ("Message alert pushes"). The server sends
// sender-name-only content (a privacy decision by the owner: message text
// never transits Apple), plus a conversationId used to open the right chat
// when the user taps the banner.

/// Pure payload helpers, kept UIKit-free so they unit-test everywhere.
enum MessagePushPayload {
    static let incomingType = "message_incoming"

    /// The conversation a tapped message notification should open, or nil
    /// when the payload is not a message push.
    static func conversationId(from userInfo: [AnyHashable: Any]) -> String? {
        // Tolerate both a flat payload and one nested under "whatsx".
        let root = (userInfo["whatsx"] as? [AnyHashable: Any]) ?? userInfo
        if let type = root["type"] as? String, type != incomingType { return nil }
        guard let id = root["conversationId"] as? String, !id.isEmpty else { return nil }
        return id
    }
}

/// Uploads the standard APNs device token (distinct from the VoIP token) to
/// the customer's server so it can notify this device about new messages
/// while the app is closed. Mirrors VoIPPush's tolerance: a server that
/// predates the endpoint answers 404 and the upload silently retries on the
/// next login.
final class MessagePush {
    static let shared = MessagePush()

    private var pendingToken: String?

    /// Called by the app delegate when iOS hands over the device token
    /// (registration itself is requested in Notifier.start()).
    func tokenReceived(_ hexToken: String) {
        pendingToken = hexToken
        upload(hexToken)
    }

    /// Call once authenticated — pushes the cached token to the server.
    func syncToken() {
        upload(pendingToken)
    }

    private func upload(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        Task { @MainActor in
            guard Session.shared.isAuthenticated else { return }
            try? await Api.shared.registerPushToken(token)
        }
    }
}

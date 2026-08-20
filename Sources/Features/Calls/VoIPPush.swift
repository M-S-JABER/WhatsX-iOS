import Foundation

#if canImport(PushKit)
import PushKit

// VoIP push registration + receipt. The push is what makes a call ring while
// the app is closed: iOS launches the app in the background, hands over the
// payload, and (Apple's hard rule since iOS 13) the app MUST surface a
// CallKit call before the delegate callback returns — every path below ends
// in a report, even for malformed payloads.
//
// The token is registered with the customer's own server (self-hosted model)
// via POST api/devices/voip-token; the server sends the pushes
// (docs/VOIP_PUSH.md). A server that predates the endpoint answers 404 and
// the upload is silently retried on the next login.
final class VoIPPush: NSObject {
    static let shared = VoIPPush()

    private var registry: PKPushRegistry?
    private var pendingToken: String?

    /// Call at app launch (before any UI): a push that cold-starts the app
    /// must find the registry already in place.
    func activate() {
        guard CallAudioEngine.isSupported, registry == nil else { return }
        let r = PKPushRegistry(queue: .main)
        r.delegate = self
        r.desiredPushTypes = [.voIP]
        registry = r
    }

    /// Call once authenticated — pushes the cached token to the server
    /// (registration can fire before login completes).
    func syncToken() {
        upload(pendingToken)
    }

    private func upload(_ token: String?) {
        guard let token, !token.isEmpty else { return }
        Task { @MainActor in
            guard Session.shared.isAuthenticated else { return }
            // Endpoint may not exist yet server-side (404) — stay silent;
            // the next login retries via syncToken().
            try? await Api.shared.registerVoipToken(token)
        }
    }
}

extension VoIPPush: PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials,
                      for type: PKPushType) {
        guard type == .voIP else { return }
        let token = VoipPayload.hexToken(pushCredentials.token)
        pendingToken = token
        upload(token)
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        pendingToken = nil
    }

    func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                      for type: PKPushType, completion: @escaping () -> Void) {
        guard type == .voIP else { completion(); return }
        // On a background cold start nothing has restored the session yet;
        // the answer POST needs the cookie in place.
        CookieVault.restore()
        let call = VoipPayload.parse(payload.dictionaryPayload)
        // Delegate queue is main, so the MainActor hop is synchronous — the
        // CallKit report happens before this callback returns, as required.
        MainActor.assumeIsolated {
            CallCenter.shared.handleVoipPush(call)
        }
        completion()
    }
}

#else

/// Platforms without PushKit (macOS package builds): inert.
final class VoIPPush {
    static let shared = VoIPPush()
    func activate() {}
    func syncToken() {}
}

#endif

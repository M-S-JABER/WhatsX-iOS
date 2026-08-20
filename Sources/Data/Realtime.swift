import Foundation
import Combine

// Live updates over the backend's `/ws` WebSocket (same cookie session auth
// as REST — the passport cookie in the shared cookie storage authenticates
// the upgrade request automatically).
//
// The server pushes JSON envelopes `{ "event": "...", "data": {...} }` for:
//   message_incoming · message_outgoing · message_status ·
//   message_media_updated · conversation_pin_updated ·
//   conversation_archive_updated · voice_call_incoming · voice_call_updated ·
//   voice_call_claimed · integration_message_created ·
//   integration_message_status
//
// `data` shapes vary per event, so only the routing fields are decoded here;
// consumers treat events as invalidation signals and refetch via REST.

/// One pushed server event, reduced to what consumers route on. Message
/// events fill body/senderLabel; voice-call events fill callId/phone/
/// displayName/status. Everything is optional — shapes vary per event.
struct RealtimeEvent {
    let name: String
    let conversationId: String?
    var body: String? = nil
    var senderLabel: String? = nil
    var callId: String? = nil
    var phone: String? = nil
    var displayName: String? = nil
    var status: String? = nil
    /// Call signaling: the remote SDP. Carries the OFFER on a fresh inbound
    /// ring, and (with sdpType == "answer") the ANSWER to our outbound offer.
    var sdpOffer: String? = nil
    var sdpType: String? = nil
    var instanceId: String? = nil
    /// ai_draft_* events carry the full draft — consumers render from it
    /// directly instead of refetching after every event.
    var draft: AiDraft? = nil
}

@MainActor
final class Realtime: ObservableObject {
    static let shared = Realtime()

    /// Fires on the main thread for every decoded server event.
    let events = PassthroughSubject<RealtimeEvent, Never>()
    @Published private(set) var isConnected = false

    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var activityTimer: Timer?
    private var reconnectAttempt = 0
    private var wantsConnection = false

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = SessionCookies.store
        cfg.httpShouldSetCookies = true
        return URLSession(configuration: cfg)
    }()

    private struct Envelope: Decodable {
        let event: String
        let data: Routing?
        // Lenient per-field decoding — payload shapes vary per event and an
        // unexpected type in one field must never drop the whole event.
        struct Routing: Decodable {
            var conversationId: String? = nil
            var body: String? = nil
            var senderLabel: String? = nil
            var callId: String? = nil
            var phone: String? = nil
            var displayName: String? = nil
            var status: String? = nil
            var sdpOffer: String? = nil
            var sdpType: String? = nil
            var instanceId: String? = nil
            var draft: AiDraft? = nil

            private enum CodingKeys: String, CodingKey {
                case conversationId, body, senderLabel, callId, phone, displayName, status
                case sdpOffer, sdpType, instanceId, draft
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                conversationId = (try? c.decodeIfPresent(String.self, forKey: .conversationId)) ?? nil
                body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? nil
                senderLabel = (try? c.decodeIfPresent(String.self, forKey: .senderLabel)) ?? nil
                callId = (try? c.decodeIfPresent(String.self, forKey: .callId)) ?? nil
                phone = (try? c.decodeIfPresent(String.self, forKey: .phone)) ?? nil
                displayName = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
                status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
                sdpOffer = (try? c.decodeIfPresent(String.self, forKey: .sdpOffer)) ?? nil
                sdpType = (try? c.decodeIfPresent(String.self, forKey: .sdpType)) ?? nil
                instanceId = (try? c.decodeIfPresent(String.self, forKey: .instanceId)) ?? nil
                draft = (try? c.decodeIfPresent(AiDraft.self, forKey: .draft)) ?? nil
            }
        }
    }

    /// Start (or restart) the connection. Call once the user is authenticated.
    func connect() {
        wantsConnection = true
        reconnectAttempt = 0
        openIfNeeded()
        startActivityHeartbeat()
    }

    /// Tear down the connection. Call on logout.
    func disconnect() {
        wantsConnection = false
        pingTimer?.invalidate()
        pingTimer = nil
        activityTimer?.invalidate()
        activityTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    /// Presence heartbeat — stamps last-active on the server every minute.
    private func startActivityHeartbeat() {
        activityTimer?.invalidate()
        Task { try? await Api.shared.activityPing() }
        activityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { try? await Api.shared.activityPing() }
        }
    }

    private func wsURL() -> URL? {
        // https only (AppConfig normalizes to it) — never downgrade to ws://.
        var base = AppConfig.baseURL.trimmed()
        guard base.hasPrefix("https://") else { return nil }
        base = "wss://" + base.dropFirst("https://".count)
        return URL(string: base + "/ws")
    }

    private func openIfNeeded() {
        guard wantsConnection, task == nil, let url = wsURL() else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        // Don't report "connected" just because resume() was called — an
        // immediate ping confirms the upgrade actually succeeded (its
        // completion is queued until the handshake resolves either way).
        t.sendPing { [weak self] error in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                if error == nil {
                    self.isConnected = true
                    self.reconnectAttempt = 0
                } else {
                    self.handleDrop()
                }
            }
        }
        listen(on: t)
        startPing()
    }

    private func listen(on t: URLSessionWebSocketTask) {
        t.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === t else { return }
                switch result {
                case .failure:
                    self.handleDrop()
                case .success(let message):
                    self.reconnectAttempt = 0
                    self.isConnected = true
                    self.handle(message)
                    self.listen(on: t)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let payload: Data?
        switch message {
        case .string(let text): payload = text.data(using: .utf8)
        case .data(let data): payload = data
        @unknown default: payload = nil
        }
        guard let payload,
              let envelope = try? JSONDecoder().decode(Envelope.self, from: payload) else { return }
        events.send(RealtimeEvent(
            name: envelope.event,
            conversationId: envelope.data?.conversationId,
            body: envelope.data?.body,
            senderLabel: envelope.data?.senderLabel,
            callId: envelope.data?.callId,
            phone: envelope.data?.phone,
            displayName: envelope.data?.displayName,
            status: envelope.data?.status,
            sdpOffer: envelope.data?.sdpOffer,
            sdpType: envelope.data?.sdpType,
            instanceId: envelope.data?.instanceId,
            draft: envelope.data?.draft
        ))
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let t = self.task else { return }
                t.sendPing { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor in
                        // A ping failure can arrive after a reconnect has
                        // already replaced the socket — acting on it would
                        // kill the healthy new connection (listen(on:) has
                        // the same guard).
                        guard let self, self.task === t else { return }
                        self.handleDrop()
                    }
                }
            }
        }
    }

    private func handleDrop() {
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
        guard wantsConnection else { return }
        reconnectAttempt += 1
        // An expired cookie fails the upgrade exactly like a network drop, so
        // blind retries would loop forever while the app looks "online".
        // Every third consecutive failure, probe the REST session: a 401
        // routes through Session.handleUnauthorized → disconnect(), which
        // ends this loop and returns the user to the login screen.
        if reconnectAttempt.isMultiple(of: 3) {
            Task { _ = try? await Api.shared.me() }
        }
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.openIfNeeded()
        }
    }
}

extension RealtimeEvent {
    /// Events that change the conversation list (previews, unread, order).
    /// ai_draft_* are included because escalation writes/clears
    /// conversations.metadata.aiEscalate, which the inbox rows mark.
    static let inboxEvents: Set<String> = [
        "message_incoming", "message_outgoing", "message_status",
        "conversation_pin_updated", "conversation_archive_updated",
        "ai_draft_ready", "ai_draft_resolved",
    ]
    /// AI-draft lifecycle events; each carries the full draft in `draft`.
    static let aiDraftEvents: Set<String> = [
        "ai_draft_scheduled", "ai_draft_ready", "ai_draft_failed", "ai_draft_resolved",
    ]
    /// Events that change an open chat's transcript.
    static let chatEvents: Set<String> = [
        "message_incoming", "message_outgoing", "message_status", "message_media_updated",
    ]
    /// Events that change the call log.
    static let callEvents: Set<String> = [
        "voice_call_incoming", "voice_call_updated", "voice_call_claimed",
    ]
}

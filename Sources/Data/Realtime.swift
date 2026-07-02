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

/// One pushed server event, reduced to what consumers route on.
struct RealtimeEvent {
    let name: String
    let conversationId: String?
}

@MainActor
final class Realtime: ObservableObject {
    static let shared = Realtime()

    /// Fires on the main thread for every decoded server event.
    let events = PassthroughSubject<RealtimeEvent, Never>()
    @Published private(set) var isConnected = false

    private var task: URLSessionWebSocketTask?
    private var pingTimer: Timer?
    private var reconnectAttempt = 0
    private var wantsConnection = false

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpShouldSetCookies = true
        return URLSession(configuration: cfg)
    }()

    private struct Envelope: Decodable {
        let event: String
        let data: Routing?
        struct Routing: Decodable {
            let conversationId: String?
        }
    }

    /// Start (or restart) the connection. Call once the user is authenticated.
    func connect() {
        wantsConnection = true
        reconnectAttempt = 0
        openIfNeeded()
    }

    /// Tear down the connection. Call on logout.
    func disconnect() {
        wantsConnection = false
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        isConnected = false
    }

    private func wsURL() -> URL? {
        var base = AppConfig.baseURL.trimmed()
        if base.hasPrefix("https://") { base = "wss://" + base.dropFirst("https://".count) }
        else if base.hasPrefix("http://") { base = "ws://" + base.dropFirst("http://".count) }
        return URL(string: base + "/ws")
    }

    private func openIfNeeded() {
        guard wantsConnection, task == nil, let url = wsURL() else { return }
        let t = session.webSocketTask(with: url)
        task = t
        t.resume()
        isConnected = true
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
        events.send(RealtimeEvent(name: envelope.event, conversationId: envelope.data?.conversationId))
    }

    private func startPing() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let t = self.task else { return }
                t.sendPing { [weak self] error in
                    guard error != nil else { return }
                    Task { @MainActor in self?.handleDrop() }
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
        let delay = min(30.0, pow(2.0, Double(min(reconnectAttempt, 5))))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.openIfNeeded()
        }
    }
}

extension RealtimeEvent {
    /// Events that change the conversation list (previews, unread, order).
    static let inboxEvents: Set<String> = [
        "message_incoming", "message_outgoing", "message_status",
        "conversation_pin_updated", "conversation_archive_updated",
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

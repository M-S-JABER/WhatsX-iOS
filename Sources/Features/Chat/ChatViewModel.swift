import SwiftUI
import AVFoundation

// Records a short voice note to a temp .m4a file (AAC) for upload via /api/upload.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in self?.beginRecording() }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.record()
        recorder = rec; fileURL = url; isRecording = true; elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    /// Stops and returns the recorded audio data (nil if empty/too short).
    func stop() -> Data? {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard elapsed >= 1, let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var calls: [VoiceCall] = []
    @Published var loading = false
    @Published var loadError: String?
    @Published var input = ""
    @Published var sending = false
    @Published var attachError: String?
    @Published var replyTarget: Message? = nil
    /// Messages merged chronologically with the conversation's call events —
    /// rebuilt only when messages/calls change, never during body evaluation
    /// (the merge+sort is too heavy to run on every keystroke).
    @Published private(set) var timeline: [ChatEntry] = []
    let conversation: Conversation

    private var realtimeReloadTask: Task<Void, Never>?

    init(conversation: Conversation) { self.conversation = conversation }

    private func rebuildTimeline() {
        let entries: [(entry: ChatEntry, date: Date, order: Int)] =
            messages.enumerated().map { (i, m) in (ChatEntry.message(m), parseISODate(m.createdAt) ?? .distantPast, i) }
            + calls.enumerated().map { (i, c) in (ChatEntry.call(c), parseISODate(c.startedAt) ?? .distantPast, i) }
        let sorted = entries.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.order < b.order
        }
        var out: [ChatEntry] = []
        var lastDay: String? = nil
        for item in sorted {
            if item.date != .distantPast {
                let day = dayLabel(item.date)
                if day != lastDay {
                    out.append(.day(day))
                    lastDay = day
                }
            }
            out.append(item.entry)
        }
        timeline = out
    }

    func load() async {
        loading = messages.isEmpty
        await loadMessages()
        // Requires calls.view — silently absent for roles without it.
        calls = (try? await Api.shared.conversationCalls(conversationId: conversation.id).items) ?? []
        rebuildTimeline()
        loading = false
    }

    /// Refetch the transcript only — realtime message events don't touch the
    /// call log, so reloading calls on every event was wasted work.
    func loadMessages() async {
        do {
            messages = try await Api.shared.messages(conversationId: conversation.id).items
            loadError = nil
        } catch { loadError = error.apiMessage }
        rebuildTimeline()
    }

    /// Coalesces realtime bursts: many events within a beat trigger ONE
    /// refetch, and an in-flight refetch is cancelled instead of racing the
    /// next one (two concurrent loads used to finish in either order).
    func scheduleRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadMessages()
        }
    }

    /// Call when the screen goes away — a pending refetch must not mutate a
    /// dismissed view's state.
    func cancelRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        input = ""
        do {
            try await Api.shared.sendMessage(conversationId: conversation.id, body: text,
                                             replyToMessageId: replyTarget?.id)
            replyTarget = nil
            await loadMessages()
        } catch {
            // Restore the failed text only if the box is still empty —
            // overwriting would eat whatever the user typed meanwhile.
            if input.isEmpty { input = text }
            attachError = error.apiMessage
        }
        sending = false
    }

    func sendMedia(data: Data, filename: String, mimeType: String, caption: String? = nil) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            let up = try await Api.shared.uploadMedia(data: data, filename: filename, mimeType: mimeType)
            try await Api.shared.sendMedia(conversationId: conversation.id, mediaUrl: up.url, caption: caption,
                                           replyToMessageId: replyTarget?.id)
            replyTarget = nil
            await loadMessages()
        } catch { attachError = error.apiMessage }
        sending = false
    }

    func sendVoiceNote(_ data: Data) async {
        await sendMedia(data: data, filename: "voice-note.m4a", mimeType: "audio/mp4")
    }

    func sendTemplate(name: String, language: String?, params: [String]) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            try await Api.shared.sendTemplate(conversationId: conversation.id, name: name, language: language, params: params)
            await loadMessages()
        } catch { attachError = error.apiMessage }
        sending = false
    }

    func insertReady(_ text: String) {
        input = input.isEmpty ? text : input + "\n" + text
    }

    func retry(_ msg: Message) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            if let mediaUrl = msg.media?.url, !mediaUrl.isEmpty {
                try await Api.shared.sendMedia(conversationId: conversation.id, mediaUrl: mediaUrl, caption: msg.body)
            } else if let body = msg.body, !body.isEmpty {
                try await Api.shared.sendMessage(conversationId: conversation.id, body: body)
            }
            await loadMessages()
        } catch { attachError = error.apiMessage }
        sending = false
    }
}

/// One row of the chat timeline: a message bubble, an inline call event,
/// or a day separator.
enum ChatEntry: Identifiable, Equatable {
    case message(Message)
    case call(VoiceCall)
    case day(String)
    var id: String {
        switch self {
        case .message(let m): return "m-\(m.id)"
        case .call(let c): return "c-\(c.id)"
        case .day(let d): return "d-\(d)"
        }
    }
}

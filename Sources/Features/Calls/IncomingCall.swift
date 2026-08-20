import SwiftUI
import Combine
import AVFoundation

// App-scoped voice-call state machine for WhatsApp/Meta P2P calls, ported
// from the Android CallManager. Listens to the call signaling events on the
// shared WebSocket, drives CallAudioEngine, and relays SDP through the REST
// endpoints. One active call at a time.
//
// In package (Swift Playgrounds) builds CallAudioEngine.isSupported is
// false: the banner keeps its historical reject-only behavior and no
// answer/outbound UI is offered.
@MainActor
final class CallCenter: ObservableObject {
    static let shared = CallCenter()

    enum State: Equatable {
        case idle, incoming, outgoing, connecting, connected
    }

    struct IncomingCall: Equatable {
        let callId: String
        let title: String
        let phone: String?
    }

    @Published private(set) var state: State = .idle
    @Published var incoming: IncomingCall? = nil
    @Published private(set) var peerName: String? = nil
    @Published private(set) var muted = false
    @Published private(set) var speakerOn = false
    @Published private(set) var connectedAt: Date? = nil
    @Published var actionError: String? = nil

    /// Whether this build can actually carry call audio (app target with the
    /// WebRTC framework) — the UI keys answer/outbound controls off this.
    let canCarryAudio = CallAudioEngine.isSupported

    private var cancellable: AnyCancellable?
    private var engine: CallAudioEngine?
    private var currentCallId: String? = nil
    private var pendingOffer: String? = nil
    private var ringTimeout: Task<Void, Never>?

    /// Idempotent. Call once the user is authenticated.
    func start() {
        guard cancellable == nil else { return }
        cancellable = Realtime.shared.events.sink { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: RealtimeEvent) {
        switch event.name {
        case "voice_call_incoming":
            // Field reuse quirk shared with Android/web: with
            // sdpType == "answer" the sdpOffer field carries the ANSWER to
            // our outbound offer.
            if event.sdpType == "answer" {
                if let sdp = event.sdpOffer, !sdp.isEmpty {
                    engine?.setRemoteAnswer(CallSDP.normalize(sdp))
                    if state == .outgoing {
                        state = .connected
                        connectedAt = Date()
                    }
                }
                return
            }
            guard let id = event.callId, !id.isEmpty, state == .idle else { return }
            currentCallId = id
            pendingOffer = event.sdpOffer?.isEmpty == false ? event.sdpOffer : nil
            let title = event.displayName?.isEmpty == false
                ? event.displayName! : (event.phone ?? L("مكالمة واردة"))
            peerName = title
            incoming = IncomingCall(callId: id, title: title, phone: event.phone)
            state = .incoming
            Haptics.warning()
            ringTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard let self, self.state == .incoming else { return }
                self.endLocal()
            }
        case "voice_call_claimed":
            // Another operator answered — drop the ring everywhere.
            if event.callId == currentCallId, state == .incoming { endLocal() }
        case "voice_call_updated":
            guard event.callId == currentCallId, let status = event.status?.lowercased() else { return }
            let terminal = ["ended", "failed", "rejected", "missed", "terminated", "completed", "no_answer", "canceled", "cancelled"]
            if terminal.contains(where: { status.contains($0) }) { endLocal() }
        default:
            break
        }
    }

    // MARK: - Actions

    /// Answer the ringing call: produce the SDP answer locally and relay it
    /// to Meta through the backend.
    func accept() {
        guard state == .incoming, canCarryAudio,
              let callId = currentCallId, let offer = pendingOffer else { return }
        ringTimeout?.cancel()
        incoming = nil
        state = .connecting
        Task {
            guard await Self.ensureMicPermission() else {
                actionError = L("إذن الميكروفون مطلوب للرد على المكالمة")
                endLocal()
                return
            }
            configureAudioSession()
            let engine = CallAudioEngine()
            self.engine = engine
            guard let answer = await engine.answerOffer(CallSDP.normalize(offer)) else {
                actionError = L("تعذّر تجهيز الصوت للمكالمة")
                endLocal()
                return
            }
            do {
                try await Api.shared.answerWhatsappCall(callId: callId, sdp: CallSDP.normalize(answer))
                state = .connected
                connectedAt = Date()
            } catch {
                actionError = error.apiMessage
                endLocal()
            }
        }
    }

    /// Place an outbound call to a customer number.
    func startOutbound(to: String, displayName: String?, instanceId: String?) {
        guard state == .idle, canCarryAudio, !to.isEmpty else { return }
        actionError = nil
        peerName = displayName?.isEmpty == false ? displayName : to
        muted = false
        state = .outgoing
        Task {
            guard await Self.ensureMicPermission() else {
                actionError = L("إذن الميكروفون مطلوب لبدء المكالمة")
                endLocal()
                return
            }
            configureAudioSession()
            let engine = CallAudioEngine()
            self.engine = engine
            guard let offer = await engine.createOffer() else {
                actionError = L("تعذّر تجهيز الصوت للمكالمة")
                endLocal()
                return
            }
            do {
                let res = try await Api.shared.startWhatsappCall(
                    to: to, sdp: CallSDP.normalize(offer),
                    displayName: displayName, instanceId: instanceId)
                currentCallId = res.callId
                if let answer = res.answer, !answer.isEmpty {
                    engine.setRemoteAnswer(CallSDP.normalize(answer))
                    state = .connected
                    connectedAt = Date()
                }
                // Otherwise stay in .outgoing: the answer arrives over the
                // WebSocket as voice_call_incoming with sdpType == "answer".
            } catch {
                actionError = error.apiMessage
                endLocal()
            }
        }
    }

    func reject() async {
        let callId = currentCallId ?? incoming?.callId
        endLocal()
        guard let callId else { return }
        do { try await Api.shared.rejectCall(callId: callId, action: "reject") }
        catch { actionError = error.apiMessage }
    }

    func hangup() async {
        let callId = currentCallId
        endLocal()
        guard let callId else { return }
        try? await Api.shared.rejectCall(callId: callId, action: "terminate")
    }

    func toggleMute() {
        muted.toggle()
        engine?.setMicEnabled(!muted)
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    func dismiss() {
        // Hides the banner without rejecting: the call keeps ringing for
        // other operators (web/Android), matching the historical behavior.
        if state == .incoming { endLocal() }
    }

    // MARK: - Internals

    private func endLocal() {
        ringTimeout?.cancel()
        ringTimeout = nil
        engine?.close()
        engine = nil
        deactivateAudioSession()
        currentCallId = nil
        pendingOffer = nil
        incoming = nil
        peerName = nil
        muted = false
        speakerOn = false
        connectedAt = nil
        state = .idle
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        try? session.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func ensureMicPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

/// Maps Meta's raw call-permission errors to human copy. #138017 in
/// particular means the customer ALREADY granted permanent permission —
/// good news, not an error — yet the backend relays Meta's whole JSON
/// blob, which used to land verbatim in the alert.
enum CallPermissionNotice {
    static func friendly(_ raw: String) -> String {
        if raw.contains("138017")
            || raw.contains("already been approved")
            || raw.contains("can already call") {
            return L("إذن الاتصال ممنوح مسبقاً من هذا العميل — يمكنك بدء المكالمة مباشرة ✓")
        }
        // Raw Meta payloads are JSON dumps; keep alerts readable.
        if raw.count > 160 || raw.contains("{\"") {
            return L("تعذّر إرسال طلب إذن الاتصال — حاول لاحقاً")
        }
        return raw
    }
}

/// Top-of-screen banner shown app-wide while a WhatsApp call is ringing.
struct IncomingCallBanner: View {
    @StateObject private var center = CallCenter.shared

    var body: some View {
        VStack {
            if let call = center.incoming {
                HStack(spacing: 12) {
                    Image(systemName: "phone.arrow.down.left")
                        .font(.wx(18, .semibold))
                        .foregroundStyle(Theme.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.title)
                            .font(.wx(15, .bold)).foregroundStyle(Theme.onSurface)
                            .lineLimit(1)
                        Text(center.canCarryAudio
                             ? L("مكالمة واتساب واردة")
                             : L("مكالمة واتساب واردة — الرد متاح من الويب"))
                            .font(.wx(12)).foregroundStyle(Theme.onMuted)
                    }
                    Spacer()
                    if center.canCarryAudio {
                        Button { center.accept() } label: {
                            Image(systemName: "phone.fill")
                                .font(.wx(16)).foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Theme.success, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("الرد على المكالمة"))
                    }
                    Button { Task { await center.reject() } } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.wx(16)).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.danger, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("رفض المكالمة"))
                    Button { center.dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.wx(13, .semibold)).foregroundStyle(Theme.onMuted)
                            .frame(width: 34, height: 34)
                            .background(Theme.surface2, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .glassCard(20)
                .padding(.horizontal, 14)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .animation(.spring(), value: center.incoming)
        .allowsHitTesting(center.incoming != nil)
    }
}

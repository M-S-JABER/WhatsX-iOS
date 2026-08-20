import SwiftUI
import Combine
import AVFoundation

// App-scoped voice-call state machine for WhatsApp/Meta P2P calls, ported
// from the Android CallManager. Listens to the call signaling events on the
// shared WebSocket, drives CallAudioEngine, and relays SDP through the REST
// endpoints. One active call at a time.
//
// Ring surface: in app-target builds every call rings through CallKit (the
// native call UI, on the lock screen too) — fed by the WS event while the
// app runs, and by the VoIP push when it doesn't (VoIPPush.swift). The two
// race for the same callId and dedupe here. Answer/end/mute flow through
// CallKit actions so system UI and in-app UI stay consistent.
//
// In package (Swift Playgrounds) builds CallAudioEngine.isSupported is
// false: the historical top banner keeps its reject-only behavior and no
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

    /// System (CallKit) ring surface; nil where CallKit or WebRTC is absent,
    /// which falls the UI back to the historical in-app banner.
    private let callKit: CallKitBridge?

    private var cancellable: AnyCancellable?
    private var engine: CallAudioEngine?
    private var currentCallId: String? = nil
    private var pendingOffer: String? = nil
    private var pendingOutbound: (to: String, displayName: String?, instanceId: String?)? = nil
    private var ringTimeout: Task<Void, Never>?

    private init() {
        callKit = CallKitBridge.isSupported ? CallKitBridge() : nil
        callKit?.center = self
    }

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
                        callKit?.reportOutboundConnected()
                    }
                }
                return
            }
            guard let id = event.callId, !id.isEmpty else { return }
            // The VoIP push may have rung this call already — just backfill
            // the offer if the push had to omit it for size.
            if id == currentCallId, state != .idle {
                if pendingOffer == nil, let sdp = event.sdpOffer, !sdp.isEmpty {
                    pendingOffer = sdp
                }
                return
            }
            guard state == .idle else { return }
            currentCallId = id
            pendingOffer = event.sdpOffer?.isEmpty == false ? event.sdpOffer : nil
            let title = event.displayName?.isEmpty == false
                ? event.displayName! : (event.phone ?? L("مكالمة واردة"))
            peerName = title
            state = .incoming
            if let callKit {
                callKit.reportIncoming(callId: id, title: title, phone: event.phone)
            } else {
                incoming = IncomingCall(callId: id, title: title, phone: event.phone)
                Haptics.warning()
            }
            armRingTimeout()
        case "voice_call_claimed":
            // Another operator answered — drop the ring everywhere.
            if event.callId == currentCallId, state == .incoming { endLocal(.answeredElsewhere) }
        case "voice_call_updated":
            guard event.callId == currentCallId, let status = event.status?.lowercased() else { return }
            let terminal = ["ended", "failed", "rejected", "missed", "terminated", "completed", "no_answer", "canceled", "cancelled"]
            if terminal.contains(where: { status.contains($0) }) { endLocal(.remoteEnded) }
        default:
            break
        }
    }

    /// A VoIP push arrived (possibly cold-starting the app in the
    /// background). CallKitBridge has Apple's ring-on-every-push rule
    /// satisfied through the paths below — even busy or malformed pushes
    /// surface (and immediately end) a CallKit call.
    func handleVoipPush(_ payload: VoipPayload.Call?) {
        guard let callKit else { return }
        guard let p = payload else {
            callKit.reportBusy(callId: "-", title: "WhatsX")
            return
        }
        let title = p.displayName ?? p.phone ?? L("مكالمة واردة")
        if p.callId == currentCallId, state != .idle {
            // The WS event beat the push — reportIncoming dedupes.
            callKit.reportIncoming(callId: p.callId, title: peerName ?? title, phone: p.phone)
            return
        }
        guard state == .idle else {
            callKit.reportBusy(callId: p.callId, title: title)
            return
        }
        currentCallId = p.callId
        pendingOffer = p.sdpOffer
        peerName = title
        state = .incoming
        callKit.reportIncoming(callId: p.callId, title: title, phone: p.phone)
        armRingTimeout()
    }

    private func armRingTimeout() {
        ringTimeout?.cancel()
        ringTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard let self, self.state == .incoming else { return }
            self.endLocal(.unanswered)
        }
    }

    // MARK: - Actions (app UI)

    /// Legacy banner answer — only reachable in builds without the CallKit
    /// surface; with CallKit the system UI owns answering (performAnswer).
    func accept() {
        guard callKit == nil else { return }
        guard state == .incoming, canCarryAudio,
              let callId = currentCallId, let offer = pendingOffer else { return }
        ringTimeout?.cancel()
        incoming = nil
        state = .connecting
        Task {
            guard await Self.ensureMicPermission() else {
                actionError = L("إذن الميكروفون مطلوب للرد على المكالمة")
                endLocal(.failed)
                return
            }
            configureAudioSession(activate: true)
            let engine = CallAudioEngine()
            self.engine = engine
            guard let answer = await engine.answerOffer(CallSDP.normalize(offer)) else {
                actionError = L("تعذّر تجهيز الصوت للمكالمة")
                endLocal(.failed)
                return
            }
            do {
                try await Api.shared.answerWhatsappCall(callId: callId, sdp: CallSDP.normalize(answer))
                state = .connected
                connectedAt = Date()
            } catch {
                actionError = error.apiMessage
                endLocal(.failed)
            }
        }
    }

    /// Place an outbound call to a customer number. With CallKit the call is
    /// requested through the system first (CXStartCallAction), which then
    /// drives performOutboundStart.
    func startOutbound(to: String, displayName: String?, instanceId: String?) {
        guard state == .idle, canCarryAudio, !to.isEmpty else { return }
        actionError = nil
        peerName = displayName?.isEmpty == false ? displayName : to
        muted = false
        state = .outgoing
        pendingOutbound = (to, displayName, instanceId)
        if let callKit {
            callKit.requestStart(handle: to, display: peerName ?? to)
        } else {
            Task { await performOutboundStart() }
        }
    }

    func reject() async {
        if let callKit { callKit.requestEnd(); return }
        let callId = currentCallId ?? incoming?.callId
        endLocal(nil)
        guard let callId else { return }
        do { try await Api.shared.rejectCall(callId: callId, action: "reject") }
        catch { actionError = error.apiMessage }
    }

    func hangup() async {
        if let callKit { callKit.requestEnd(); return }
        let callId = currentCallId
        endLocal(nil)
        guard let callId else { return }
        try? await Api.shared.rejectCall(callId: callId, action: "terminate")
    }

    func toggleMute() {
        let target = !muted
        if let callKit { callKit.requestMuted(target) } else { applyMuted(target) }
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        let session = AVAudioSession.sharedInstance()
        try? session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    func dismiss() {
        // Banner-only (no CallKit): hides the banner without rejecting — the
        // call keeps ringing for other operators (web/Android).
        guard callKit == nil else { return }
        if state == .incoming { endLocal(nil) }
    }

    // MARK: - CallKit entry points (system UI → CallKitBridge → here)

    func performAnswer() async {
        guard state == .incoming, let callId = currentCallId else { return }
        ringTimeout?.cancel()
        state = .connecting
        guard await Self.ensureMicPermission() else {
            actionError = L("إذن الميكروفون مطلوب للرد على المكالمة")
            endLocal(.failed)
            return
        }
        // Category only — CallKit owns activation (didActivate → WebRTC).
        configureAudioSession(activate: false)
        let engine = CallAudioEngine()
        self.engine = engine
        // A push that had to omit the offer for size falls back to REST.
        var offer = pendingOffer
        if offer == nil {
            offer = try? await Api.shared.callOffer(callId: callId)
        }
        guard let offer, !offer.isEmpty,
              let answer = await engine.answerOffer(CallSDP.normalize(offer)) else {
            actionError = L("تعذّر تجهيز الصوت للمكالمة")
            endLocal(.failed)
            return
        }
        do {
            try await Api.shared.answerWhatsappCall(callId: callId, sdp: CallSDP.normalize(answer))
            state = .connected
            connectedAt = Date()
        } catch {
            actionError = error.apiMessage
            endLocal(.failed)
        }
    }

    func performOutboundStart() async {
        guard state == .outgoing, let params = pendingOutbound else { return }
        guard await Self.ensureMicPermission() else {
            actionError = L("إذن الميكروفون مطلوب لبدء المكالمة")
            endLocal(.failed)
            return
        }
        configureAudioSession(activate: callKit == nil)
        let engine = CallAudioEngine()
        self.engine = engine
        guard let offer = await engine.createOffer() else {
            actionError = L("تعذّر تجهيز الصوت للمكالمة")
            endLocal(.failed)
            return
        }
        do {
            let res = try await Api.shared.startWhatsappCall(
                to: params.to, sdp: CallSDP.normalize(offer),
                displayName: params.displayName, instanceId: params.instanceId)
            currentCallId = res.callId
            if let id = res.callId { callKit?.linkOutbound(callId: id) }
            if let answer = res.answer, !answer.isEmpty {
                engine.setRemoteAnswer(CallSDP.normalize(answer))
                state = .connected
                connectedAt = Date()
                callKit?.reportOutboundConnected()
            }
            // Otherwise stay in .outgoing: the answer arrives over the
            // WebSocket as voice_call_incoming with sdpType == "answer".
        } catch {
            actionError = error.apiMessage
            endLocal(.failed)
        }
    }

    /// CXEndCallAction fired (system UI or our own requestEnd) — CallKit
    /// already considers the call over, so end locally without re-reporting
    /// and tell the backend.
    func performEnd() async {
        let callId = currentCallId
        let wasIncoming = state == .incoming
        endLocal(nil)
        guard let callId else { return }
        try? await Api.shared.rejectCall(callId: callId, action: wasIncoming ? "reject" : "terminate")
    }

    func applyMuted(_ newValue: Bool) {
        muted = newValue
        engine?.setMicEnabled(!newValue)
    }

    /// reportNewIncomingCall failed (e.g. filtered by Do Not Disturb) — the
    /// system will not ring, so drop our side quietly.
    func callKitFailedToRing(callId: String) {
        guard callId == currentCallId, state == .incoming else { return }
        endLocal(nil)
    }

    /// The CXProvider was reset by the system — all call state is gone.
    func callKitReset() {
        endLocal(nil)
    }

    // MARK: - Internals

    /// Tears down the active call. `cause` is reported to CallKit; pass nil
    /// when CallKit already knows (its own end action, reset, or no ring).
    private func endLocal(_ cause: CallEndCause?) {
        ringTimeout?.cancel()
        ringTimeout = nil
        engine?.close()
        engine = nil
        if let cause { callKit?.reportEnded(cause) }
        // With CallKit the system deactivates the audio session itself.
        if callKit == nil { deactivateAudioSession() }
        currentCallId = nil
        pendingOffer = nil
        pendingOutbound = nil
        incoming = nil
        peerName = nil
        muted = false
        speakerOn = false
        connectedAt = nil
        state = .idle
    }

    private func configureAudioSession(activate: Bool) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        if activate { try? session.setActive(true) }
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
/// Only populated in builds WITHOUT the CallKit surface (Swift Playgrounds
/// package): there `incoming` is set and the banner keeps its historical
/// reject-only behavior. With CallKit, ringing is the system's call UI.
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

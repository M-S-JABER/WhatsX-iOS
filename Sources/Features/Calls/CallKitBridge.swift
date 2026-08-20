import Foundation

/// Why a call ended, expressed without CallKit types so CallCenter compiles
/// on platforms where CallKit is unavailable (macOS package builds).
enum CallEndCause {
    case remoteEnded, unanswered, failed, answeredElsewhere, localEnded
}

#if canImport(CallKit)
import CallKit
import AVFAudio

// System call surface: reports rings to CallKit (the native full-screen /
// lock-screen call UI), and forwards the user's answer/end/mute actions back
// to CallCenter. This is what lets a VoIP-push call ring while the app is
// closed — and it also fronts WS-signaled rings so the experience matches.
//
// Main-thread only by construction: the provider delegate queue is the main
// queue, PKPushRegistry uses the main queue, and CallCenter (@MainActor)
// calls in from the main thread. One active call at a time, like CallCenter.
final class CallKitBridge: NSObject {
    /// Ringing without audio is pointless — the bridge activates only in
    /// builds that carry the WebRTC engine.
    static var isSupported: Bool { CallAudioEngine.isSupported }

    weak var center: CallCenter?

    private let provider: CXProvider
    private let controller = CXCallController()
    private var activeUUID: UUID?
    private var activeCallId: String?

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = false
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.supportedHandleTypes = [.phoneNumber, .generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: nil)
        // With CallKit, the system owns audio-session activation; WebRTC must
        // wait for didActivate instead of starting audio on its own.
        CallAudioEngine.prepareManualAudio()
    }

    // MARK: - Reporting (app → system)

    /// Ring the system UI. Safe to call twice for the same callId (WS event
    /// and VoIP push race each other) — the duplicate report is a no-op.
    func reportIncoming(callId: String, title: String, phone: String?) {
        if activeCallId == callId, activeUUID != nil { return }
        let uuid = UUID()
        activeUUID = uuid
        activeCallId = callId
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: phone != nil ? .phoneNumber : .generic,
                                       value: phone ?? title)
        update.localizedCallerName = title
        update.hasVideo = false
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.center?.callKitFailedToRing(callId: callId) }
            }
        }
    }

    /// Apple requires every VoIP push to surface a CallKit call, even when
    /// the device is already busy with one — ring-and-immediately-end is the
    /// sanctioned way to satisfy that without disturbing the active call.
    func reportBusy(callId: String, title: String) {
        let uuid = UUID()
        let update = CXCallUpdate()
        update.remoteHandle = CXHandle(type: .generic, value: title)
        update.localizedCallerName = title
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
            self?.provider.reportCall(with: uuid, endedAt: nil, reason: .failed)
        }
    }

    /// Outbound leg: the server assigns the callId after the offer POST.
    func linkOutbound(callId: String) {
        activeCallId = callId
    }

    func reportOutboundConnected() {
        guard let uuid = activeUUID else { return }
        provider.reportOutgoingCall(with: uuid, connectedAt: Date())
    }

    func reportEnded(_ cause: CallEndCause) {
        guard let uuid = activeUUID else { return }
        activeUUID = nil
        activeCallId = nil
        let reason: CXCallEndedReason
        switch cause {
        case .remoteEnded: reason = .remoteEnded
        case .unanswered: reason = .unanswered
        case .failed: reason = .failed
        case .answeredElsewhere: reason = .answeredElsewhere
        case .localEnded:
            // Locally-initiated ends go through CXEndCallAction (requestEnd)
            // and need no report; this is a fallback for cleanup paths.
            provider.reportCall(with: uuid, endedAt: nil, reason: .remoteEnded)
            return
        }
        provider.reportCall(with: uuid, endedAt: nil, reason: reason)
    }

    // MARK: - Requests (app UI → system → provider delegate)

    func requestStart(handle: String, display: String) {
        let uuid = UUID()
        activeUUID = uuid
        activeCallId = nil
        let cxHandle = CXHandle(type: handle.allSatisfy(\.isNumber) ? .phoneNumber : .generic,
                                value: handle)
        let action = CXStartCallAction(call: uuid, handle: cxHandle)
        action.contactIdentifier = display
        controller.request(CXTransaction(action: action)) { [weak self] error in
            if error != nil {
                // CallKit refused (rare; e.g. restrictions) — run the call
                // without the system surface rather than dropping it.
                Task { @MainActor in await self?.center?.performOutboundStart() }
            }
        }
    }

    func requestEnd() {
        guard let uuid = activeUUID else {
            Task { @MainActor in await center?.performEnd() }
            return
        }
        controller.request(CXTransaction(action: CXEndCallAction(call: uuid))) { [weak self] error in
            if error != nil {
                Task { @MainActor in
                    await self?.center?.performEnd()
                    self?.reportEnded(.localEnded)
                }
            }
        }
    }

    func requestMuted(_ muted: Bool) {
        guard let uuid = activeUUID else {
            Task { @MainActor in center?.applyMuted(muted) }
            return
        }
        controller.request(CXTransaction(action: CXSetMutedCallAction(call: uuid, muted: muted))) { [weak self] error in
            if error != nil {
                Task { @MainActor in self?.center?.applyMuted(muted) }
            }
        }
    }
}

extension CallKitBridge: CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        activeUUID = nil
        activeCallId = nil
        Task { @MainActor in center?.callKitReset() }
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        Task { @MainActor in await center?.performAnswer() }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())
        Task { @MainActor in await center?.performOutboundStart() }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        activeUUID = nil
        activeCallId = nil
        Task { @MainActor in await center?.performEnd() }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor in center?.applyMuted(action.isMuted) }
        action.fulfill()
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        CallAudioEngine.audioSessionDidActivate(audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        CallAudioEngine.audioSessionDidDeactivate(audioSession)
    }
}

#else

/// Platforms without CallKit (macOS package builds): inert, never supported.
final class CallKitBridge {
    static var isSupported: Bool { false }
    weak var center: CallCenter?
    func reportIncoming(callId: String, title: String, phone: String?) {}
    func reportBusy(callId: String, title: String) {}
    func linkOutbound(callId: String) {}
    func reportOutboundConnected() {}
    func reportEnded(_ cause: CallEndCause) {}
    func requestStart(handle: String, display: String) {}
    func requestEnd() {}
    func requestMuted(_ muted: Bool) {}
}

#endif

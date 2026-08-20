import Foundation

// Minimal WebRTC peer for WhatsApp/Meta P2P audio calls, ported from the
// Android WebRtcClient. Signaling is non-trickle: gather every ICE candidate
// (or hit a 2.5s cap), then hand the complete local SDP to the caller, which
// relays it to Meta through the REST endpoints. One active call at a time.
//
// The WebRTC binary framework is linked only into the XcodeGen app target —
// a Swift Playgrounds package cannot bundle it — so everything WebRTC-shaped
// lives behind `#if canImport(WebRTC)` with an inert fallback. In package
// builds `isSupported` is false and the UI keeps today's reject-only banner.

#if canImport(WebRTC)
import WebRTC

final class CallAudioEngine {
    static let isSupported = true

    private static let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        return RTCPeerConnectionFactory()
    }()

    private var connection: RTCPeerConnection?
    private var localAudio: RTCAudioTrack?
    private var observer: PeerObserver?

    /// Collects the full local SDP once ICE gathering completes or 2.5s
    /// elapse, whichever comes first — mirroring the Android client.
    private func awaitLocalSdp(_ connection: RTCPeerConnection,
                               observer: PeerObserver) async -> String? {
        await withCheckedContinuation { continuation in
            let fired = Locked(false)
            let fire = {
                guard !fired.exchange(true) else { return }
                continuation.resume(returning: connection.localDescription?.sdp)
            }
            observer.onIceGatheringComplete = fire
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: fire)
        }
    }

    private func makeConnection() -> RTCPeerConnection? {
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]),
        ]
        let peerObserver = PeerObserver()
        observer = peerObserver
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = Self.factory.peerConnection(with: config, constraints: constraints, delegate: peerObserver) else {
            return nil
        }
        let source = Self.factory.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let track = Self.factory.audioTrack(with: source, trackId: "audio0")
        localAudio = track
        pc.add(track, streamIds: ["stream0"])
        connection = pc
        return pc
    }

    /// Outbound leg: returns the complete offer SDP, nil on failure.
    func createOffer() async -> String? {
        guard let pc = makeConnection(), let observer else { return nil }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let offer = try? await pc.offer(for: constraints) else { return nil }
        try? await pc.setLocalDescription(offer)
        return await awaitLocalSdp(pc, observer: observer)
    }

    /// Inbound leg: applies the remote offer, returns the complete answer SDP.
    func answerOffer(_ offerSdp: String) async -> String? {
        guard let pc = makeConnection(), let observer else { return nil }
        let remote = RTCSessionDescription(type: .offer, sdp: offerSdp)
        guard (try? await pc.setRemoteDescription(remote)) != nil else { return nil }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let answer = try? await pc.answer(for: constraints) else { return nil }
        try? await pc.setLocalDescription(answer)
        return await awaitLocalSdp(pc, observer: observer)
    }

    /// Outbound leg: applies the answer Meta sent back.
    func setRemoteAnswer(_ answerSdp: String) {
        guard let pc = connection, pc.signalingState == .haveLocalOffer else { return }
        let remote = RTCSessionDescription(type: .answer, sdp: answerSdp)
        pc.setRemoteDescription(remote) { _ in }
    }

    func setMicEnabled(_ enabled: Bool) {
        localAudio?.isEnabled = enabled
    }

    func close() {
        connection?.close()
        connection = nil
        localAudio = nil
        observer = nil
    }
}

/// RTCPeerConnectionDelegate is a sprawling ObjC protocol; only the ICE
/// gathering transition matters for non-trickle signaling.
private final class PeerObserver: NSObject, RTCPeerConnectionDelegate {
    var onIceGatheringComplete: (() -> Void)?

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        if newState == .complete {
            let complete = onIceGatheringComplete
            DispatchQueue.main.async { complete?() }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

/// Tiny thread-safe flag for the fire-once continuation guard.
private final class Locked {
    private let lock = NSLock()
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    func exchange(_ new: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
}

#else

/// Package (Swift Playgrounds) fallback: calls are not supported, the UI
/// keeps the reject-only banner, and every method is inert.
final class CallAudioEngine {
    static let isSupported = false
    func createOffer() async -> String? { nil }
    func answerOffer(_ offerSdp: String) async -> String? { nil }
    func setRemoteAnswer(_ answerSdp: String) {}
    func setMicEnabled(_ enabled: Bool) {}
    func close() {}
}

#endif

/// Meta rejects SDP with bare-LF line endings; force CRLF plus a trailing
/// CRLF, exactly like the Android client.
enum CallSDP {
    static func normalize(_ sdp: String) -> String {
        let crlf = sdp
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
        return crlf.hasSuffix("\r\n") ? crlf : crlf + "\r\n"
    }
}

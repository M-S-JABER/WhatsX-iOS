import SwiftUI
import Combine

// Live incoming-call handling (web parity: VoiceCallManager, minus the
// WebRTC leg). Answering needs an SDP/WebRTC stack that a Swift Playgrounds
// package can't bundle, so the banner offers reject/dismiss and points the
// operator at the web softphone for pickup; the reject action itself hits
// Meta through the backend exactly like the web client.
@MainActor
final class CallCenter: ObservableObject {
    static let shared = CallCenter()

    struct IncomingCall: Equatable {
        let callId: String
        let title: String
        let phone: String?
    }

    @Published var incoming: IncomingCall? = nil
    @Published var actionError: String? = nil

    private var cancellable: AnyCancellable?

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
            guard let id = event.callId, !id.isEmpty else { return }
            incoming = IncomingCall(
                callId: id,
                title: event.displayName?.isEmpty == false ? event.displayName! : (event.phone ?? L("مكالمة واردة")),
                phone: event.phone
            )
        case "voice_call_claimed":
            // Another operator answered — drop the banner everywhere.
            if event.callId == incoming?.callId { incoming = nil }
        case "voice_call_updated":
            guard event.callId == incoming?.callId, let status = event.status?.lowercased() else { return }
            let terminal = ["ended", "failed", "rejected", "missed", "terminated", "completed", "no_answer", "canceled", "cancelled"]
            if terminal.contains(where: { status.contains($0) }) { incoming = nil }
        default:
            break
        }
    }

    func reject() async {
        guard let call = incoming else { return }
        incoming = nil
        do { try await Api.shared.rejectCall(callId: call.callId) }
        catch { actionError = error.apiMessage }
    }

    func dismiss() { incoming = nil }
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
                        Text(L("مكالمة واتساب واردة — الرد متاح من الويب"))
                            .font(.wx(12)).foregroundStyle(Theme.onMuted)
                    }
                    Spacer()
                    Button { Task { await center.reject() } } label: {
                        Image(systemName: "phone.down.fill")
                            .font(.wx(16)).foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(Theme.danger, in: Circle())
                    }
                    .buttonStyle(.plain)
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

import SwiftUI

/// Full-screen in-call UI, shown whenever a call is being placed or is live
/// (web parity: the softphone panel). Rendered above the tab view from
/// RootView; the incoming ring itself stays on IncomingCallBanner.
struct CallOverlay: View {
    @StateObject private var center = CallCenter.shared

    private var active: Bool {
        switch center.state {
        case .outgoing, .connecting, .connected: return true
        case .idle, .incoming: return false
        }
    }

    var body: some View {
        ZStack {
            if active {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 26) {
                    Spacer()

                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 96))
                        .foregroundStyle(Theme.primary.opacity(0.85))

                    VStack(spacing: 8) {
                        Text(center.peerName ?? L("مكالمة"))
                            .font(.wx(24, .bold))
                            .foregroundStyle(Theme.onSurface)
                            .lineLimit(1)
                        stateLine
                            .font(.wx(15))
                            .foregroundStyle(Theme.onMuted)
                    }

                    Spacer()

                    HStack(spacing: 28) {
                        controlButton(
                            system: center.muted ? "mic.slash.fill" : "mic.fill",
                            label: center.muted ? L("إلغاء كتم الصوت") : L("كتم الصوت"),
                            emphasized: center.muted
                        ) { center.toggleMute() }

                        Button {
                            Haptics.action()
                            Task { await center.hangup() }
                        } label: {
                            Image(systemName: "phone.down.fill")
                                .font(.wx(24)).foregroundStyle(.white)
                                .frame(width: 72, height: 72)
                                .background(Theme.danger, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("إنهاء المكالمة"))

                        controlButton(
                            system: center.speakerOn ? "speaker.wave.3.fill" : "speaker.fill",
                            label: L("مكبر الصوت"),
                            emphasized: center.speakerOn
                        ) { center.toggleSpeaker() }
                    }
                    .padding(.bottom, 48)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: active)
        .allowsHitTesting(active)
    }

    @ViewBuilder
    private var stateLine: some View {
        switch center.state {
        case .outgoing:
            Text(L("جارٍ الاتصال…"))
        case .connecting:
            Text(L("جارٍ التوصيل…"))
        case .connected:
            if let start = center.connectedAt {
                // TimelineView re-renders every second for the live duration.
                TimelineView(.periodic(from: start, by: 1)) { context in
                    Text(durationText(from: start, now: context.date))
                        .monospacedDigit()
                }
            } else {
                Text(L("متصل"))
            }
        case .idle, .incoming:
            EmptyView()
        }
    }

    private func durationText(from start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func controlButton(system: String, label: String, emphasized: Bool,
                               action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: system)
                .font(.wx(20))
                .foregroundStyle(emphasized ? Theme.onPrimary : Theme.onSurface)
                .frame(width: 58, height: 58)
                .background(emphasized ? Theme.primary : Theme.surface2, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

import SwiftUI

// MARK: - Voice / SIP settings (read-only)

struct VoiceSettingsView: View {
    @State private var s: VoiceSettings?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            } else if let s {
                VStack(spacing: 0) {
                    infoRow(L("مُفعّل"), s.enabled ? L("نعم") : L("لا"))
                    infoRow("SIP", s.sipEnabled ? L("مُفعّل") : L("متوقف"))
                    infoRow("Cloudflare", s.cloudflareHostname)
                    infoRow("WebRTC WSS", s.asteriskWebrtcWssUrl)
                    infoRow("UCM IP", s.ucmPublicIp)
                    infoRow(L("التحويلة الافتراضية"), s.ucmDefaultExtension)
                    infoRow("SIP Domain", s.whatsappSipDomain)
                }
                .glassCard(22)
                .padding(16)
            } else {
                Text(L("تعذّر تحميل الإعدادات")).foregroundStyle(Theme.onMuted).padding(.top, 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("الصوت والمكالمات"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            s = (try? await Api.shared.voiceSettings())?.settings
            loading = false
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.wx(15)).foregroundStyle(Theme.onSurface)
            Spacer()
            Text(value.isEmpty ? "—" : value).font(.wx(12)).foregroundStyle(Theme.onMuted)
                .monospaced().lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

// Shared plain-list container with loading/empty states.
@ViewBuilder
func listContainer<Content: View>(loading: Bool, empty: Bool, emptyText: String, @ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Theme.background.ignoresSafeArea()
        if loading {
            ProgressView().tint(Theme.primary)
        } else if empty {
            Text(emptyText).foregroundStyle(Theme.onMuted)
        } else {
            ScrollView { LazyVStack(spacing: 0) { content() } }
        }
    }
}

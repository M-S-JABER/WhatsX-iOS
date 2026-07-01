import SwiftUI

enum MainTab: CaseIterable {
    case chats, calls, reports, integrations, settings
    var icon: WIcon {
        switch self {
        case .chats: return .chat
        case .calls: return .call
        case .reports: return .chart
        case .integrations: return .hub
        case .settings: return .settings
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var session: Session
    @State private var tab: MainTab = .chats
    @State private var showNewConversation = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.background.ignoresSafeArea()

            // Active tab content
            Group {
                switch tab {
                case .chats: InboxView()
                case .calls: CallsView()
                case .reports: StatsView()
                case .integrations: IntegrationsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // New-chat FAB (chats tab only) — rounded square, on-surface fill.
            if tab == .chats {
                HStack {
                    Button { showNewConversation = true } label: {
                        Image(icon: .add).font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Theme.surface)
                            .frame(width: 56, height: 56)
                            .background(Theme.onSurface, in: RoundedRectangle(cornerRadius: 18))
                            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 92)
            }

            bottomBar
        }
        .sheet(isPresented: $showNewConversation) {
            NewConversationSheet()
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(MainTab.allCases), id: \.self) { t in
                let active = tab == t
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { tab = t }
                } label: {
                    ZStack {
                        if active && t != .settings {
                            Circle().fill(Theme.onSurface.opacity(0.10)).frame(width: 48, height: 48)
                        }
                        if t == .settings {
                            Avatar(name: session.user?.title ?? "?",
                                   imageURL: avatarURL, size: 34)
                                .overlay(Circle().stroke(active ? Theme.primary : .clear, lineWidth: 2))
                        } else {
                            Image(icon: t.icon, filled: active)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(active ? Theme.onSurface : Theme.onSurface.opacity(0.5))
                                .scaleEffect(active ? 1 : 0.9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 30)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 30).stroke(Theme.outline, lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private var avatarURL: URL? {
        guard let user = session.user, let avatar = user.avatar, !avatar.isEmpty else { return nil }
        return Api.avatarURL(userId: user.id, avatar: avatar)
    }
}

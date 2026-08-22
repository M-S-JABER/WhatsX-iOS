import SwiftUI
import UIKit
import Combine

// WhatsX 2.0 information architecture: FOUR tabs — Chats · Calls · Reports ·
// Settings. The Search tab dissolved into the inbox (a persistent field in
// phase B; a temporary header button until then) and Integrations became a
// Settings row. The system tab bar is hidden; a floating glass capsule bar
// (design 4x) renders instead, with the active tab as an amber capsule.
enum MainTab: Hashable { case chats, calls, reports, settings }

/// Tiny event bus between the tab bar and the inbox: re-tapping the chats
/// tab (a second press while already on it) flips active ⇄ archive, and a
/// tapped message notification routes to its conversation through here.
@MainActor
final class InboxBus: ObservableObject {
    static let shared = InboxBus()
    let toggleArchive = PassthroughSubject<Void, Never>()

    /// Fired when a tapped notification wants a conversation opened. The
    /// pending id covers the cold-start race: the tap can arrive before the
    /// session is bootstrapped and the inbox exists — the inbox consumes it
    /// once it has loaded.
    let openConversation = PassthroughSubject<String, Never>()
    private(set) var pendingConversationId: String? = nil

    func requestOpenConversation(_ id: String) {
        pendingConversationId = id
        openConversation.send(id)
    }

    func consumePendingConversation() -> String? {
        defer { pendingConversationId = nil }
        return pendingConversationId
    }

    /// How many chat screens are currently PUSHED over a tab root (phone
    /// navigation). While any is open the floating tab bar hides: the chat
    /// composer owns the bottom edge (TestFlight feedback on 1.23.0 — the
    /// bar covered the composer, because pushed destinations don't inherit
    /// a safeAreaInset applied outside their NavigationStack on iOS 16/17).
    /// The iPad split pane and sheet presentations don't count.
    @Published private(set) var pushedChats = 0

    func chatDidAppear() {
        withAnimation(.easeInOut(duration: 0.22)) { pushedChats += 1 }
    }

    func chatDidDisappear() {
        withAnimation(.easeInOut(duration: 0.22)) { pushedChats = max(0, pushedChats - 1) }
    }
}

struct MainTabView: View {
    @State private var tab: MainTab = .chats
    @State private var lastChatsTap: Date? = nil
    @StateObject private var unread = UnreadCenter.shared
    @StateObject private var bus = InboxBus.shared
    @Namespace private var activeTabNamespace

    var body: some View {
        TabView(selection: $tab) {
            InboxView()
                .toolbar(.hidden, for: .tabBar)
                .tag(MainTab.chats)
            CallsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(MainTab.calls)
            NavigationStack { StatsView() }
                .toolbar(.hidden, for: .tabBar)
                .tag(MainTab.reports)
            SettingsView()
                .toolbar(.hidden, for: .tabBar)
                .tag(MainTab.settings)
        }
        .tint(Theme.primary)
        .environment(\.horizontalSizeClass, .compact)
        // The floating bar claims its own bottom band, so every screen's
        // content (and their own bottom overlays) stays above it. It hides
        // entirely while a chat is pushed — the composer takes the edge.
        .safeAreaInset(edge: .bottom) {
            if bus.pushedChats == 0 {
                floatingBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // A tapped message notification always lands on the chats tab; the
        // inbox itself performs the navigation to the conversation.
        .onReceive(InboxBus.shared.openConversation) { _ in
            tab = .chats
        }
    }

    // MARK: - Floating glass tab bar (design: glass capsule, amber active)

    private struct TabItem {
        let tab: MainTab
        let icon: String
        let title: String
    }

    private var items: [TabItem] {
        [
            TabItem(tab: .chats, icon: "bubble.left.and.bubble.right", title: L("المحادثات")),
            TabItem(tab: .calls, icon: "phone", title: L("المكالمات")),
            TabItem(tab: .reports, icon: "chart.bar.xaxis", title: L("التقارير")),
            TabItem(tab: .settings, icon: "gearshape", title: L("الإعدادات")),
        ]
    }

    private var floatingBar: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.tab) { item in
                tabButton(item)
            }
        }
        .padding(6)
        .glassCard(Theme.Radius.tabBar)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func tabButton(_ item: TabItem) -> some View {
        let isActive = tab == item.tab
        return Button {
            select(item.tab)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: item.icon)
                    .font(.wx(17, .medium))
                    // Fills only where the symbol has a fill variant.
                    .symbolVariant(isActive ? .fill : .none)
                if isActive {
                    Text(item.title)
                        .font(.wx(12.5, .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isActive ? .white : Theme.onMuted)
            .padding(.horizontal, isActive ? 16 : 12)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                if isActive {
                    Capsule().fill(Theme.amberAction)
                        .matchedGeometryEffect(id: "activeTab", in: activeTabNamespace)
                        .shadow(color: Theme.amberShadow, radius: 8, y: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.tab == .chats, unread.total > 0 {
                    Text("\(min(unread.total, 99))")
                        .font(.wx(10, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1.5)
                        .background(Theme.danger, in: Capsule())
                        .offset(x: 4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: isActive ? nil : .infinity)
        .accessibilityLabel(item.title)
    }

    /// DOUBLE-press on the chats tab toggles the inbox's archive mode:
    /// two taps within the window count; a single (re)tap does nothing.
    private func select(_ newValue: MainTab) {
        if newValue != tab { Haptics.selection() }
        if newValue == .chats {
            let now = Date()
            if tab == .chats, let last = lastChatsTap, now.timeIntervalSince(last) < 0.45 {
                InboxBus.shared.toggleArchive.send()
                lastChatsTap = nil
            } else {
                lastChatsTap = now
            }
        } else {
            lastChatsTap = nil
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            tab = newValue
        }
    }
}

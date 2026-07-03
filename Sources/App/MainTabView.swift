import SwiftUI

enum MainTab: Hashable { case chats, calls, reports, integrations, settings }

// System tab bar, pinned to the BOTTOM with icon-only items.
//
// iPadOS 18+ renders TabView as a top text-label bar by default; forcing the
// compact horizontal size class keeps the classic bottom bar (still native
// Liquid Glass on iOS 26). Icon-only tab items (no Text) replace the word
// labels; the selected symbol picks up its .fill variant automatically.
struct MainTabView: View {
    @State private var tab: MainTab = .chats
    @StateObject private var unread = UnreadCenter.shared

    var body: some View {
        TabView(selection: $tab) {
            InboxView()
                .tabItem { Image(systemName: "bubble.left.and.bubble.right").accessibilityLabel("المحادثات") }
                .tag(MainTab.chats)
                .badge(unread.total)
            CallsView()
                .tabItem { Image(systemName: "phone").accessibilityLabel("المكالمات") }
                .tag(MainTab.calls)
            StatsView()
                .tabItem { Image(systemName: "chart.bar").accessibilityLabel("الإحصاءات") }
                .tag(MainTab.reports)
            IntegrationsView()
                .tabItem { Image(systemName: "point.3.connected.trianglepath.dotted").accessibilityLabel("التكاملات") }
                .tag(MainTab.integrations)
            SettingsView()
                .tabItem { Image(systemName: "gearshape").accessibilityLabel("الإعدادات") }
                .tag(MainTab.settings)
        }
        .tint(Theme.primary)
        .environment(\.horizontalSizeClass, .compact)
    }
}

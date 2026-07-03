import SwiftUI

enum MainTab: Hashable { case integrations, chats, settings, search }

// Telegram-style bottom bar: three labeled tabs (Integrations · Chats ·
// Settings) plus the system search tab, which iOS 26 renders as the separate
// floating glass circle that morphs into a search field. Calls + Statistics
// live inside Settings. The compact size class keeps the bar at the BOTTOM
// on iPad; below iOS 26 (or pre-iOS-26 toolchains) a classic labeled tab bar
// with a regular search tab is used instead.
struct MainTabView: View {
    @State private var tab: MainTab = .chats
    @StateObject private var unread = UnreadCenter.shared

    var body: some View {
        Group {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                modernTabs
            } else {
                legacyTabs
            }
            #else
            legacyTabs
            #endif
        }
        .tint(Theme.primary)
        .environment(\.horizontalSizeClass, .compact)
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var modernTabs: some View {
        TabView(selection: $tab) {
            Tab("التكاملات", systemImage: "point.3.connected.trianglepath.dotted", value: MainTab.integrations) {
                IntegrationsView()
            }
            Tab("المحادثات", systemImage: "bubble.left.and.bubble.right", value: MainTab.chats) {
                InboxView()
            }
            .badge(unread.total)
            Tab("الإعدادات", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
            Tab(value: MainTab.search, role: .search) {
                GlobalSearchView()
            }
        }
    }
    #endif

    private var legacyTabs: some View {
        TabView(selection: $tab) {
            IntegrationsView()
                .tabItem { Label("التكاملات", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(MainTab.integrations)
            InboxView()
                .tabItem { Label("المحادثات", systemImage: "bubble.left.and.bubble.right") }
                .tag(MainTab.chats)
                .badge(unread.total)
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape") }
                .tag(MainTab.settings)
            GlobalSearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                .tag(MainTab.search)
        }
    }
}

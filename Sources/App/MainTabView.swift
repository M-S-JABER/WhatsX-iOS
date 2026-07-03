import SwiftUI

enum MainTab: Hashable { case chats, calls, reports, integrations, settings }

// System tab bar: on iOS 26 the OS renders it as the floating Liquid Glass
// bar automatically; the classic tabItem form (instead of the iOS 18+ Tab
// API) keeps the package loadable on iOS 16+ / Swift Playgrounds.
// `.tint` carries the amber brand accent on the selected tab.
struct MainTabView: View {
    @State private var tab: MainTab = .chats
    @StateObject private var unread = UnreadCenter.shared

    var body: some View {
        TabView(selection: $tab) {
            InboxView()
                .tabItem { Label("المحادثات", systemImage: "bubble.left.and.bubble.right") }
                .tag(MainTab.chats)
                .badge(unread.total)
            CallsView()
                .tabItem { Label("المكالمات", systemImage: "phone") }
                .tag(MainTab.calls)
            StatsView()
                .tabItem { Label("الإحصاءات", systemImage: "chart.bar") }
                .tag(MainTab.reports)
            IntegrationsView()
                .tabItem { Label("التكاملات", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(MainTab.integrations)
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(Theme.primary)
    }
}

import SwiftUI

enum MainTab: Hashable { case chats, calls, reports, integrations, settings }

// Native iOS 26 Liquid Glass tab bar: TabView + Tab renders the floating glass
// bar automatically; `.tint` carries the amber brand accent on the selected tab.
struct MainTabView: View {
    @State private var tab: MainTab = .chats

    var body: some View {
        TabView(selection: $tab) {
            Tab("المحادثات", systemImage: "bubble.left.and.bubble.right", value: MainTab.chats) {
                InboxView()
            }
            Tab("المكالمات", systemImage: "phone", value: MainTab.calls) {
                CallsView()
            }
            Tab("الإحصاءات", systemImage: "chart.bar", value: MainTab.reports) {
                StatsView()
            }
            Tab("التكاملات", systemImage: "point.3.connected.trianglepath.dotted", value: MainTab.integrations) {
                IntegrationsView()
            }
            Tab("الإعدادات", systemImage: "gearshape", value: MainTab.settings) {
                SettingsView()
            }
        }
        .tint(Theme.primary)
    }
}

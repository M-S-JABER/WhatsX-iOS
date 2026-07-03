import SwiftUI
import UIKit
import Combine

enum MainTab: Hashable { case integrations, chats, settings, search }

/// Tiny event bus between the tab bar and the inbox: re-tapping the chats
/// tab (a second press while already on it) flips active ⇄ archive.
@MainActor
final class InboxBus: ObservableObject {
    static let shared = InboxBus()
    let toggleArchive = PassthroughSubject<Void, Never>()
}

/// Downloads the signed avatar and renders it as a small circular tab icon
/// (original colors, aspect-filled). Falls back to the gear symbol until an
/// avatar exists; reloads whenever the user or their avatar changes.
@MainActor
final class TabAvatar: ObservableObject {
    static let shared = TabAvatar()

    @Published var image: UIImage? = nil
    private var loadedKey: String?

    func load(for user: AuthUser?) async {
        guard let user, let avatar = user.avatar, !avatar.isEmpty,
              let url = Api.avatarURL(userId: user.id, avatar: avatar) else {
            image = nil
            loadedKey = nil
            return
        }
        let key = user.id + "|" + avatar
        guard key != loadedKey else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = UIImage(data: data) else { return }
        loadedKey = key
        image = Self.circularIcon(source, side: 27)
    }

    private static func circularIcon(_ source: UIImage, side: CGFloat) -> UIImage {
        let size = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            let scale = max(side / max(source.size.width, 1), side / max(source.size.height, 1))
            let w = source.size.width * scale
            let h = source.size.height * scale
            source.draw(in: CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
        }
        return rendered.withRenderingMode(.alwaysOriginal)
    }
}

// Bottom bar: Integrations · Chats (center, badge) · Settings (user avatar
// as the icon) + the system search tab. On iOS 26 the search tab is the
// separate floating glass circle whose tap morphs the bottom bar into a
// search field over the same conversations list. The compact size class
// keeps the bar at the BOTTOM on iPad; below iOS 26 a classic labeled bar
// with a regular search tab is used.
struct MainTabView: View {
    @State private var tab: MainTab = .chats
    @StateObject private var unread = UnreadCenter.shared
    @StateObject private var avatar = TabAvatar.shared

    /// Re-selecting the chats tab toggles the inbox's archive mode.
    private var tabSelection: Binding<MainTab> {
        Binding(
            get: { tab },
            set: { newValue in
                if newValue == .chats && tab == .chats {
                    InboxBus.shared.toggleArchive.send()
                }
                tab = newValue
            }
        )
    }

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
        .task { await avatar.load(for: Session.shared.user) }
        .onReceive(Session.shared.$user) { user in
            Task { await avatar.load(for: user) }
        }
    }

    @ViewBuilder
    private var settingsTabIcon: some View {
        if let icon = avatar.image {
            Image(uiImage: icon)
        } else {
            Image(systemName: "gearshape")
        }
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var modernTabs: some View {
        TabView(selection: tabSelection) {
            Tab("التكاملات", systemImage: "point.3.connected.trianglepath.dotted", value: MainTab.integrations) {
                IntegrationsView()
            }
            Tab("المحادثات", systemImage: "bubble.left.and.bubble.right", value: MainTab.chats) {
                InboxView()
            }
            .badge(unread.total)
            Tab(value: MainTab.settings) {
                SettingsView()
            } label: {
                settingsTabIcon
                Text("الإعدادات")
            }
            Tab(value: MainTab.search, role: .search) {
                GlobalSearchView()
            }
        }
    }
    #endif

    private var legacyTabs: some View {
        TabView(selection: tabSelection) {
            IntegrationsView()
                .tabItem { Label("التكاملات", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(MainTab.integrations)
            InboxView()
                .tabItem { Label("المحادثات", systemImage: "bubble.left.and.bubble.right") }
                .tag(MainTab.chats)
                .badge(unread.total)
            SettingsView()
                .tabItem {
                    settingsTabIcon
                    Text("الإعدادات")
                }
                .tag(MainTab.settings)
            GlobalSearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
                .tag(MainTab.search)
        }
    }
}

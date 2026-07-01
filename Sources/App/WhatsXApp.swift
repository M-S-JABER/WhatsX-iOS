import SwiftUI

@main
struct WhatsXApp: App {
    @StateObject private var session = Session.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environment(\.layoutDirection, .rightToLeft)   // Arabic-first, RTL
                .tint(Theme.primary)
                .task { await session.bootstrap() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var session: Session

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if session.isBootstrapping {
                ProgressView().tint(Theme.primary)
            } else if session.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
    }
}

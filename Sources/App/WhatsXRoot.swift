import SwiftUI

/// Public entry point of the WhatsX app as a library view.
///
/// The iPad (Swift Playgrounds) shell app — and the macOS `@main` in
/// `WhatsXApp.swift` — both just render `WhatsXRoot()`. It wires the session,
/// RTL/Arabic layout, tint, and initial bootstrap so the host needs nothing else.
public struct WhatsXRoot: View {
    @StateObject private var session = Session.shared

    public init() {}

    public var body: some View {
        RootView()
            .environmentObject(session)
            .environment(\.layoutDirection, .rightToLeft)   // Arabic-first, RTL
            .tint(Theme.primary)
            .task { await session.bootstrap() }
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

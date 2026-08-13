import SwiftUI

/// Public entry point of the WhatsX app as a library view.
///
/// The iPad (Swift Playgrounds) shell app — and the macOS `@main` in
/// `WhatsXApp.swift` — both just render `WhatsXRoot()`. It wires the session,
/// RTL/Arabic layout, tint, and initial bootstrap so the host needs nothing else.
public struct WhatsXRoot: View {
    @StateObject private var session = Session.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    public init() {
        // Register the bundled web-parity typeface before any text renders.
        WXFont.registerIfNeeded()
    }

    public var body: some View {
        RootView()
            .environmentObject(session)
            // Live in-app language: RTL/LTR flips (and every L() string
            // re-resolves) the moment the setting changes — .id forces the
            // whole tree to rebuild.
            .environment(\.layoutDirection, settings.isArabic ? .rightToLeft : .leftToRight)
            .id(settings.language)
            .preferredColorScheme(settings.colorScheme)
            .tint(Theme.primary)
            .overlay {
                if lock.isLocked { LockScreenView(lock: lock) }
            }
            .task {
                lock.lockIfEnabled()
                await session.bootstrap()
            }
            .onChange(of: scenePhase) { phase in
                // Cover the UI the moment the app leaves the foreground so
                // chats never show in the app switcher.
                if phase == .background { lock.lockIfEnabled() }
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
                IncomingCallBanner()
            } else {
                LoginView()
            }
        }
    }
}

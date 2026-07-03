import SwiftUI

// App-wide auth/session state (cookie-based). Mirrors Android's Session.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    @Published var user: AuthUser? = nil
    @Published var isBootstrapping = true
    @Published var isLoggingIn = false
    @Published var loginError: String? = nil

    var isAuthenticated: Bool { user != nil }

    /// On launch, try to restore an existing session from the stored cookie.
    func bootstrap() async {
        do { user = try await Api.shared.me() } catch { user = nil }
        isBootstrapping = false
        if isAuthenticated { startLiveServices() }
    }

    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        do {
            user = try await Api.shared.login(username: username, password: password)
            startLiveServices()
        } catch {
            loginError = (error as? ApiError)?.message ?? error.localizedDescription
        }
        isLoggingIn = false
    }

    func logout() async {
        Realtime.shared.disconnect()
        try? await Api.shared.logout()
        user = nil
    }

    /// Realtime socket + the consumers that must outlive any single screen.
    private func startLiveServices() {
        Realtime.shared.connect()
        CallCenter.shared.start()
        Notifier.shared.start()
    }
}

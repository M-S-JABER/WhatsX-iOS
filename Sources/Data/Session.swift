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
        clearLocalSession()
    }

    /// Called by the API layer when any authenticated call answers 401 —
    /// the cookie expired or was revoked server-side. Drops straight back to
    /// the login screen instead of leaving a "logged-in" app whose every
    /// request fails.
    func handleUnauthorized() {
        guard user != nil else { return }
        Realtime.shared.disconnect()
        clearLocalSession()
        loginError = L("انتهت الجلسة — سجّل الدخول من جديد")
    }

    /// Wipes local auth state. The session cookie is removed even when the
    /// server logout call never succeeded (offline logout must still forget
    /// the credentials on this device).
    private func clearLocalSession() {
        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
        user = nil
    }

    /// Realtime socket + the consumers that must outlive any single screen.
    private func startLiveServices() {
        Realtime.shared.connect()
        CallCenter.shared.start()
        Notifier.shared.start()
    }
}

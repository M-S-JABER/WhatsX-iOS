import Foundation
import Security

// The session cookie is the app's only credential, and it used to live in
// HTTPCookieStorage.shared — a plain file inside the app container that is
// included in backups and protected only by default file protection. These
// two types move it where it belongs:
//   - SessionCookies: an in-memory-only cookie store shared by every
//     network stack in the app.
//   - CookieVault: persists the cookies encrypted in the Keychain
//     (this-device-only) and restores them at launch, migrating whatever
//     older versions stored in the legacy file-backed store.

/// The unified non-persistent cookie store for all networking (REST,
/// WebSocket, image loading, audio/video players). An ephemeral
/// configuration's storage never touches disk.
enum SessionCookies {
    static let store: HTTPCookieStorage = {
        let s = URLSessionConfiguration.ephemeral.httpCookieStorage ?? HTTPCookieStorage()
        s.cookieAcceptPolicy = .always
        return s
    }()

    static var all: [HTTPCookie] { store.cookies ?? [] }

    static func removeAll() {
        for cookie in all { store.deleteCookie(cookie) }
    }
}

/// Saves/restores the session cookies through the Keychain — with
/// AfterFirstUnlockThisDeviceOnly accessibility they never leave the device
/// and are excluded from backups.
enum CookieVault {
    private static let service = "com.m-s-jaber.whatsx.session"
    private static let account = "cookies"

    /// Overwrites the stored snapshot with the current cookies. Called after
    /// a successful login/restore and when the app backgrounds — the server
    /// may roll the session cookie while the app is in use.
    static func save(_ cookies: [HTTPCookie] = SessionCookies.all) {
        guard !cookies.isEmpty else {
            clear()
            return
        }
        // Cookie properties contain expiry Dates; plist supports Date, JSON does not.
        let payload: [[String: Any]] = cookies.compactMap { cookie in
            guard let props = cookie.properties else { return nil }
            var out: [String: Any] = [:]
            for (key, value) in props { out[key.rawValue] = value }
            return out
        }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: payload, format: .binary, options: 0) else { return }

        var query = baseQuery
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    /// Loads the stored cookies back into the store — called once at launch,
    /// before the first request.
    static func restore() {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let payload = (try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil)) as? [[String: Any]]
        else { return }
        for props in payload {
            var typed: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in props { typed[HTTPCookiePropertyKey(key)] = value }
            if let cookie = HTTPCookie(properties: typed) {
                SessionCookies.store.setCookie(cookie)
            }
        }
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    /// Older versions kept the cookie in HTTPCookieStorage.shared (a file on
    /// disk). Move whatever is there into the new store and wipe it — the
    /// user stays signed in across the upgrade and no plaintext copy remains.
    static func migrateLegacyStore() {
        let legacy = HTTPCookieStorage.shared.cookies ?? []
        guard !legacy.isEmpty else { return }
        for cookie in legacy {
            SessionCookies.store.setCookie(cookie)
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        save()
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

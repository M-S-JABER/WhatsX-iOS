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
/// WebSocket, image loading, audio/video players).
enum SessionCookies {
    static let store: HTTPCookieStorage = InMemoryCookieStorage()

    static var all: [HTTPCookie] { store.cookies ?? [] }

    static func removeAll() {
        for cookie in all { store.deleteCookie(cookie) }
    }
}

/// A purely in-memory HTTPCookieStorage. Borrowing an ephemeral
/// configuration's storage does not work — detached from its session,
/// setCookie silently drops cookies — so this subclass owns the jar
/// itself. URLSession routes cookie traffic for custom storage subclasses
/// through storeCookies(_:for:) / getCookiesFor(_:completionHandler:),
/// both of which resolve to the overrides below, so nothing ever reaches
/// the on-disk cookie file.
final class InMemoryCookieStorage: HTTPCookieStorage {
    private let lock = NSLock()
    private var jar: [String: HTTPCookie] = [:]

    private func key(_ cookie: HTTPCookie) -> String {
        "\(cookie.name)|\(cookie.domain.lowercased())|\(cookie.path)"
    }

    override var cookies: [HTTPCookie]? {
        lock.lock()
        defer { lock.unlock() }
        purgeExpired()
        return Array(jar.values)
    }

    override var cookieAcceptPolicy: HTTPCookie.AcceptPolicy {
        get { .always }
        set {}
    }

    override func setCookie(_ cookie: HTTPCookie) {
        lock.lock()
        defer { lock.unlock() }
        jar[key(cookie)] = cookie
    }

    override func deleteCookie(_ cookie: HTTPCookie) {
        lock.lock()
        defer { lock.unlock() }
        jar.removeValue(forKey: key(cookie))
    }

    override func removeCookies(since date: Date) {
        // Creation dates aren't tracked; the only use this app has is a
        // full wipe, so that is what it does.
        lock.lock()
        defer { lock.unlock() }
        jar = [:]
    }

    override func cookies(for url: URL) -> [HTTPCookie]? {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        lock.lock()
        defer { lock.unlock() }
        purgeExpired()
        return jar.values.filter { cookie in
            domainMatches(cookieDomain: cookie.domain.lowercased(), host: host)
                && path.hasPrefix(cookie.path.isEmpty ? "/" : cookie.path)
        }
    }

    override func setCookies(_ cookies: [HTTPCookie], for url: URL?, mainDocumentURL: URL?) {
        for cookie in cookies { setCookie(cookie) }
    }

    override func storeCookies(_ cookies: [HTTPCookie], for task: URLSessionTask) {
        setCookies(cookies, for: task.currentRequest?.url, mainDocumentURL: nil)
    }

    override func getCookiesFor(_ task: URLSessionTask, completionHandler: @escaping ([HTTPCookie]?) -> Void) {
        guard let url = task.currentRequest?.url else {
            completionHandler([])
            return
        }
        completionHandler(cookies(for: url))
    }

    /// Caller must hold the lock.
    private func purgeExpired() {
        let now = Date()
        jar = jar.filter { _, cookie in cookie.expiresDate.map { $0 > now } ?? true }
    }

    private func domainMatches(cookieDomain: String, host: String) -> Bool {
        // Dotted domains (Set-Cookie with a Domain attribute) cover
        // subdomains; host-only cookies match that exact host, per RFC 6265.
        if cookieDomain.hasPrefix(".") {
            let domain = String(cookieDomain.dropFirst())
            return host == domain || host.hasSuffix("." + domain)
        }
        return host == cookieDomain
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

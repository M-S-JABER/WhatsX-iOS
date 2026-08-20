import XCTest
@testable import WhatsX

/// CookieVault is the only thing standing between a fresh launch and the
/// login screen — a broken roundtrip silently signs every user out.
final class CookieVaultTests: XCTestCase {

    private func makeCookie(name: String = "passport", value: String = "secret-token") -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: "whatsx.example.com",
            .path: "/",
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 86_400),
        ])!
    }

    override func setUp() {
        super.setUp()
        SessionCookies.removeAll()
        CookieVault.clear()
    }

    override func tearDown() {
        SessionCookies.removeAll()
        CookieVault.clear()
        super.tearDown()
    }

    func testSaveRestoreRoundtrip() {
        let cookie = makeCookie()
        CookieVault.save([cookie])

        SessionCookies.removeAll()
        XCTAssertTrue(SessionCookies.all.isEmpty)

        CookieVault.restore()
        let restored = SessionCookies.all
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.name, "passport")
        XCTAssertEqual(restored.first?.value, "secret-token")
        XCTAssertEqual(restored.first?.domain, "whatsx.example.com")
    }

    func testClearRemovesStoredCookies() {
        CookieVault.save([makeCookie()])
        CookieVault.clear()

        SessionCookies.removeAll()
        CookieVault.restore()
        XCTAssertTrue(SessionCookies.all.isEmpty)
    }

    func testSavingEmptyListClearsTheVault() {
        CookieVault.save([makeCookie()])
        CookieVault.save([])

        SessionCookies.removeAll()
        CookieVault.restore()
        XCTAssertTrue(SessionCookies.all.isEmpty)
    }

    func testMigrationMovesLegacyCookiesAndWipesTheOldStore() {
        let legacy = makeCookie(name: "legacy-passport")
        HTTPCookieStorage.shared.setCookie(legacy)

        CookieVault.migrateLegacyStore()

        XCTAssertTrue(SessionCookies.all.contains { $0.name == "legacy-passport" })
        let leftover = HTTPCookieStorage.shared.cookies?.contains { $0.name == "legacy-passport" }
        XCTAssertNotEqual(leftover, true)

        // The migrated cookie must also survive a relaunch (vault roundtrip).
        SessionCookies.removeAll()
        CookieVault.restore()
        XCTAssertTrue(SessionCookies.all.contains { $0.name == "legacy-passport" })
    }
}

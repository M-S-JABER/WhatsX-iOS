import XCTest

/// App Store screenshot capture. Launches the app in demo mode (canned
/// Arabic fixtures, no server) and walks the five marketing screens,
/// attaching a full-screen PNG for each. The ios-screenshots workflow runs
/// this on iPhone and iPad simulators and exports the attachments.
final class WhatsXScreenshots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-wx-demo"]
        app.launch()

        // 01 — Inbox: wait for a demo conversation row to render.
        let firstRow = app.staticTexts["أم محمد"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 30), "inbox did not load")
        capture("01-inbox")

        // 02 — Chat: open the main demo thread; the header's back button
        // (explicit accessibility label) marks the screen as loaded.
        firstRow.tap()
        let backButton = app.buttons["رجوع"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 15), "chat did not open")
        // Let the timeline settle (auto-scroll to the newest message).
        Thread.sleep(forTimeInterval: 2)
        capture("02-chat")

        // Back to the tab roots (the floating tab bar hides inside a chat).
        backButton.tap()
        Thread.sleep(forTimeInterval: 1)

        // 03 — Calls tab.
        app.buttons["المكالمات"].firstMatch.tap()
        let callRow = app.staticTexts["حسين كريم"].firstMatch
        _ = callRow.waitForExistence(timeout: 15)
        capture("03-calls")

        // 04 — Reports tab.
        app.buttons["التقارير"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        capture("04-reports")

        // 05 — Settings tab.
        app.buttons["الإعدادات"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        capture("05-settings")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

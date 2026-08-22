import XCTest
@testable import WhatsX

/// The floating tab bar hides while a chat is pushed (TestFlight feedback
/// on 1.23.0: the bar covered the composer). The pushed-chats counter must
/// stay balanced and never go negative — a stray extra disappear must not
/// hide the bar forever.
@MainActor
final class InboxBusTests: XCTestCase {
    func testPushedChatsBalances() {
        let bus = InboxBus()
        XCTAssertEqual(bus.pushedChats, 0)
        bus.chatDidAppear()
        XCTAssertEqual(bus.pushedChats, 1)
        bus.chatDidAppear()
        XCTAssertEqual(bus.pushedChats, 2)
        bus.chatDidDisappear()
        bus.chatDidDisappear()
        XCTAssertEqual(bus.pushedChats, 0)
    }

    func testPushedChatsNeverGoesNegative() {
        let bus = InboxBus()
        bus.chatDidDisappear()
        XCTAssertEqual(bus.pushedChats, 0)
        bus.chatDidAppear()
        XCTAssertEqual(bus.pushedChats, 1)
    }

    func testPendingConversationConsumedOnce() {
        let bus = InboxBus()
        bus.requestOpenConversation("c1")
        XCTAssertEqual(bus.consumePendingConversation(), "c1")
        XCTAssertNil(bus.consumePendingConversation())
    }
}

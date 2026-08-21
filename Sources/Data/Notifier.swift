import UIKit
import Combine
import UserNotifications

// Local-notification bridge for realtime events — the package-feasible stand-in
// for APNs/FCM (which need native entitlements a Swift Playgrounds app can't
// hold). While the app is running, incoming messages and WhatsApp calls raise
// system banners with sound; the open conversation never notifies about itself.
// Main-actor isolated: `activeConversationId` is mutated by ChatView and read
// from the realtime sink (which publishes on main), and `handle` touches
// UIApplication — the isolation makes that contract explicit instead of
// depending on Realtime's delivery thread.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// UserDefaults key for the Settings toggle (@AppStorage uses the same key).
    static let messagesEnabledKey = "whatsx.notify.messages"

    /// The conversation currently on screen — set/cleared by ChatView.
    var activeConversationId: String? = nil

    private var cancellable: AnyCancellable?

    /// Idempotent. Call once the user is authenticated (main thread).
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        // Standard APNs registration for message pushes while the app is
        // closed (docs/VOIP_PUSH.md, "Message alert pushes"). The token
        // lands in the app delegate → MessagePush. Independent of the
        // authorization answer — registration works either way.
        UIApplication.shared.registerForRemoteNotifications()
        guard cancellable == nil else { return }
        cancellable = Realtime.shared.events.sink { [weak self] event in
            self?.handle(event)
        }
    }

    /// Runs on the main thread (Realtime publishes on main).
    private func handle(_ event: RealtimeEvent) {
        switch event.name {
        case "message_incoming":
            let enabled = UserDefaults.standard.object(forKey: Self.messagesEnabledKey) as? Bool ?? true
            guard enabled else { return }
            // Skip only when the user is actively looking at that conversation.
            let inThatChat = event.conversationId != nil
                && event.conversationId == activeConversationId
                && UIApplication.shared.applicationState == .active
            guard !inThatChat else { return }
            // Local banners may carry the full text — they never leave the
            // device (unlike remote pushes, which are sender-name-only).
            // The conversationId makes a tap open the right chat, exactly
            // like a remote push.
            post(title: event.senderLabel?.isEmpty == false ? event.senderLabel! : L("رسالة واردة جديدة"),
                 body: event.body?.isEmpty == false ? event.body! : L("وسائط 📎"),
                 userInfo: event.conversationId.map {
                     ["type": MessagePushPayload.incomingType, "conversationId": $0]
                 } ?? [:])
        case "voice_call_incoming":
            Haptics.warning()
            post(title: L("مكالمة واتساب واردة 📞"),
                 body: event.displayName ?? event.phone ?? "")
        default:
            break
        }
    }

    private func post(title: String, body: String, userInfo: [AnyHashable: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Present LOCAL banners with sound even while the app is in the
    // foreground — but suppress REMOTE pushes there: the server always sends
    // them (it cannot know the app is open), and the WS-driven local banner
    // above already covers the foreground case; showing both would double
    // every message. nonisolated: the notification center calls this on its
    // own queue and the body touches no actor state.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.trigger is UNPushNotificationTrigger {
            completionHandler([])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    // Tapping a message push (typically from the lock screen, app closed)
    // opens the conversation it references.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let id = MessagePushPayload.conversationId(from: userInfo) {
            Task { @MainActor in InboxBus.shared.requestOpenConversation(id) }
        }
        completionHandler()
    }
}

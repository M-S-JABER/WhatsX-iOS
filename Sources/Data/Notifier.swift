import UIKit
import Combine
import UserNotifications

// Local-notification bridge for realtime events — the package-feasible stand-in
// for APNs/FCM (which need native entitlements a Swift Playgrounds app can't
// hold). While the app is running, incoming messages and WhatsApp calls raise
// system banners with sound; the open conversation never notifies about itself.
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
            post(title: event.senderLabel?.isEmpty == false ? event.senderLabel! : L("رسالة واردة جديدة"),
                 body: event.body?.isEmpty == false ? event.body! : L("وسائط 📎"))
        case "voice_call_incoming":
            post(title: L("مكالمة واتساب واردة 📞"),
                 body: event.displayName ?? event.phone ?? "")
        default:
            break
        }
    }

    private func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Present banners with sound even while the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

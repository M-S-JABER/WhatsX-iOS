import SwiftUI

/// App-wide unread total for the chats tab badge. Fed by the inbox whenever
/// it (re)loads — which, thanks to Realtime, also happens on every incoming
/// message — so the badge stays live without its own fetching.
@MainActor
final class UnreadCenter: ObservableObject {
    static let shared = UnreadCenter()
    @Published var total = 0
}

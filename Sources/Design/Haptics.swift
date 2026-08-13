import UIKit

/// One tap-feel vocabulary for the whole app — call these instead of creating
/// generators inline so the intensity language stays consistent.
enum Haptics {
    /// Light tick — chip taps, toggles, minor selections.
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    /// Medium thump — primary actions (send, record, archive).
    static func action() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    /// Selection tick — tab switches, segment changes.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

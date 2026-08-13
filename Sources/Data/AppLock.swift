import SwiftUI
import LocalAuthentication

/// Face ID / passcode app lock. When enabled, the UI is covered whenever the
/// app leaves the foreground and unlocks only after biometric (or device
/// passcode) authentication.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published var isLocked = false
    private var authenticating = false

    /// Cover the UI (called when the scene backgrounds, and at launch).
    func lockIfEnabled() {
        if AppSettings.shared.faceIDLock { isLocked = true }
    }

    /// Prompt Face ID / passcode; unlocks on success.
    func unlock() async {
        guard isLocked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        var error: NSError?
        // Device-owner auth = Face ID with passcode fallback. If neither is
        // set up on the device there is nothing to check against — unlock.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: L("افتح WhatsX"))
            if ok {
                isLocked = false
                Haptics.success()
            }
        } catch {
            Haptics.error()
        }
    }
}

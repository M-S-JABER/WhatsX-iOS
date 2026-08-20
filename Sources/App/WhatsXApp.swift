import SwiftUI

// NOTE: This @main entry is for building the app directly with Xcode/XcodeGen
// on a Mac. It is EXCLUDED from the Swift Package (see Package.swift) because a
// library cannot declare an entry point. On iPad (Swift Playgrounds) the shell
// app provides its own @main and just renders `WhatsXRoot()` from the package.
@main
struct WhatsXApp: App {
    @UIApplicationDelegateAdaptor(WhatsXAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WhatsXRoot()
        }
    }
}

/// The VoIP push registry must exist from the very start of the process — a
/// push can cold-start the app in the background, before any scene or view
/// is built — so it is created in the app delegate, the earliest hook a
/// SwiftUI app has. Excluded from the package together with @main above
/// (calls are unsupported there anyway).
final class WhatsXAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        VoIPPush.shared.activate()
        return true
    }
}

import SwiftUI

// NOTE: This @main entry is for building the app directly with Xcode/XcodeGen
// on a Mac. It is EXCLUDED from the Swift Package (see Package.swift) because a
// library cannot declare an entry point. On iPad (Swift Playgrounds) the shell
// app provides its own @main and just renders `WhatsXRoot()` from the package.
@main
struct WhatsXApp: App {
    var body: some Scene {
        WindowGroup {
            WhatsXRoot()
        }
    }
}

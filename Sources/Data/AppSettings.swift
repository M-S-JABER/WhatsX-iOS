import SwiftUI

/// User-tunable app behavior: language, appearance and the Face ID lock.
/// Values persist in UserDefaults; views observe this object so a change
/// re-renders the whole tree live (no relaunch).
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let languageKey = "whatsx.language"       // system | ar | en
    static let appearanceKey = "whatsx.appearance"   // system | light | dark
    static let faceIDKey = "whatsx.faceIDLock"

    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: Self.languageKey)
            L10n.override = language
        }
    }
    @Published var appearance: String {
        didSet { UserDefaults.standard.set(appearance, forKey: Self.appearanceKey) }
    }
    @Published var faceIDLock: Bool {
        didSet { UserDefaults.standard.set(faceIDLock, forKey: Self.faceIDKey) }
    }

    private init() {
        language = UserDefaults.standard.string(forKey: Self.languageKey) ?? "system"
        appearance = UserDefaults.standard.string(forKey: Self.appearanceKey) ?? "system"
        faceIDLock = UserDefaults.standard.bool(forKey: Self.faceIDKey)
        L10n.override = language
    }

    var isArabic: Bool {
        switch language {
        case "ar": return true
        case "en": return false
        default: return L10n.systemIsArabic
        }
    }

    /// nil follows the system appearance.
    var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

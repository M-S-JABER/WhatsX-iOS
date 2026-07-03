import SwiftUI
import CoreText

/// Web-parity typeface: IBM Plex Sans Arabic (bundled in Resources/Fonts),
/// the same font the web client uses. `Font.wx(size, weight)` replaces
/// `Font.system` across the app so all text renders with the web's type.
enum WXFont {
    private static var registered = false

    /// Registers the bundled faces with Core Text (idempotent).
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func name(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black:
            return "IBMPlexSansArabic-Bold"
        case .semibold:
            return "IBMPlexSansArabic-SemiBold"
        case .medium:
            return "IBMPlexSansArabic-Medium"
        default:
            return "IBMPlexSansArabic-Regular"
        }
    }
}

extension Font {
    /// The app typeface at a given size/weight. `.custom` falls back to the
    /// system font automatically when the face is unavailable.
    static func wx(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        WXFont.registerIfNeeded()
        return .custom(WXFont.name(for: weight), size: size)
    }
}

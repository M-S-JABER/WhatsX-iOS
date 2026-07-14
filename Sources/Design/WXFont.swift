import SwiftUI
import CoreText

/// Web-parity typeface: IBM Plex Sans Arabic (bundled in Resources/Fonts),
/// the same font the web client uses. `Font.wx(size, weight)` replaces
/// `Font.system` across the app so all text renders with the web's type.
enum WXFont {
    private static var registered = false

    /// The bundle carrying the .ttf files: the SwiftPM resource bundle when
    /// built as a package (Playgrounds), the app bundle when built as an app
    /// target (XcodeGen), where resources are copied flat into the root.
    private static var fontBundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    /// Registers the bundled faces with Core Text (idempotent).
    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        var urls = fontBundle.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        if urls.isEmpty {
            urls = fontBundle.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        }
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

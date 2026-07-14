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
    /// Nearest system text style for a design size — anchors custom fonts to
    /// Dynamic Type so the whole app honors the user's text-size setting.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<15: return .footnote
        case ..<16: return .subheadline
        case ..<18: return .body
        case ..<21: return .title3
        case ..<26: return .title2
        case ..<32: return .title
        default: return .largeTitle
        }
    }

    /// The app typeface at a given size/weight, scaling with Dynamic Type.
    /// `.custom` falls back to the system font when the face is unavailable.
    static func wx(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        WXFont.registerIfNeeded()
        return .custom(WXFont.name(for: weight), size: size, relativeTo: textStyle(for: size))
    }
}

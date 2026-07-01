import SwiftUI
import UIKit

// Luxe Amber identity — mirrors the Android theme (Color.kt / design tokens).
// Colors are dynamic UIColors so they adapt to light/dark automatically.

extension UIColor {
    fileprivate convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

extension Color {
    /// A color that resolves to `light` in light mode and `dark` in dark mode.
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

enum Theme {
    // Core surfaces / text
    static let background = Color(light: 0xF7F2E8, dark: 0x0C0A06)   // screen canvas
    static let surface = Color(light: 0xFFFFFF, dark: 0x15110A)      // cards
    static let surface1 = Color(light: 0xFBF7EE, dark: 0x19150D)
    static let surface2 = Color(light: 0xF1EADB, dark: 0x221C12)     // chips / tiles
    static let surface3 = Color(light: 0xE9E0CD, dark: 0x2C2418)
    static let onSurface = Color(light: 0x211B12, dark: 0xF1EBDC)
    static let onMuted = Color(light: 0x6E654F, dark: 0xABA08A)
    static let onFaint = Color(light: 0x97907F, dark: 0x756B57)
    static let outline = Color(light: 0xE5DCC8, dark: 0x2A2317)

    // Accent
    static let primary = Color(light: 0xB07D1A, dark: 0xE6B24E)      // saffron amber
    static let onPrimary = Color(light: 0xFFFFFF, dark: 0x2A1E05)
    static let primaryContainer = Color(light: 0xF7E7C2, dark: 0x4A3809)
    static let primarySoft = Color(light: 0xFBF1DC, dark: 0x241D10)

    // Chat bubbles
    static let bubbleIn = Color(light: 0xFFFFFF, dark: 0x1E1810)
    static let bubbleInFg = Color(light: 0x211B12, dark: 0xF1EBDC)
    static let bubbleOut = Color(light: 0xF6E7C0, dark: 0x4A3809)
    static let bubbleOutFg = Color(light: 0x3D2D08, dark: 0xF8E7BE)

    // Semantic
    static let success = Color(light: 0x2E9466, dark: 0x4FB489)
    static let info = Color(light: 0x3B6FB0, dark: 0x7FA9DE)
    static let warning = Color(light: 0xB8860B, dark: 0xE6B24E)
    static let danger = Color(light: 0xC5483A, dark: 0xE78579)
    static let dangerBg = Color(light: 0xF8E2DE, dark: 0x2E1714)

    // Gradient for the login hero (matches the Android amber hero).
    static let heroGradient = LinearGradient(
        colors: [Color(light: 0x8E5E11, dark: 0x8E5E11),
                 Color(light: 0xC68A22, dark: 0xC68A22),
                 Color(light: 0xE0A52E, dark: 0xE0A52E)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Distinct donut/chart segment palette (theme-independent), matching the web.
    static let chartPalette: [Color] = [
        Color(rgb: 0x1FA98A), Color(rgb: 0x3B82C4), Color(rgb: 0xCE6A47),
        Color(rgb: 0x7C6BD0), Color(rgb: 0x5C9A3A), Color(rgb: 0xC68A22),
    ]
}

extension Color {
    /// Solid RGB (theme-independent) — used for the fixed chart palette.
    init(rgb: UInt) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

// Stable per-account color from a seed string (mirrors Android accountColor()).
enum AccountColor {
    private static let swatches: [UInt] = [
        0x1FA98A, 0x3B82C4, 0xCE6A47, 0x7C6BD0, 0x5C9A3A, 0xC68A22, 0xB0517A, 0x3F7E8C,
    ]
    static func color(_ seed: String) -> Color {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = Int(scalar.value) &+ (hash &* 31) }
        let idx = abs(hash) % swatches.count
        return Color(rgb: swatches[idx])
    }
}

import SwiftUI
import UIKit

// WEB-PARITY palette — every token is converted from the web client's CSS
// variables (client/src/index.css + whatsx-redesign.css), light AND dark,
// so the app matches the web's Luxe Amber theme and its dark mode exactly.
// Chat bubbles mirror the web's WhatsApp-style pair (pale green / deep teal).

extension Color {
    /// A color that resolves to `light` in light mode and `dark` in dark mode.
    init(light: UInt, dark: UInt) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}

enum Theme {
    // Core surfaces / text — web --background/--card/--sidebar/--secondary.
    static let background = Color(light: 0xF8F6F2, dark: 0x1C1A17)   // --background
    static let surface = Color(light: 0xFFFFFF, dark: 0x24211E)      // --card
    static let surface1 = Color(light: 0xF2EEE9, dark: 0x221F1C)     // --sidebar
    static let surface2 = Color(light: 0xEAE6E1, dark: 0x37332F)     // --secondary
    static let surface3 = Color(light: 0xD9D3C9, dark: 0x48423D)     // --input
    static let onSurface = Color(light: 0x2A241D, dark: 0xEFECE6)    // --foreground
    static let onMuted = Color(light: 0x696159, dark: 0xADA69F)      // --muted-foreground
    static let onFaint = Color(light: 0x938A80, dark: 0x7C756E)
    static let outline = Color(light: 0xE2DDD5, dark: 0x3D3834)      // --border

    // Accent — the web's saffron amber --primary.
    static let primary = Color(light: 0xD98E26, dark: 0xE4A944)
    static let onPrimary = Color(light: 0x261F17, dark: 0x201A13)    // --primary-foreground
    static let primaryContainer = Color(light: 0xF2D7B0, dark: 0x6F522A)
    static let primarySoft = Color(light: 0xFAEDDB, dark: 0x493B27)  // --accent

    // Chat bubbles — web --wx-message-in/out (WhatsApp-style).
    static let bubbleIn = Color(light: 0xFFFFFF, dark: 0x172024)
    static let bubbleInFg = Color(light: 0x111B21, dark: 0xF4F7F6)
    static let bubbleOut = Color(light: 0xD9FDD3, dark: 0x005C4B)
    static let bubbleOutFg = Color(light: 0x0B332B, dark: 0xFFFFFF)

    // Semantic — web statuses (emerald / slate / amber / --destructive).
    static let success = Color(light: 0x4D8970, dark: 0x6BB395)
    static let info = Color(light: 0x63789C, dark: 0x97A7C4)
    static let warning = Color(light: 0xC17915, dark: 0xE4A944)
    static let danger = Color(light: 0xD44A35, dark: 0xD46554)
    static let dangerBg = Color(light: 0xF9E9E7, dark: 0x391D18)
    /// The web's purple accent (--chart-5); dark-mode aware — screens must
    /// use this token, never a raw hex.
    static let accentPurple = Color(light: 0x89639C, dark: 0xAC88BF)

    // Layout tokens — one scale instead of per-screen magic numbers. New code
    // should draw radii/spacing from here; existing screens migrate as touched.
    enum Radius {
        static let chip: CGFloat = 10
        static let field: CGFloat = 14
        static let card: CGFloat = 18
        static let panel: CGFloat = 22
    }
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // Login hero gradient — the web's amber hero.
    static let heroGradient = LinearGradient(
        colors: [Color(light: 0x8E5E11, dark: 0x8E5E11),
                 Color(light: 0xC68A22, dark: 0xC68A22),
                 Color(light: 0xE0A52E, dark: 0xE0A52E)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Charts — web --chart-1…5 (light/dark aware) + a teal companion.
    static let chartPalette: [Color] = [
        Color(light: 0xD98E26, dark: 0xECB351),
        Color(light: 0x63789C, dark: 0x97A7C4),
        Color(light: 0x4D8970, dark: 0x6BB395),
        Color(light: 0xC67553, dark: 0xD38969),
        Color(light: 0x89639C, dark: 0xAC88BF),
        Color(light: 0x3F7E8C, dark: 0x6FA9B8),
    ]
}

extension Color {
    /// Solid RGB (theme-independent) — used for the fixed account palette.
    init(rgb: UInt) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

// Stable per-account color from a seed string — the web chart swatches.
enum AccountColor {
    private static let swatches: [UInt] = [
        0xD98E26, 0x63789C, 0x4D8970, 0xC67553, 0x89639C, 0x3F7E8C, 0xB0517A, 0x5C9A3A,
    ]
    static func color(_ seed: String) -> Color {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = Int(scalar.value) &+ (hash &* 31) }
        let idx = abs(hash) % swatches.count
        return Color(rgb: swatches[idx])
    }
}

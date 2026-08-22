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

    /// Mode-aware color WITH alpha — the glass recipe needs translucency.
    init(light: UInt, lightAlpha: CGFloat, dark: UInt, darkAlpha: CGFloat) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(rgb: dark).withAlphaComponent(darkAlpha)
                : UIColor(rgb: light).withAlphaComponent(lightAlpha)
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
    // Core surfaces / text. Light values follow the WhatsX 2.0 design
    // handoff (docs: design_handoff_whatsx_redesign); the handoff specs
    // light mode only, so dark values stay the Luxe Amber dark palette.
    static let background = Color(light: 0xF6F1E9, dark: 0x1C1A17)   // 2.0 base
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

    // ── WhatsX 2.0 tokens (design handoff) ────────────────────────────────

    /// Content sheet above the base background (lists, panes).
    static let surfaceContent = Color(light: 0xF8F6F2, dark: 0x211E1B)
    /// Fixed dark chrome — the login top block; NOT mode-aware by design.
    static let darkChrome = Color(rgb: 0x211D18)
    /// In-call screen chrome (4l), slightly warmer than the login chrome.
    static let callChrome = Color(rgb: 0x1C1916)
    /// Amber on dark chrome (logo tile, login CTA text).
    static let amberOnDark = Color(rgb: 0xE4A944)
    /// Amber TEXT on light surfaces (passes contrast, unlike the fill amber).
    static let amberText = Color(light: 0xB16E14, dark: 0xE4A944)
    /// Unread-row timestamp accent.
    static let unreadTime = Color(light: 0xC08119, dark: 0xE4A944)

    /// The prominent-action gradient (send button, active tab, counters).
    static let amberAction = LinearGradient(
        colors: [Color(rgb: 0xE3A93B), Color(rgb: 0xD08A1F)],
        startPoint: .top, endPoint: .bottom)
    /// Shadow tint under amber actions.
    static let amberShadow = Color(rgb: 0xD08A1F).opacity(0.4)

    // Segmented controls: track + floating active thumb.
    static let segmentedTrack = Color(light: 0xE9E4DC, dark: 0x37332F)
    static let segmentedActive = Color(light: 0xFFFFFF, dark: 0x4A443E)

    // Chat (design 4c/4n): read ticks + the suggested-reply chip family.
    static let readTick = Color(rgb: 0x53BDEB)
    static let draftChipBg = Color(light: 0xFBF0D6, lightAlpha: 0.85, dark: 0x493B27, darkAlpha: 0.85)
    static let draftChipBorder = Color(light: 0xEBCF8E, dark: 0x6F522A)
    static let draftChipText = Color(light: 0x8A6414, dark: 0xE4A944)
    static let draftCardBg = Color(light: 0xFBF0D6, lightAlpha: 0.9, dark: 0x493B27, darkAlpha: 0.9)

    // Glass recipe (pre-iOS 26 fallback fills; see Glass.swift).
    static let glassFill = Color(light: 0xFFFFFF, lightAlpha: 0.58, dark: 0x2A2622, darkAlpha: 0.55)
    static let glassBorder = Color(light: 0xFFFFFF, lightAlpha: 0.7, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let glassHighlight = Color(light: 0xFFFFFF, lightAlpha: 0.8, dark: 0xFFFFFF, darkAlpha: 0.08)

    /// The app-wide warm radial glow behind content (2.0 base background).
    /// Screens apply it via `Theme.glowBackground()`.
    @ViewBuilder
    static func glowBackground() -> some View {
        background.overlay(
            RadialGradient(
                colors: [Color(rgb: 0xE0A52E).opacity(0.15), .clear],
                center: .init(x: 0.25, y: 0.08), startRadius: 0, endRadius: 420)
        ).ignoresSafeArea()
    }

    // Layout tokens — one scale instead of per-screen magic numbers. New code
    // should draw radii/spacing from here; existing screens migrate as touched.
    enum Radius {
        static let chip: CGFloat = 10
        static let field: CGFloat = 14
        static let card: CGFloat = 18
        static let panel: CGFloat = 22
        // 2.0 additions.
        static let cardTight: CGFloat = 16
        static let chatHeader: CGFloat = 24
        static let tabBar: CGFloat = 32
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

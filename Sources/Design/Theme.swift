import SwiftUI
import UIKit

// Native Apple palette — every token maps to a UIKit system color, so the
// whole app looks and adapts (light/dark, increased contrast) exactly like
// Apple's own apps. The bubble pair mirrors Messages (blue out / gray in).

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
    // Core surfaces / text — the standard iOS grouped-list stack.
    static let background = Color(uiColor: .systemGroupedBackground)          // screen canvas
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)    // cards
    static let surface1 = Color(uiColor: .secondarySystemBackground)
    static let surface2 = Color(uiColor: .tertiarySystemFill)                 // chips / tiles
    static let surface3 = Color(uiColor: .secondarySystemFill)
    static let onSurface = Color(uiColor: .label)
    static let onMuted = Color(uiColor: .secondaryLabel)
    static let onFaint = Color(uiColor: .tertiaryLabel)
    static let outline = Color(uiColor: .separator)

    // Accent — Apple's system blue, like Messages/FaceTime/Phone.
    static let primary = Color(uiColor: .systemBlue)
    static let onPrimary = Color.white
    static let primaryContainer = Color(uiColor: .systemBlue).opacity(0.22)
    static let primarySoft = Color(uiColor: .systemBlue).opacity(0.12)

    // Chat bubbles — Messages-style: blue outgoing, gray incoming.
    static let bubbleIn = Color(uiColor: .secondarySystemBackground)
    static let bubbleInFg = Color(uiColor: .label)
    static let bubbleOut = Color(uiColor: .systemBlue)
    static let bubbleOutFg = Color.white

    // Semantic — the system palette.
    static let success = Color(uiColor: .systemGreen)
    static let info = Color(uiColor: .systemBlue)
    static let warning = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)
    static let dangerBg = Color(uiColor: .systemRed).opacity(0.12)

    // Login hero gradient — system blues.
    static let heroGradient = LinearGradient(
        colors: [Color(uiColor: .systemBlue), Color(uiColor: .systemIndigo)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Distinct donut/chart segment palette (system colors).
    static let chartPalette: [Color] = [
        Color(uiColor: .systemTeal), Color(uiColor: .systemBlue), Color(uiColor: .systemOrange),
        Color(uiColor: .systemPurple), Color(uiColor: .systemGreen), Color(uiColor: .systemYellow),
    ]
}

extension Color {
    /// Solid RGB (theme-independent) — used for the fixed account palette.
    init(rgb: UInt) {
        self.init(uiColor: UIColor(rgb: rgb))
    }
}

// Stable per-account color from a seed string — system palette swatches.
enum AccountColor {
    private static let swatches: [UIColor] = [
        .systemTeal, .systemBlue, .systemOrange, .systemPurple,
        .systemGreen, .systemYellow, .systemPink, .systemIndigo,
    ]
    static func color(_ seed: String) -> Color {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = Int(scalar.value) &+ (hash &* 31) }
        let idx = abs(hash) % swatches.count
        return Color(uiColor: swatches[idx])
    }
}

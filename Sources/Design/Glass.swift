import SwiftUI

// Reusable native Liquid Glass (iOS 26) building blocks for WhatsX.
// Cards/panels and chips render on real Liquid Glass instead of flat fills;
// group nearby glass shapes in a `GlassEffectContainer` so they blend & morph.
extension View {
    /// A Liquid Glass panel/card with a continuous rounded-rectangle shape.
    func glassCard(_ radius: CGFloat = 22) -> some View {
        glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A capsule glass surface for chips, pills, and floating controls.
    func glassCapsule(interactive: Bool = false) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
    }

    /// A circular glass surface for icon buttons.
    func glassCircle(interactive: Bool = true) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
    }

    /// A brand-tinted Liquid Glass capsule for accent/primary controls.
    func glassAccent(interactive: Bool = true) -> some View {
        glassEffect(
            interactive ? .regular.tint(Theme.primary).interactive() : .regular.tint(Theme.primary),
            in: Capsule()
        )
    }
}

import SwiftUI

// Liquid Glass building blocks with graceful degradation.
//
// On iOS 26+ (compiled with an iOS 26 SDK toolchain) cards, chips and icon
// buttons render on real Liquid Glass; group nearby glass shapes in a
// `GlassEffectContainer` so they blend & morph. On older systems — or when
// built by a toolchain predating the iOS 26 SDK (e.g. older Swift Playgrounds
// releases) — they fall back to the classic Luxe surfaces, so the package
// keeps loading, building and looking right everywhere.
extension View {
    /// A panel/card with a continuous rounded-rectangle shape.
    /// Liquid Glass on iOS 26; Luxe surface + outline below.
    @ViewBuilder
    func glassCard(_ radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            // Tinted with the Luxe surface so iOS 26 glass carries the same
            // warm palette (and dark-mode contrast) as the pre-26 fallback.
            glassEffect(.regular.tint(Theme.surface.opacity(0.5)), in: shape)
        } else {
            luxeSurface(in: shape)
        }
        #else
        luxeSurface(in: shape)
        #endif
    }

    /// A capsule surface for chips, pills, and floating controls.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(
                interactive ? .regular.tint(Theme.surface2.opacity(0.5)).interactive()
                            : .regular.tint(Theme.surface2.opacity(0.5)),
                in: Capsule())
        } else {
            luxeChip(in: Capsule())
        }
        #else
        luxeChip(in: Capsule())
        #endif
    }

    /// A circular surface for icon buttons.
    @ViewBuilder
    func glassCircle(interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(
                interactive ? .regular.tint(Theme.surface2.opacity(0.5)).interactive()
                            : .regular.tint(Theme.surface2.opacity(0.5)),
                in: Circle())
        } else {
            luxeChip(in: Circle())
        }
        #else
        luxeChip(in: Circle())
        #endif
    }

    /// A brand-tinted capsule for accent/primary controls.
    @ViewBuilder
    func glassAccent(interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(
                interactive ? .regular.tint(Theme.primary).interactive() : .regular.tint(Theme.primary),
                in: Capsule()
            )
        } else {
            background(Theme.primary, in: Capsule())
        }
        #else
        background(Theme.primary, in: Capsule())
        #endif
    }

    /// Pre-iOS 26 stand-in for glass cards: the classic Luxe card surface.
    private func luxeSurface<S: InsettableShape>(in shape: S) -> some View {
        background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
    }

    /// Pre-iOS 26 stand-in for glass chips/circles: the classic Luxe chip fill.
    private func luxeChip<S: InsettableShape>(in shape: S) -> some View {
        background(Theme.surface2, in: shape)
            .overlay(shape.strokeBorder(Theme.outline, lineWidth: 1))
    }
}

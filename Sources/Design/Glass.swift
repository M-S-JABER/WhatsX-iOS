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

    /// Pre-iOS 26 stand-in for glass cards — the WhatsX 2.0 glass recipe:
    /// translucent white over system blur, hairline light border, an inner
    /// top highlight, and a soft drop shadow.
    private func luxeSurface<S: InsettableShape>(in shape: S) -> some View {
        background {
            // The drop shadow hangs off the SHAPE here, not off the composed
            // view: shadowing the whole card rebuilt its full alpha mask
            // (blur + borders + content) every frame, which dragged large
            // panels like the calls log. Same look, far cheaper.
            shape.fill(Theme.glassFill)
                .background(.ultraThinMaterial, in: shape)
                .shadow(color: .black.opacity(0.1), radius: 12, y: 8)
        }
        .overlay(shape.strokeBorder(Theme.glassBorder, lineWidth: 1))
        .overlay(
            // Inner highlight: a light line hugging the top edge.
            shape.inset(by: 0.5).strokeBorder(
                LinearGradient(colors: [Theme.glassHighlight, .clear],
                               startPoint: .top, endPoint: .center),
                lineWidth: 1.5)
        )
    }

    /// Pre-iOS 26 stand-in for glass chips/circles — same recipe, no drop
    /// shadow (chips repeat in lists; per-row shadows are visual noise and
    /// a scrolling cost).
    private func luxeChip<S: InsettableShape>(in shape: S) -> some View {
        background {
            shape.fill(Theme.glassFill)
                .background(.ultraThinMaterial, in: shape)
        }
        .overlay(shape.strokeBorder(Theme.glassBorder, lineWidth: 1))
    }
}

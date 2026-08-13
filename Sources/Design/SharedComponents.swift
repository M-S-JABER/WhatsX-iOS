import SwiftUI

// Shared building blocks that used to be copy-pasted per screen — one source
// of truth for KPI tiles, status capsules and the time-range chip row.

/// KPI tile: muted caption over a big colored value, on a glass card.
/// (Was duplicated in Stats, Integrations and Customer reports.)
struct MetricTile: View {
    let label: String
    let value: String
    var color: Color = Theme.onSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.wx(12)).foregroundStyle(Theme.onMuted)
            Text(value).font(.wx(26, .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Space.l).padding(.vertical, 14)
        .glassCard(20)
    }
}

/// Colored status capsule — the "string → (label, color)" mapping stays with
/// each caller; the visual treatment lives here once.
struct StatusCapsule: View {
    let text: String
    let color: Color
    var showDot: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showDot { Circle().fill(color).frame(width: 6, height: 6) }
            Text(text.isEmpty ? "—" : text).font(.wx(11, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

/// Three pulsing dots — the classic "typing…" indicator.
struct TypingDots: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Theme.success).frame(width: 5, height: 5)
                    .scaleEffect(animate ? 1 : 0.55)
                    .opacity(animate ? 1 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                        value: animate)
            }
        }
        .onAppear { animate = true }
    }
}

/// Time-range chips shared by Statistics and Customer reports.
struct RangeChipsRow: View {
    let selected: String?
    let onSelect: (String?) -> Void

    private static let ranges: [(String?, String)] = [
        (nil, L("الكل")), ("24h", L("24س")), ("7d", L("7 أيام")),
        ("30d", L("30 يومًا")), ("90d", L("90 يومًا")),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(Self.ranges, id: \.1) { key, label in
                    let active = selected == key
                    Button { onSelect(key) } label: {
                        Text(label).font(.wx(15, .semibold))
                            .foregroundStyle(active ? Theme.background : Theme.onMuted)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(active ? Theme.onSurface : Theme.surface2, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

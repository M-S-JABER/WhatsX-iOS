import SwiftUI

/// The WhatsX 2.0 floating-thumb segmented control — the same recipe the
/// inbox and calls filters draw inline. Screens added after phase D share
/// this one implementation instead of copying the pattern again.
struct GlassSegmented: View {
    let items: [(key: String, title: String)]
    @Binding var selection: String
    @Namespace private var thumbNamespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.key) { item in
                let active = selection == item.key
                Button {
                    guard !active else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        selection = item.key
                    }
                } label: {
                    Text(item.title)
                        .font(.wx(13, active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.onSurface : Theme.onMuted)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.segmentedActive)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.segmentedTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

import SwiftUI

/// WhatsApp-style swipe-to-reply: drag a bubble horizontally past the
/// threshold to quote-reply it. The bubble follows the finger with damping,
/// a reply arrow fades in, and a haptic fires the moment the gesture arms.
struct SwipeToReply<Content: View>: View {
    let onReply: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var dragX: CGFloat = 0
    @State private var armed = false
    private let threshold: CGFloat = 56

    var body: some View {
        content()
            .offset(x: dragX)
            .background(alignment: dragX >= 0 ? .leading : .trailing) {
                Image(systemName: "arrowshape.turn.up.left.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.primary)
                    .opacity(Double(min(abs(dragX) / threshold, 1)))
                    .scaleEffect(armed ? 1.15 : 0.9)
                    .padding(.horizontal, 14)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: armed)
            }
            .gesture(
                DragGesture(minimumDistance: 25)
                    .onChanged { value in
                        // Horizontal intent only — let vertical drags scroll.
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        dragX = max(-84, min(84, value.translation.width * 0.55))
                        let over = abs(value.translation.width) > threshold
                        if over != armed {
                            armed = over
                            if over { Haptics.action() }
                        }
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > threshold { onReply() }
                        armed = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { dragX = 0 }
                    }
            )
    }
}

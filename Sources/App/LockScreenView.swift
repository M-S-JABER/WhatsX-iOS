import SwiftUI

/// Full-screen cover shown while the app is locked behind Face ID. Content
/// underneath is fully hidden (privacy: customer chats must not leak into
/// the app switcher or over someone's shoulder).
struct LockScreenView: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Theme.heroGradient.opacity(0.14).ignoresSafeArea()
            VStack(spacing: 18) {
                BrandMark(size: 84)
                Text(L("التطبيق مقفل")).font(.wx(20, .bold)).foregroundStyle(Theme.onSurface)
                Button {
                    Task { await lock.unlock() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid").font(.wx(18))
                        Text(L("اضغط للفتح")).font(.wx(16, .semibold))
                    }
                    .padding(.horizontal, 26).padding(.vertical, 13)
                    .background(Theme.primary, in: Capsule())
                    .foregroundStyle(Theme.onPrimary)
                }
                .buttonStyle(.pressable)
            }
        }
        .task { await lock.unlock() }
    }
}

/// The app's brand mark — the icon's chat bubble + X, reusable in login and
/// the lock screen so the identity reads the same everywhere.
struct BrandMark: View {
    var size: CGFloat = 74

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.heroGradient)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.18), radius: size * 0.12, y: size * 0.06)
            Image(systemName: "bubble.left.fill")
                .font(.system(size: size * 0.5))
                .foregroundStyle(.white)
            Text("X")
                .font(.wx(size * 0.26, .bold))
                .foregroundStyle(Color(rgb: 0xB16E14))
                .offset(y: -size * 0.045)
        }
    }
}

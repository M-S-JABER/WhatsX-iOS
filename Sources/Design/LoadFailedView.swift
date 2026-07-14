import SwiftUI

/// Shared inline error state: message + retry button, themed. Screens show it
/// wherever a load failed instead of silently rendering an empty state.
struct LoadFailedView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.wx(30)).foregroundStyle(Theme.onFaint)
            Text(L("تعذّر التحميل")).font(.wx(16, .semibold)).foregroundStyle(Theme.onSurface)
            Text(message).font(.wx(13)).foregroundStyle(Theme.onMuted)
                .multilineTextAlignment(.center)
                .lineLimit(4)
            if let retry {
                Button {
                    Haptics.tap()
                    retry()
                } label: {
                    HStack(spacing: 6) {
                        Image(icon: .refresh).font(.wx(13))
                        Text(L("إعادة المحاولة")).font(.wx(14, .semibold))
                    }
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.primary, in: Capsule())
                    .foregroundStyle(Theme.onPrimary)
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32).padding(.horizontal, 20)
    }
}

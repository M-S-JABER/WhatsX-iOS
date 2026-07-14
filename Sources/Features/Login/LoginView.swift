import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showServer = false
    @State private var serverURL = AppConfig.baseURL

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                form.padding(20)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Text("W")
                .font(.wx(40, .bold))
                .foregroundStyle(.white)
                .frame(width: 74, height: 74)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 22))
            Text("WhatsX").font(.wx(30, .bold)).foregroundStyle(.white)
            Text(L("منصّة إدارة محادثات واتساب")).font(.wx(15)).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80).padding(.bottom, 40)
        .background(Theme.heroGradient)
        .clipShape(RoundedCorners(radius: 34, corners: [.bottomLeft, .bottomRight]))
    }

    private var form: some View {
        VStack(spacing: 14) {
            Text(L("مرحبًا بعودتك")).font(.wx(20, .bold)).foregroundStyle(Theme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)

            field(icon: .user, placeholder: L("اسم المستخدم")) {
                TextField(L("اسم المستخدم"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
            }

            field(icon: .lock, placeholder: L("كلمة المرور")) {
                Group {
                    if showPassword { TextField(L("كلمة المرور"), text: $password) }
                    else { SecureField(L("كلمة المرور"), text: $password) }
                }
                .autocorrectionDisabled()
                .textContentType(.password)
                Button { showPassword.toggle() } label: {
                    Image(icon: showPassword ? .eyeOff : .eye).foregroundStyle(Theme.onMuted)
                }
            }

            if let err = session.loginError {
                Text(err).font(.wx(13)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                AppConfig.baseURL = serverURL
                Task { await session.login(username: username, password: password) }
            } label: {
                HStack {
                    if session.isLoggingIn { ProgressView().tint(Theme.onPrimary) }
                    else { Text(L("تسجيل الدخول")).font(.wx(17, .semibold)) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.primary, in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(Theme.onPrimary)
            }
            .disabled(session.isLoggingIn || username.isEmpty || password.isEmpty)

            DisclosureGroup(isExpanded: $showServer) {
                field(icon: .cloud, placeholder: "https://server") {
                    TextField("https://server", text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                .padding(.top, 8)
            } label: {
                Label(L("إعدادات الخادم"), systemImage: WIcon.settings.symbol())
                    .font(.wx(15)).foregroundStyle(Theme.onMuted)
            }
            .tint(Theme.onMuted)
        }
    }

    @ViewBuilder
    private func field(icon: WIcon, placeholder: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(icon: icon).foregroundStyle(Theme.onFaint)
            ZStack(alignment: .leading) {
                content()
            }
            .foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }
}

// Rounded specific corners helper.
struct RoundedCorners: Shape {
    var radius: CGFloat = 16
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                          cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

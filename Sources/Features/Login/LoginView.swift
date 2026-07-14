import SwiftUI
import UIKit

/// Sign-in screen: brand mark over the amber hero, a floating glass card with
/// focus-ring fields, springy primary button, and haptic feedback on
/// success/failure. Fields animate in on first appearance.
struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var showServer = false
    @State private var serverURL = AppConfig.baseURL
    @State private var appeared = false
    @FocusState private var focused: Field?

    private enum Field { case username, password, server }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                hero
                card
                    .padding(.horizontal, 20)
                    .offset(y: -34)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? -34 : -10)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8).delay(0.1)) { appeared = true }
        }
        .onChange(of: session.loginError) { err in
            if err != nil { Haptics.error() }
        }
        .onChange(of: session.user) { user in
            if user != nil { Haptics.success() }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            BrandMark(size: 92)
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
            Text("WhatsX").font(.wx(32, .bold)).foregroundStyle(.white)
            Text(L("منصّة إدارة محادثات واتساب"))
                .font(.wx(15)).foregroundStyle(.white.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 76).padding(.bottom, 64)
        .background(
            Theme.heroGradient
                .overlay(
                    RadialGradient(colors: [.white.opacity(0.16), .clear],
                                   center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 380)
                )
        )
        .clipShape(RoundedCorners(radius: 36, corners: [.bottomLeft, .bottomRight]))
    }

    private var card: some View {
        VStack(spacing: 14) {
            VStack(spacing: 3) {
                Text(L("مرحبًا بعودتك")).font(.wx(21, .bold)).foregroundStyle(Theme.onSurface)
                Text(L("سجّل دخولك للمتابعة")).font(.wx(13)).foregroundStyle(Theme.onMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)

            field(icon: .user, active: focused == .username) {
                TextField(L("اسم المستخدم"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            field(icon: .lock, active: focused == .password) {
                Group {
                    if showPassword { TextField(L("كلمة المرور"), text: $password) }
                    else { SecureField(L("كلمة المرور"), text: $password) }
                }
                .autocorrectionDisabled()
                .textContentType(.password)
                .focused($focused, equals: .password)
                .submitLabel(.go)
                .onSubmit { logIn() }
                Button {
                    showPassword.toggle()
                    Haptics.tap()
                } label: {
                    Image(icon: showPassword ? .eyeOff : .eye).foregroundStyle(Theme.onMuted)
                }
                .accessibilityLabel(showPassword ? L("إخفاء كلمة المرور") : L("إظهار كلمة المرور"))
            }

            if let err = session.loginError {
                HStack(spacing: 6) {
                    Image(icon: .alert).font(.wx(12))
                    Text(err).font(.wx(13))
                }
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Button(action: logIn) {
                HStack(spacing: 8) {
                    if session.isLoggingIn {
                        ProgressView().tint(Theme.onPrimary)
                    } else {
                        Text(L("تسجيل الدخول")).font(.wx(17, .semibold))
                        Image(icon: .forward).font(.wx(14, .semibold))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
                .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 5)
            }
            .buttonStyle(.pressable)
            .disabled(session.isLoggingIn || username.isEmpty || password.isEmpty)
            .opacity(username.isEmpty || password.isEmpty ? 0.55 : 1)
            .animation(.easeOut(duration: 0.2), value: username.isEmpty || password.isEmpty)

            DisclosureGroup(isExpanded: $showServer.animation(.spring(response: 0.35, dampingFraction: 0.85))) {
                field(icon: .cloud, active: focused == .server) {
                    TextField("https://server", text: $serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused, equals: .server)
                        .environment(\.layoutDirection, .leftToRight)
                }
                .padding(.top, 8)
            } label: {
                Label(L("إعدادات الخادم"), systemImage: WIcon.settings.symbol())
                    .font(.wx(14)).foregroundStyle(Theme.onMuted)
            }
            .tint(Theme.onMuted)
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Theme.outline, lineWidth: 1))
        .shadow(color: .black.opacity(0.09), radius: 22, y: 10)
    }

    private func logIn() {
        guard !username.isEmpty, !password.isEmpty, !session.isLoggingIn else { return }
        Haptics.action()
        AppConfig.baseURL = serverURL
        Task { await session.login(username: username, password: password) }
    }

    @ViewBuilder
    private func field(icon: WIcon, active: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(icon: icon).foregroundStyle(active ? Theme.primary : Theme.onFaint)
            content().foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(active ? Theme.primary : Theme.outline, lineWidth: active ? 1.5 : 1)
        )
        .animation(.easeOut(duration: 0.18), value: active)
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

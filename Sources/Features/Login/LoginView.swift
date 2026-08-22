import SwiftUI
import UIKit

/// Sign-in screen — WhatsX 2.0 (design 4a): a fixed dark chrome block on top
/// (flat amber brand tile, value line, muted description) flowing into a
/// light sheet with white fields, a dark CTA with amber text, and the server
/// row with the saved address in mono. No hero gradient. All behaviors from
/// the previous screen survive: server-address gate, focus flow, password
/// reveal, error surface, haptics.
struct LoginView: View {
    @EnvironmentObject var session: Session
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    /// Auto-expanded on first run: with no saved server address the login
    /// button is gated, and hiding the reason would read as a bug.
    @State private var showServer = !AppConfig.hasServer
    @State private var serverURL = AppConfig.baseURL
    @State private var appeared = false
    @FocusState private var focused: Field?

    private enum Field { case username, password, server }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                darkBlock
                lightBlock
            }
        }
        .background(alignment: .top) {
            // The chrome bleeds behind the status bar / rubber-band zone.
            VStack(spacing: 0) {
                Theme.darkChrome.frame(height: 600)
                Theme.surfaceContent
            }
            .ignoresSafeArea()
        }
        .background(Theme.surfaceContent.ignoresSafeArea())
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

    // MARK: - Dark chrome (top)

    private var darkBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandMark(size: 64, flat: true)
                .scaleEffect(appeared ? 1 : 0.8)
                .opacity(appeared ? 1 : 0)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("مساحة عمل فريقك على واتساب."))
                    .font(.wx(30, .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("محادثات، مكالمات، وتقارير — على خادمكم الخاص."))
                    .font(.wx(14))
                    .foregroundStyle(Color(rgb: 0x9C948C))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 110).padding(.horizontal, 28).padding(.bottom, 44)
        .background(Theme.darkChrome)
    }

    // MARK: - Light sheet (fields + CTA)

    private var lightBlock: some View {
        VStack(spacing: 14) {
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
                        ProgressView().tint(Theme.amberOnDark)
                    } else {
                        Text(L("دخول")).font(.wx(16, .semibold))
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Theme.darkChrome, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(Theme.amberOnDark)
            }
            .buttonStyle(.pressable)
            .disabled(session.isLoggingIn || !canSubmit)
            .opacity(canSubmit ? 1 : 0.55)
            .animation(.easeOut(duration: 0.2), value: canSubmit)

            serverRow
        }
        .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 32)
        .background(Theme.surfaceContent)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }

    private var serverRow: some View {
        DisclosureGroup(isExpanded: $showServer.animation(.spring(response: 0.35, dampingFraction: 0.85))) {
            field(icon: .cloud, active: focused == .server) {
                TextField("https://server", text: $serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused, equals: .server)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .padding(.top, 8)
            // First run has no saved address — explain the disabled button
            // instead of letting it look broken.
            if serverURL.trimmed().isEmpty {
                Text(L("أدخل عنوان خادم WhatsX الخاص بك للمتابعة."))
                    .font(.wx(12))
                    .foregroundStyle(Theme.onMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            }
        } label: {
            HStack(spacing: 8) {
                Label(L("إعدادات الخادم"), systemImage: WIcon.settings.symbol())
                    .font(.wx(14)).foregroundStyle(Theme.onMuted)
                Spacer()
                if !showServer, !serverURL.trimmed().isEmpty {
                    // The saved address, mono 12 (design 4a).
                    Text(serverURL.trimmed()
                        .replacingOccurrences(of: "https://", with: ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.onFaint)
                        .lineLimit(1).truncationMode(.middle)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .tint(Theme.onMuted)
        .padding(.top, 4)
    }

    /// The server address gates login: WhatsX is self-hosted, so there is no
    /// default the app could assume.
    private var canSubmit: Bool {
        !username.isEmpty && !password.isEmpty && !serverURL.trimmed().isEmpty
    }

    private func logIn() {
        guard canSubmit, !session.isLoggingIn else { return }
        Haptics.action()
        AppConfig.baseURL = serverURL
        Task { await session.login(username: username, password: password) }
    }

    /// White field, r12, 1.5px border; the border turns amber on focus.
    @ViewBuilder
    private func field(icon: WIcon, active: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(icon: icon).foregroundStyle(active ? Theme.primary : Theme.onFaint)
            content().foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(active ? Theme.primary : Theme.outline, lineWidth: 1.5)
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

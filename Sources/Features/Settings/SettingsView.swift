import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var session: Session
    @State private var loggingOut = false
    @State private var editOpen = false
    @State private var passwordOpen = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @AppStorage(Notifier.messagesEnabledKey) private var notifyMessages = true
    @StateObject private var settings = AppSettings.shared
    /// Integrations row summary (design 4f) — filled lazily, silent on failure.
    @State private var integrationsSummary = L("الأنظمة والتدفق والويب هوك")

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            HStack {
                Text(L("الإعدادات")).font(.wx(22, .bold)).foregroundStyle(Theme.onSurface)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ScrollView {
                // WhatsX 2.0 (design 4f): THREE groups — profile,
                // preferences, and manager-tagged work management — with
                // monochrome icon tiles throughout.
                VStack(alignment: .leading, spacing: 4) {
                    profileCard.padding(.horizontal, 14).padding(.vertical, 6)
                    group {
                        Button { passwordOpen = true } label: {
                            SettingRow(icon: .lock, title: L("تغيير كلمة المرور"), trailingChevron: true)
                        }.buttonStyle(.plain)
                    }

                    section(L("التفضيلات"))
                    group {
                        HStack {
                            SettingRow(icon: .sun, title: L("المظهر"))
                            Picker("", selection: $settings.appearance) {
                                Text(L("تلقائي")).tag("system")
                                Text(L("فاتح")).tag("light")
                                Text(L("داكن")).tag("dark")
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.onMuted)
                            .padding(.trailing, 8)
                            .onChange(of: settings.appearance) { _ in Haptics.tap() }
                        }
                        HStack {
                            SettingRow(icon: .lang, title: L("اللغة"))
                            Picker("", selection: $settings.language) {
                                Text(L("تلقائي")).tag("system")
                                Text(L("العربية")).tag("ar")
                                Text("English").tag("en")
                            }
                            .pickerStyle(.menu)
                            .tint(Theme.onMuted)
                            .padding(.trailing, 8)
                            .onChange(of: settings.language) { _ in Haptics.tap() }
                        }
                        HStack {
                            SettingRow(icon: .bell, title: L("تنبيهات الرسائل الجديدة"),
                                       subtitle: L("أثناء تشغيل التطبيق (صوت + لافتة)"))
                            Toggle("", isOn: $notifyMessages)
                                .labelsHidden()
                                .tint(Theme.primary)
                                .padding(.trailing, 14)
                        }
                        HStack {
                            SettingRow(icon: .lock, title: L("قفل بالوجه (Face ID)"),
                                       subtitle: L("يُقفل التطبيق عند مغادرته"))
                            Toggle("", isOn: $settings.faceIDLock)
                                .labelsHidden()
                                .tint(Theme.primary)
                                .padding(.trailing, 14)
                                .onChange(of: settings.faceIDLock) { _ in Haptics.tap() }
                        }
                        NavigationLink { VoiceSettingsView() } label: {
                            SettingRow(icon: .phoneCall, title: L("الصوت والمكالمات"), subtitle: L("إعدادات SIP وWebRTC"), trailingChevron: true)
                        }.buttonStyle(.plain)
                    }

                    HStack(spacing: 8) {
                        section(L("إدارة العمل"))
                        Text(L("للمدراء")).font(.wx(10, .bold))
                            .foregroundStyle(Theme.amberText)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Theme.primarySoft, in: Capsule())
                            .padding(.top, 8)
                    }
                    group {
                        NavigationLink { UsersView() } label: {
                            SettingRow(icon: .users, title: L("إدارة المستخدمين"), trailingChevron: true)
                        }.buttonStyle(.plain)
                        NavigationLink { RolesView() } label: {
                            SettingRow(icon: .shield, title: L("الأدوار والصلاحيات"), trailingChevron: true)
                        }.buttonStyle(.plain)
                        NavigationLink { WhatsAppAccountsView() } label: {
                            SettingRow(icon: .whatsapp, title: L("حسابات واتساب"), trailingChevron: true)
                        }.buttonStyle(.plain)
                        NavigationLink { TemplatesView() } label: {
                            SettingRow(icon: .template, title: L("القوالب والردود"), trailingChevron: true)
                        }.buttonStyle(.plain)
                        NavigationLink { IntegrationsView() } label: {
                            SettingRow(icon: .hub, title: L("التكاملات"),
                                       subtitle: integrationsSummary, trailingChevron: true)
                        }.buttonStyle(.plain)
                    }

                    logoutButton.padding(.horizontal, 14).padding(.top, 16)
                    Text("v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1") + " · " + L("أسوار المدن"))
                        .font(.wx(11)).foregroundStyle(Theme.onFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                }
                .padding(.bottom, 24)
            }
            .task {
                let count = (try? await Api.shared.integrations())?.items.count
                if let count, count > 0 {
                    integrationsSummary = "\(count) " + L("أنظمة مرتبطة")
                }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $editOpen) { EditProfileSheet() }
        .sheet(isPresented: $passwordOpen) { ChangePasswordSheet() }
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        if let user = try? await Api.shared.uploadAvatar(imageData: data) {
            session.user = user
        }
        photoItem = nil
    }

    private var profileCard: some View {
        HStack(spacing: 14) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Avatar(name: session.user?.title ?? "?", imageURL: avatarURL, size: 62)
                    .overlay { if uploading { Circle().fill(.black.opacity(0.3)); ProgressView().tint(.white) } }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(session.user?.title ?? "—").font(.wx(17, .bold)).foregroundStyle(Theme.onSurface)
                if let email = session.user?.email, !email.isEmpty {
                    Text(email).font(.wx(12)).foregroundStyle(Theme.onMuted).monospaced()
                }
                if let role = session.user?.role, !role.isEmpty {
                    Text(role).font(.wx(12, .semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
            Spacer()
            Button { editOpen = true } label: { Image(icon: .edit).foregroundStyle(Theme.primary) }
        }
        .padding(16)
        .glassCard(22)
    }

    private var logoutButton: some View {
        Button {
            loggingOut = true
            Task { await session.logout(); loggingOut = false }
        } label: {
            HStack(spacing: 8) {
                if loggingOut { ProgressView().tint(Theme.danger) }
                else {
                    Image(icon: .logout).font(.wx(18))
                    Text(L("تسجيل الخروج")).font(.wx(17, .semibold))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(Theme.danger)
        }
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(.vertical, 4)
            .glassCard(22)
            .padding(.horizontal, 14)
    }

    private var avatarURL: URL? {
        guard let user = session.user, let avatar = user.avatar, !avatar.isEmpty else { return nil }
        return Api.avatarURL(userId: user.id, avatar: avatar)
    }
}

struct SettingRow: View {
    let icon: WIcon
    let title: String
    var subtitle: String? = nil
    var trailingChevron: Bool = false
    /// Kept for call-site compatibility; design 4f made every tile
    /// monochrome (one 32px `#F2EEE9` tile, one line-icon color), so the
    /// tint no longer paints anything.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(icon: icon).font(.wx(15, .medium))
                .foregroundStyle(Color(light: 0x6B6156, dark: 0xADA69F))
                .frame(width: 32, height: 32)
                .background(Color(light: 0xF2EEE9, dark: 0x37332F),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                if let subtitle { Text(subtitle).font(.wx(12)).foregroundStyle(Theme.onMuted) }
            }
            Spacer()
            if trailingChevron { Image(icon: .chevLeft).foregroundStyle(Theme.onFaint) }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

struct EditProfileSheet: View {
    @EnvironmentObject var session: Session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(L("الاسم"), text: $name)
                TextField(L("البريد الإلكتروني"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle(L("تعديل الملف"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("إلغاء")) { dismiss() }
                }
            }
        }
        .onAppear {
            name = session.user?.displayName ?? ""
            email = session.user?.email ?? ""
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true
        if let user = try? await Api.shared.updateProfile(displayName: name, email: email) {
            session.user = user
        }
        saving = false
        dismiss()
    }
}

struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var newPass = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var error: String?
    @State private var done = false

    private var valid: Bool { !current.isEmpty && newPass.count >= 6 && newPass == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(L("كلمة المرور الحالية"), text: $current)
                    SecureField(L("كلمة المرور الجديدة"), text: $newPass)
                    SecureField(L("تأكيد كلمة المرور الجديدة"), text: $confirm)
                } footer: {
                    Text(L("٦ أحرف على الأقل، ويجب أن يتطابق الحقلان."))
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
                if done { Text(L("تم تغيير كلمة المرور بنجاح")).foregroundStyle(Theme.success) }
            }
            .navigationTitle(L("تغيير كلمة المرور"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }.disabled(saving || !valid)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true; error = nil
        do {
            try await Api.shared.changePassword(currentPassword: current, newPassword: newPass)
            done = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            self.error = error.apiMessage
        }
        saving = false
    }
}

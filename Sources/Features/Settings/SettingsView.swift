import SwiftUI
import PhotosUI

struct SettingsView: View {
    @EnvironmentObject var session: Session
    @State private var loggingOut = false
    @State private var editOpen = false
    @State private var passwordOpen = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @AppStorage(Notifier.messagesEnabledKey) private var notifyMessages = true

    var body: some View {
        NavigationStack {
        VStack(spacing: 0) {
            HStack {
                Text("الإعدادات").font(.title2.bold()).foregroundStyle(Theme.onSurface)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    profileCard.padding(.horizontal, 14).padding(.vertical, 6)

                    section("الأدوات")
                    group {
                        NavigationLink { CallsView() } label: {
                            SettingRow(icon: .call, title: "سجل المكالمات", subtitle: "الواردة والصادرة والتسجيلات", trailingChevron: true, tint: Theme.success)
                        }.buttonStyle(.plain)
                        NavigationLink { StatsView() } label: {
                            SettingRow(icon: .chart, title: "الإحصاءات", subtitle: "المؤشرات وتقارير العملاء", trailingChevron: true, tint: Theme.info)
                        }.buttonStyle(.plain)
                    }

                    section("المظهر")
                    group {
                        SettingRow(icon: .palette, title: "السمة", subtitle: "حسب النظام", tint: Color(rgb: 0xCE6A47))
                        SettingRow(icon: .lang, title: "اللغة", subtitle: "العربية", trailingChevron: true, tint: Theme.info)
                    }

                    section("الإشعارات")
                    group {
                        HStack {
                            SettingRow(icon: .bell, title: "تنبيهات الرسائل الجديدة",
                                       subtitle: "أثناء تشغيل التطبيق (صوت + لافتة)", tint: Theme.warning)
                            Toggle("", isOn: $notifyMessages)
                                .labelsHidden()
                                .tint(Theme.primary)
                                .padding(.trailing, 14)
                        }
                    }

                    section("الإدارة")
                    group {
                        NavigationLink { UsersView() } label: {
                            SettingRow(icon: .users, title: "إدارة المستخدمين", trailingChevron: true, tint: Theme.info)
                        }.buttonStyle(.plain)
                        NavigationLink { RolesView() } label: {
                            SettingRow(icon: .shield, title: "الأدوار والصلاحيات", trailingChevron: true, tint: Color(rgb: 0x7C6BD0))
                        }.buttonStyle(.plain)
                        NavigationLink { WhatsAppAccountsView() } label: {
                            SettingRow(icon: .whatsapp, title: "حسابات واتساب", trailingChevron: true, tint: Color(rgb: 0x23A55A))
                        }.buttonStyle(.plain)
                        NavigationLink { TemplatesView() } label: {
                            SettingRow(icon: .template, title: "القوالب والردود", trailingChevron: true, tint: Theme.primary)
                        }.buttonStyle(.plain)
                    }

                    section("الأمان")
                    group {
                        Button { passwordOpen = true } label: {
                            SettingRow(icon: .lock, title: "تغيير كلمة المرور", trailingChevron: true, tint: Theme.danger)
                        }.buttonStyle(.plain)
                    }

                    section("عام")
                    group {
                        NavigationLink { VoiceSettingsView() } label: {
                            SettingRow(icon: .phoneCall, title: "الصوت والمكالمات", subtitle: "إعدادات SIP وWebRTC", trailingChevron: true, tint: Theme.success)
                        }.buttonStyle(.plain)
                        SettingRow(icon: .info, title: "الإصدار", subtitle: "v1.6.2 · أسوار المدن")
                    }

                    logoutButton.padding(.horizontal, 14).padding(.top, 16)
                }
                .padding(.bottom, 24)
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
                Text(session.user?.title ?? "—").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.onSurface)
                if let email = session.user?.email, !email.isEmpty {
                    Text(email).font(.caption).foregroundStyle(Theme.onMuted).monospaced()
                }
                if let role = session.user?.role, !role.isEmpty {
                    Text(role).font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
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
                    Image(icon: .logout).font(.system(size: 18))
                    Text("تسجيل الخروج").font(.headline)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 16))
            .foregroundStyle(Theme.danger)
        }
    }

    private func section(_ text: String) -> some View {
        Text(text).font(.callout.bold()).foregroundStyle(Theme.onMuted)
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
    /// iOS-Settings-style colored icon tile; nil keeps the neutral surface tile.
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(icon: icon).font(.system(size: 17, weight: .medium))
                .foregroundStyle(tint == nil ? Theme.onSurface : .white)
                .frame(width: 38, height: 38)
                .background(tint ?? Theme.surface2, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.onMuted) }
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
                TextField("الاسم", text: $name)
                TextField("البريد الإلكتروني", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .navigationTitle("تعديل الملف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
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
                    SecureField("كلمة المرور الحالية", text: $current)
                    SecureField("كلمة المرور الجديدة", text: $newPass)
                    SecureField("تأكيد كلمة المرور الجديدة", text: $confirm)
                } footer: {
                    Text("٦ أحرف على الأقل، ويجب أن يتطابق الحقلان.")
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
                if done { Text("تم تغيير كلمة المرور بنجاح").foregroundStyle(Theme.success) }
            }
            .navigationTitle("تغيير كلمة المرور")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(saving || !valid)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
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
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

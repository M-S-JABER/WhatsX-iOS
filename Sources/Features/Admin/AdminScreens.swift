import SwiftUI

// MARK: - Users

struct UsersView: View {
    @State private var users: [AuthUser] = []
    @State private var roles: [Role] = []
    @State private var loading = true
    @State private var createOpen = false
    @State private var editingUser: AuthUser?

    var body: some View {
        Group {
            if loading {
                ZStack { Theme.background.ignoresSafeArea(); ProgressView().tint(Theme.primary) }
            } else if users.isEmpty {
                ZStack { Theme.background.ignoresSafeArea(); Text("لا مستخدمون").foregroundStyle(Theme.onMuted) }
            } else {
                List {
                    ForEach(users) { u in
                        HStack(spacing: 12) {
                            Avatar(name: u.title, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                Text(u.role ?? "—").font(.caption).foregroundStyle(Theme.onMuted)
                            }
                            Spacer()
                        }
                        .listRowBackground(Theme.background)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(u) } } label: { Label("حذف", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { editingUser = u } label: { Label("تعديل", systemImage: "pencil") }.tint(Theme.info)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("المستخدمون")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { createOpen = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $createOpen) { CreateUserSheet(roles: roles) { await load() } }
        .sheet(item: $editingUser) { u in EditUserSheet(user: u, roles: roles) { await load() } }
        .task { await load() }
    }

    private func load() async {
        do { users = try await Api.shared.users().items } catch {}
        roles = (try? await Api.shared.roles())?.items ?? []
        loading = false
    }
    private func delete(_ u: AuthUser) async { try? await Api.shared.deleteUser(u.id); await load() }
}

struct CreateUserSheet: View {
    let roles: [Role]
    let onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var role = ""       // role id (backend may expect name — adjust if create fails)
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("اسم المستخدم", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("كلمة المرور", text: $password)
                Picker("الدور", selection: $role) {
                    Text("اختر دورًا").tag("")
                    ForEach(roles) { r in Text(r.name).tag(r.id) }
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("مستخدم جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") { Task { await create() } }
                        .disabled(saving || username.isEmpty || password.isEmpty || role.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        saving = true; error = nil
        do {
            _ = try await Api.shared.createUser(username: username, password: password, role: role)
            await onCreated()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

struct EditUserSheet: View {
    let user: AuthUser
    let roles: [Role]
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var role = ""
    @State private var password = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Text(user.title).font(.headline).foregroundStyle(Theme.onSurface)
                Picker("الدور", selection: $role) {
                    ForEach(roles) { r in Text(r.name).tag(r.id) }
                }
                SecureField("كلمة مرور جديدة (اختياري)", text: $password)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("تعديل المستخدم")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
            .onAppear {
                role = roles.first { $0.id == user.role || $0.name == user.role }?.id ?? roles.first?.id ?? ""
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true; error = nil
        do {
            _ = try await Api.shared.updateUser(user.id, role: role, password: password)
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Roles

struct RolesView: View {
    @State private var roles: [Role] = []
    @State private var loading = true
    @State private var createOpen = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if roles.isEmpty {
                Text("لا أدوار").foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(roles) { role in
                        HStack(spacing: 12) {
                            Image(icon: .shield).foregroundStyle(Theme.onSurface)
                                .frame(width: 40, height: 40)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(role.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                Text("\(role.permissions.count) صلاحية").font(.caption).foregroundStyle(Theme.onMuted)
                            }
                            Spacer()
                            if role.isSystem {
                                Text("نظام").font(.caption2.weight(.semibold)).foregroundStyle(Theme.onMuted)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Theme.surface2, in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.background)
                        .swipeActions(edge: .trailing) {
                            if !role.isSystem {
                                Button(role: .destructive) { Task { await delete(role) } } label: { Label("حذف", systemImage: "trash") }
                            }
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("الأدوار والصلاحيات")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { createOpen = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $createOpen) { CreateRoleSheet { await load() } }
        .task { await load() }
    }

    private func load() async {
        do { roles = try await Api.shared.roles().items } catch {}
        loading = false
    }

    private func delete(_ role: Role) async {
        try? await Api.shared.deleteRole(role.id)
        await load()
    }
}

struct CreateRoleSheet: View {
    let onCreated: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var desc = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("اسم الدور", text: $name)
                TextField("الوصف (اختياري)", text: $desc)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("دور جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") { Task { await create() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func create() async {
        saving = true; error = nil
        do {
            _ = try await Api.shared.createRole(name: name, description: desc.isEmpty ? nil : desc)
            await onCreated()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Templates

struct TemplatesView: View {
    @State private var templates: [Template] = []
    @State private var ready: [ReadyMessage] = []
    @State private var loading = true
    @State private var editorOpen = false
    @State private var editing: ReadyMessage?

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if !ready.isEmpty {
                        Text("الردود الجاهزة").font(.callout.bold()).foregroundStyle(Theme.onMuted)
                        ForEach(ready) { r in readyCard(r) }
                    }
                    if !templates.isEmpty {
                        Text("قوالب Meta").font(.callout.bold()).foregroundStyle(Theme.onMuted)
                        ForEach(templates, id: \.stableId) { t in
                            card(title: t.name, body: t.bodyText ?? "", tag: t.status ?? t.language ?? "")
                        }
                    }
                    if ready.isEmpty && templates.isEmpty {
                        Text("لا قوالب").foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("القوالب والردود")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = nil; editorOpen = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $editorOpen) { ReadyMessageSheet(message: editing) { await load() } }
        .task { await load() }
    }

    private func load() async {
        async let r = Api.shared.readyMessages()
        async let t = Api.shared.templates()
        ready = (try? await r)?.items ?? []
        templates = (try? await t)?.items ?? []
        loading = false
    }

    private func delete(_ r: ReadyMessage) async {
        try? await Api.shared.deleteReadyMessage(r.id)
        await load()
    }

    private func readyCard(_ r: ReadyMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                let tag = r.isActive ? "مُفعّل" : "متوقّف"
                Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.primaryContainer, in: Capsule())
            }
            if !r.body.isEmpty { Text(r.body).font(.footnote).foregroundStyle(Theme.onMuted).lineLimit(3) }
            HStack(spacing: 8) {
                Spacer()
                Button { editing = r; editorOpen = true } label: {
                    Image(icon: .edit).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 9))
                }
                Button { Task { await delete(r) } } label: {
                    Image(icon: .trash).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                        .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.outline, lineWidth: 1))
    }

    private func card(title: String, body: String, tag: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                if !tag.isEmpty {
                    Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
            if !body.isEmpty { Text(body).font(.footnote).foregroundStyle(Theme.onMuted).lineLimit(3) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.outline, lineWidth: 1))
    }
}

struct ReadyMessageSheet: View {
    let message: ReadyMessage?
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var text = ""
    @State private var isActive = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("الاسم", text: $name)
                TextField("النص", text: $text, axis: .vertical).lineLimit(3...8)
                Toggle("مُفعّل", isOn: $isActive)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(message == nil ? "رد جاهز جديد" : "تعديل الرد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }
                        .disabled(saving || name.isEmpty || text.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
            .onAppear {
                if let message {
                    name = message.name
                    text = message.body
                    isActive = message.isActive
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        saving = true; error = nil
        do {
            if let message {
                try await Api.shared.updateReadyMessage(message.id, name: name, body: text, isActive: isActive)
            } else {
                try await Api.shared.createReadyMessage(name: name, body: text, isActive: isActive)
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

// MARK: - WhatsApp accounts (health)

struct WhatsAppAccountsView: View {
    @State private var accounts: [WhatsAppAccount] = []
    @State private var loading = true
    @State private var createOpen = false
    @State private var editing: WhatsAppAccount?

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if accounts.isEmpty {
                Text("لا حسابات").foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(accounts) { a in
                        Button { editing = a } label: { row(a) }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.background)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(a) } } label: { Label("حذف", systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("حسابات واتساب")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { createOpen = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $createOpen) { CreateWhatsappAccountSheet { await load() } }
        .sheet(item: $editing) { acct in EditWhatsappAccountSheet(account: acct) { await load() } }
        .task { await load() }
    }

    private func row(_ a: WhatsAppAccount) -> some View {
        HStack(spacing: 12) {
            Image(icon: .whatsapp).foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(AccountColor.color(a.id), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(a.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                    if a.isDefault {
                        Text("افتراضي").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.primaryContainer, in: Capsule())
                    }
                }
                if let phone = a.phoneNumber { Text(phone).font(.caption).foregroundStyle(Theme.onMuted) }
            }
            Spacer()
            statusChip(a)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        do { accounts = try await Api.shared.whatsappAccounts().items } catch {}
        loading = false
    }

    private func delete(_ a: WhatsAppAccount) async {
        try? await Api.shared.deleteWhatsappAccount(a.id)
        await load()
    }

    private func statusChip(_ a: WhatsAppAccount) -> some View {
        let ok = a.health == "healthy" || (a.health == nil && a.isActive)
        let (label, color) = ok ? ("متصل", Theme.success) : ("متوقف", Theme.warning)
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }
}

struct CreateWhatsappAccountSheet: View {
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phoneNumberId = ""
    @State private var accessToken = ""
    @State private var displayPhoneNumber = ""
    @State private var wabaId = ""
    @State private var isActive = true
    @State private var isDefault = false
    @State private var saving = false
    @State private var error: String?

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !phoneNumberId.trimmingCharacters(in: .whitespaces).isEmpty
            && (!isActive || !accessToken.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("الأساسيات") {
                    TextField("اسم الحساب", text: $name)
                    TextField("Phone Number ID", text: $phoneNumberId).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField("رقم الهاتف الظاهر (اختياري)", text: $displayPhoneNumber)
                    TextField("WABA ID (اختياري)", text: $wabaId).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section("الاعتماد") {
                    SecureField("Access Token", text: $accessToken)
                }
                Section {
                    Toggle("مفعّل", isOn: $isActive)
                    Toggle("الحساب الافتراضي", isOn: $isDefault)
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("حساب واتساب جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("إنشاء") { Task { await create() } }.disabled(saving || !valid)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func create() async {
        saving = true; error = nil
        do {
            _ = try await Api.shared.createWhatsappAccount(CreateWhatsappAccountRequest(
                name: name, phoneNumberId: phoneNumberId, accessToken: accessToken,
                displayPhoneNumber: displayPhoneNumber.isEmpty ? nil : displayPhoneNumber,
                wabaId: wabaId.isEmpty ? nil : wabaId, isActive: isActive, isDefault: isDefault))
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

struct EditWhatsappAccountSheet: View {
    let account: WhatsAppAccount
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var displayPhoneNumber = ""
    @State private var wabaId = ""
    @State private var accessToken = ""
    @State private var isActive = true
    @State private var isDefault = false
    @State private var saving = false
    @State private var error: String?
    // Registration
    @State private var pin = ""
    @State private var regInfo: String?
    @State private var regBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("الأساسيات") {
                    TextField("اسم الحساب", text: $name)
                    TextField("رقم الهاتف الظاهر", text: $displayPhoneNumber)
                    TextField("WABA ID", text: $wabaId).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section {
                    SecureField("Access Token (اتركه فارغًا للإبقاء)", text: $accessToken)
                } header: { Text("الاعتماد") } footer: { Text("Phone Number ID: \(account.phoneNumberId ?? "—")") }
                Section {
                    Toggle("مفعّل", isOn: $isActive)
                    Toggle("الحساب الافتراضي", isOn: $isDefault)
                }
                Section {
                    HStack {
                        Button("طلب رمز SMS") { Task { await requestCode("SMS") } }.buttonStyle(.bordered).disabled(regBusy)
                        Spacer()
                        Button("مكالمة صوتية") { Task { await requestCode("VOICE") } }.buttonStyle(.bordered).disabled(regBusy)
                    }
                    TextField("رمز التحقق (٦ أرقام)", text: $pin).keyboardType(.numberPad)
                    Button("تسجيل الرقم") { Task { await register() } }
                        .disabled(regBusy || pin.count != 6)
                    if let regInfo { Text(regInfo).font(.caption).foregroundStyle(Theme.success) }
                } header: { Text("تسجيل الرقم لدى Meta") }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("تعديل الحساب")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
            .onAppear {
                name = account.displayName
                displayPhoneNumber = account.phoneNumber ?? ""
                wabaId = account.wabaId ?? ""
                isActive = account.isActive
                isDefault = account.isDefault
            }
        }
        .presentationDetents([.large])
    }

    private func save() async {
        saving = true; error = nil
        do {
            _ = try await Api.shared.updateWhatsappAccount(account.id, UpdateWhatsappAccountRequest(
                name: name, displayPhoneNumber: displayPhoneNumber, wabaId: wabaId,
                accessToken: accessToken.isEmpty ? nil : accessToken,
                isActive: isActive, isDefault: isDefault))
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }

    private func requestCode(_ method: String) async {
        regBusy = true; error = nil; regInfo = nil
        do {
            try await Api.shared.requestWhatsappCode(account.id, method: method)
            regInfo = "أُرسل الرمز عبر \(method == "VOICE" ? "مكالمة" : "SMS")."
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        regBusy = false
    }

    private func register() async {
        regBusy = true; error = nil; regInfo = nil
        do {
            try await Api.shared.registerWhatsappNumber(account.id, pin: pin)
            regInfo = "تم تسجيل الرقم بنجاح."
            await onSaved()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        regBusy = false
    }
}

// MARK: - Voice / SIP settings (read-only)

struct VoiceSettingsView: View {
    @State private var s: VoiceSettings?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            } else if let s {
                VStack(spacing: 0) {
                    infoRow("مُفعّل", s.enabled ? "نعم" : "لا")
                    infoRow("SIP", s.sipEnabled ? "مُفعّل" : "متوقف")
                    infoRow("Cloudflare", s.cloudflareHostname)
                    infoRow("WebRTC WSS", s.asteriskWebrtcWssUrl)
                    infoRow("UCM IP", s.ucmPublicIp)
                    infoRow("التحويلة الافتراضية", s.ucmDefaultExtension)
                    infoRow("SIP Domain", s.whatsappSipDomain)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.outline, lineWidth: 1))
                .padding(16)
            } else {
                Text("تعذّر تحميل الإعدادات").foregroundStyle(Theme.onMuted).padding(.top, 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("الصوت والمكالمات")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            s = (try? await Api.shared.voiceSettings())?.settings
            loading = false
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.onSurface)
            Spacer()
            Text(value.isEmpty ? "—" : value).font(.caption).foregroundStyle(Theme.onMuted)
                .monospaced().lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }
}

// Shared plain-list container with loading/empty states.
@ViewBuilder
func listContainer<Content: View>(loading: Bool, empty: Bool, emptyText: String, @ViewBuilder content: () -> Content) -> some View {
    ZStack {
        Theme.background.ignoresSafeArea()
        if loading {
            ProgressView().tint(Theme.primary)
        } else if empty {
            Text(emptyText).foregroundStyle(Theme.onMuted)
        } else {
            ScrollView { LazyVStack(spacing: 0) { content() } }
        }
    }
}

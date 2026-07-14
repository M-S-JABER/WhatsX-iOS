import SwiftUI

// MARK: - WhatsApp accounts (health)

struct WhatsAppAccountsView: View {
    @State private var accounts: [WhatsAppAccount] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var createOpen = false
    @State private var editing: WhatsAppAccount?

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, accounts.isEmpty {
                LoadFailedView(message: err) { Task { loading = true; await load() } }
            } else if accounts.isEmpty {
                Text(L("لا حسابات")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(accounts) { a in
                        Button { editing = a } label: { row(a) }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.background)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(a) } } label: { Label(L("حذف"), systemImage: "trash") }
                            }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("حسابات واتساب"))
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
                    Text(a.displayName).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                    if a.isDefault {
                        Text(L("افتراضي")).font(.wx(9, .bold)).foregroundStyle(Theme.primary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Theme.primaryContainer, in: Capsule())
                    }
                }
                if let phone = a.phoneNumber { Text(phone).font(.wx(12)).foregroundStyle(Theme.onMuted) }
            }
            Spacer()
            statusChip(a)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        do { accounts = try await Api.shared.whatsappAccounts().items; loadError = nil }
        catch { loadError = error.apiMessage }
        loading = false
    }

    private func delete(_ a: WhatsAppAccount) async {
        try? await Api.shared.deleteWhatsappAccount(a.id)
        await load()
    }

    private func statusChip(_ a: WhatsAppAccount) -> some View {
        let ok = a.health == "healthy" || (a.health == nil && a.isActive)
        let (label, color) = ok ? (L("متصل"), Theme.success) : (L("متوقف"), Theme.warning)
        return StatusCapsule(text: label, color: color, showDot: true)
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
                Section(L("الأساسيات")) {
                    TextField(L("اسم الحساب"), text: $name)
                    TextField("Phone Number ID", text: $phoneNumberId).autocorrectionDisabled().textInputAutocapitalization(.never)
                    TextField(L("رقم الهاتف الظاهر (اختياري)"), text: $displayPhoneNumber)
                    TextField(L("WABA ID (اختياري)"), text: $wabaId).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section(L("الاعتماد")) {
                    SecureField("Access Token", text: $accessToken)
                }
                Section {
                    Toggle(L("مفعّل"), isOn: $isActive)
                    Toggle(L("الحساب الافتراضي"), isOn: $isDefault)
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("حساب واتساب جديد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("إنشاء")) { Task { await create() } }.disabled(saving || !valid)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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
            self.error = error.apiMessage
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
    @State private var webhookBehavior = "auto"
    @State private var saving = false
    @State private var error: String?
    // Registration
    @State private var pin = ""
    @State private var regInfo: String?
    @State private var regBusy = false

    var body: some View {
        NavigationStack {
            Form {
                Section(L("الأساسيات")) {
                    TextField(L("اسم الحساب"), text: $name)
                    TextField(L("رقم الهاتف الظاهر"), text: $displayPhoneNumber)
                    TextField("WABA ID", text: $wabaId).autocorrectionDisabled().textInputAutocapitalization(.never)
                }
                Section {
                    SecureField(L("Access Token (اتركه فارغًا للإبقاء)"), text: $accessToken)
                } header: { Text(L("الاعتماد")) } footer: { Text("Phone Number ID: \(account.phoneNumberId ?? "—")") }
                Section {
                    Toggle(L("مفعّل"), isOn: $isActive)
                    Toggle(L("الحساب الافتراضي"), isOn: $isDefault)
                }
                Section {
                    Picker(L("سلوك طلبات إذن الاتصال"), selection: $webhookBehavior) {
                        Text(L("تلقائي")).tag("auto")
                        Text(L("قبول تلقائي")).tag("accept")
                        Text(L("رفض تلقائي")).tag("reject")
                    }
                }
                Section {
                    HStack {
                        Button(L("طلب رمز SMS")) { Task { await requestCode("SMS") } }.buttonStyle(.bordered).disabled(regBusy)
                        Spacer()
                        Button(L("مكالمة صوتية")) { Task { await requestCode("VOICE") } }.buttonStyle(.bordered).disabled(regBusy)
                    }
                    TextField(L("رمز التحقق (٦ أرقام)"), text: $pin).keyboardType(.numberPad)
                    Button(L("تسجيل الرقم")) { Task { await register() } }
                        .disabled(regBusy || pin.count != 6)
                    if let regInfo { Text(regInfo).font(.wx(12)).foregroundStyle(Theme.success) }
                } header: { Text(L("تسجيل الرقم لدى Meta")) }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("تعديل الحساب"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } }
            }
            .onAppear {
                name = account.displayName
                displayPhoneNumber = account.phoneNumber ?? ""
                wabaId = account.wabaId ?? ""
                isActive = account.isActive
                isDefault = account.isDefault
                webhookBehavior = account.webhookBehavior ?? "auto"
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
                isActive: isActive, isDefault: isDefault,
                webhookBehavior: webhookBehavior))
            await onSaved()
            dismiss()
        } catch {
            self.error = error.apiMessage
        }
        saving = false
    }

    private func requestCode(_ method: String) async {
        regBusy = true; error = nil; regInfo = nil
        do {
            try await Api.shared.requestWhatsappCode(account.id, method: method)
            regInfo = L("أُرسل الرمز عبر") + " " + (method == "VOICE" ? L("مكالمة") : "SMS") + "."
        } catch {
            self.error = error.apiMessage
        }
        regBusy = false
    }

    private func register() async {
        regBusy = true; error = nil; regInfo = nil
        do {
            try await Api.shared.registerWhatsappNumber(account.id, pin: pin)
            regInfo = L("تم تسجيل الرقم بنجاح.")
            await onSaved()
        } catch {
            self.error = error.apiMessage
        }
        regBusy = false
    }
}

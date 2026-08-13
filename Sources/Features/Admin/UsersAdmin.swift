import SwiftUI

// MARK: - Users

struct UsersView: View {
    @State private var users: [AuthUser] = []
    @State private var roles: [Role] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var createOpen = false
    @State private var editingUser: AuthUser?

    var body: some View {
        Group {
            if loading {
                ZStack { Theme.background.ignoresSafeArea(); ProgressView().tint(Theme.primary) }
            } else if let err = loadError, users.isEmpty {
                LoadFailedView(message: err) { Task { loading = true; await load() } }
            } else if users.isEmpty {
                ZStack { Theme.background.ignoresSafeArea(); Text(L("لا مستخدمون")).foregroundStyle(Theme.onMuted) }
            } else {
                List {
                    ForEach(users) { u in
                        NavigationLink {
                            UserPermissionsView(userId: u.id, username: u.title)
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(name: u.title, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(u.title).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                                    Text(u.role ?? "—").font(.wx(12)).foregroundStyle(Theme.onMuted)
                                }
                                Spacer()
                            }
                        }
                        .listRowBackground(Theme.background)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await delete(u) } } label: { Label(L("حذف"), systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { editingUser = u } label: { Label(L("تعديل"), systemImage: "pencil") }.tint(Theme.info)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("المستخدمون"))
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
        do { users = try await Api.shared.users().items; loadError = nil }
        catch { loadError = error.apiMessage }
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
                TextField(L("اسم المستخدم"), text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField(L("كلمة المرور"), text: $password)
                Picker(L("الدور"), selection: $role) {
                    Text(L("اختر دورًا")).tag("")
                    ForEach(roles) { r in Text(r.name).tag(r.id) }
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("مستخدم جديد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("إنشاء")) { Task { await create() } }
                        .disabled(saving || username.isEmpty || password.isEmpty || role.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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
            self.error = error.apiMessage
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
                Text(user.title).font(.wx(17, .semibold)).foregroundStyle(Theme.onSurface)
                Picker(L("الدور"), selection: $role) {
                    ForEach(roles) { r in Text(r.name).tag(r.id) }
                }
                SecureField(L("كلمة مرور جديدة (اختياري)"), text: $password)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("تعديل المستخدم"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }.disabled(saving)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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
            self.error = error.apiMessage
        }
        saving = false
    }
}

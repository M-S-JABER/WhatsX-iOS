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
                                    Text(u.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                    Text(u.role ?? "—").font(.caption).foregroundStyle(Theme.onMuted)
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
                Text(L("لا أدوار")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(roles) { role in
                        NavigationLink {
                            RolePermissionsView(role: role) { await load() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(icon: .shield).foregroundStyle(Theme.onSurface)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(role.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                    Text("\(role.permissions.count) " + L("صلاحية")).font(.caption).foregroundStyle(Theme.onMuted)
                                }
                                Spacer()
                                if role.isSystem {
                                    Text(L("نظام")).font(.caption2.weight(.semibold)).foregroundStyle(Theme.onMuted)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Theme.surface2, in: Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Theme.background)
                        .swipeActions(edge: .trailing) {
                            if !role.isSystem {
                                Button(role: .destructive) { Task { await delete(role) } } label: { Label(L("حذف"), systemImage: "trash") }
                            }
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("الأدوار والصلاحيات"))
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
                TextField(L("اسم الدور"), text: $name)
                TextField(L("الوصف (اختياري)"), text: $desc)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("دور جديد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("إنشاء")) { Task { await create() } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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

// MARK: - Role permission editor

struct RolePermissionsView: View {
    let role: Role
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: [PermissionCatalogItem] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    private var groups: [(String, [PermissionCatalogItem])] {
        let dict = Dictionary(grouping: catalog) { $0.groupTitle }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if catalog.isEmpty {
                Text(L("لا صلاحيات متاحة")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("\(selected.count) " + L("صلاحية مُفعّلة")).font(.caption).foregroundStyle(Theme.onMuted)
                    }
                    ForEach(groups, id: \.0) { group, items in
                        Section(group) {
                            ForEach(items) { p in
                                Button { toggle(p.id) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(p.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.onSurface)
                                                if p.isCritical == true {
                                                    Text(L("حسّاس")).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.danger)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Theme.dangerBg, in: Capsule())
                                                }
                                            }
                                            if let d = p.description, !d.isEmpty {
                                                Text(d).font(.caption2).foregroundStyle(Theme.onMuted)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: selected.contains(p.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selected.contains(p.id) ? Theme.primary : Theme.onFaint)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(Theme.danger) }
                    }
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(role.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("حفظ")) { Task { await save() } }.disabled(saving || loading)
            }
        }
        .task { await load() }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load() async {
        selected = Set(role.permissions)
        do { catalog = try await Api.shared.permissionsCatalog() } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true; error = nil
        do {
            try await Api.shared.updateRole(role.id, permissions: Array(selected))
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

// MARK: - Per-user permission overrides

struct UserPermissionsView: View {
    let userId: String
    let username: String
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: [PermissionCatalogItem] = []
    @State private var rolePerms: Set<String> = []
    @State private var overrides: [String: Bool] = [:]   // absent = inherit, true = allow, false = deny
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    private var groups: [(String, [PermissionCatalogItem])] {
        let dict = Dictionary(grouping: catalog) { $0.groupTitle }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    private func effective(_ id: String) -> Bool {
        if let o = overrides[id] { return o }
        return rolePerms.contains(id)
    }
    private var effectiveCount: Int { catalog.filter { effective($0.id) }.count }

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if catalog.isEmpty {
                Text(L("لا صلاحيات متاحة")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("\(overrides.count) " + L("تجاوز") + " · \(effectiveCount) " + L("صلاحية فعّالة"))
                            .font(.caption).foregroundStyle(Theme.onMuted)
                    }
                    ForEach(groups, id: \.0) { group, items in
                        Section(group) {
                            ForEach(items) { p in row(p) }
                        }
                    }
                    if let error {
                        Section { Text(error).foregroundStyle(Theme.danger) }
                    }
                }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("حفظ")) { Task { await save() } }.disabled(saving || loading)
            }
        }
        .task { await load() }
    }

    private func row(_ p: PermissionCatalogItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle().fill(effective(p.id) ? Theme.success : Theme.onFaint).frame(width: 7, height: 7)
                Text(p.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.onSurface)
                if p.isCritical == true {
                    Text(L("حسّاس")).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.danger)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Theme.dangerBg, in: Capsule())
                }
                Spacer()
            }
            Picker("", selection: stateBinding(p.id)) {
                Text(L("وراثة")).tag(0)
                Text(L("سماح")).tag(1)
                Text(L("منع")).tag(2)
            }
            .pickerStyle(.segmented)
            Text(rolePerms.contains(p.id) ? L("الدور: يمنحها") : L("الدور: لا يمنحها"))
                .font(.caption2).foregroundStyle(Theme.onFaint)
        }
        .padding(.vertical, 2)
    }

    private func stateBinding(_ id: String) -> Binding<Int> {
        Binding(
            get: { overrides[id] == nil ? 0 : (overrides[id] == true ? 1 : 2) },
            set: { v in
                if v == 0 { overrides.removeValue(forKey: id) }
                else { overrides[id] = (v == 1) }
            }
        )
    }

    private func load() async {
        do {
            async let cat = Api.shared.permissionsCatalog()
            let perms = try await Api.shared.userPermissions(userId)
            catalog = (try? await cat) ?? []
            rolePerms = Set(perms.rolePermissions)
            var map: [String: Bool] = [:]
            for o in perms.overrides { map[o.permissionId] = o.allowed }
            overrides = map
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true; error = nil
        let arr = overrides.map { UserPermissionOverride(permissionId: $0.key, allowed: $0.value) }
        do {
            try await Api.shared.updateUserPermissions(userId, overrides: arr)
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
    @State private var accounts: [Instance] = []
    @State private var loading = true
    @State private var editorOpen = false
    @State private var createTemplateOpen = false
    @State private var editing: ReadyMessage?
    @State private var syncing = false
    @State private var banner: String?

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner {
                        Text(banner).font(.caption).foregroundStyle(Theme.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !ready.isEmpty {
                        Text(L("الردود الجاهزة")).font(.callout.bold()).foregroundStyle(Theme.onMuted)
                        ForEach(ready) { r in readyCard(r) }
                    }
                    if !templates.isEmpty {
                        Text(L("قوالب Meta")).font(.callout.bold()).foregroundStyle(Theme.onMuted)
                        ForEach(templates, id: \.stableId) { t in templateCard(t) }
                    }
                    if ready.isEmpty && templates.isEmpty {
                        Text(L("لا قوالب")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("القوالب والردود"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = nil; editorOpen = true } label: { Label(L("رد جاهز جديد"), systemImage: "text.bubble") }
                    Button { createTemplateOpen = true } label: { Label(L("قالب Meta جديد"), systemImage: "doc.badge.plus") }
                    Button { Task { await sync() } } label: { Label(L("مزامنة من Meta"), systemImage: "arrow.clockwise") }
                } label: {
                    if syncing { ProgressView() } else { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $editorOpen) { ReadyMessageSheet(message: editing) { await load() } }
        .sheet(isPresented: $createTemplateOpen) { CreateTemplateSheet(accounts: accounts) { await load() } }
        .task { await load() }
    }

    private func load() async {
        async let r = Api.shared.readyMessages()
        async let t = Api.shared.templates()
        async let a = Api.shared.instances()
        ready = (try? await r)?.items ?? []
        templates = (try? await t)?.items ?? []
        accounts = (try? await a)?.items ?? []
        loading = false
    }

    private func sync() async {
        syncing = true; banner = nil
        do {
            let r = try await Api.shared.syncTemplates()
            banner = L("تمت المزامنة:") + " \(r.syncedCount) " + L("قالب من Meta.")
            await load()
        } catch {
            banner = (error as? ApiError)?.message ?? error.localizedDescription
        }
        syncing = false
    }

    private func delete(_ r: ReadyMessage) async {
        try? await Api.shared.deleteReadyMessage(r.id)
        await load()
    }

    private func deleteTemplate(_ t: Template) async {
        try? await Api.shared.deleteTemplate(t.stableId)
        await load()
    }

    private func templateCard(_ t: Template) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(t.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                let tag = t.status ?? t.language ?? ""
                if !tag.isEmpty {
                    Text(tag).font(.caption2.weight(.semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
            if let body = t.bodyText, !body.isEmpty {
                Text(body).font(.footnote).foregroundStyle(Theme.onMuted).lineLimit(3)
            }
            HStack {
                Spacer()
                Button { Task { await deleteTemplate(t) } } label: {
                    Image(icon: .trash).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                        .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }

    private func readyCard(_ r: ReadyMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                let tag = r.isActive ? L("مُفعّل") : L("متوقّف")
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
        .glassCard(18)
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
        .glassCard(18)
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
                TextField(L("الاسم"), text: $name)
                TextField(L("النص"), text: $text, axis: .vertical).lineLimit(3...8)
                Toggle(L("مُفعّل"), isOn: $isActive)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(message == nil ? L("رد جاهز جديد") : L("تعديل الرد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }
                        .disabled(saving || name.isEmpty || text.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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

struct CreateTemplateSheet: View {
    let accounts: [Instance]
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var language = "ar"
    @State private var category = "MARKETING"
    @State private var bodyText = ""
    @State private var submitToMeta = false
    @State private var instanceId = ""
    @State private var saving = false
    @State private var error: String?

    private let categories = ["MARKETING", "UTILITY", "AUTHENTICATION"]
    private let languages = ["ar", "en_US", "en"]

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !bodyText.trimmingCharacters(in: .whitespaces).isEmpty
            && (!submitToMeta || !instanceId.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("القالب")) {
                    TextField(L("الاسم (أحرف صغيرة و_)"), text: $name)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                    Picker(L("اللغة"), selection: $language) { ForEach(languages, id: \.self) { Text($0).tag($0) } }
                    Picker(L("الفئة"), selection: $category) { ForEach(categories, id: \.self) { Text($0).tag($0) } }
                }
                Section(L("نص الرسالة (BODY)")) {
                    TextField(L("النص"), text: $bodyText, axis: .vertical).lineLimit(3...8)
                }
                Section {
                    Toggle(L("إرسال إلى Meta للاعتماد"), isOn: $submitToMeta)
                    if submitToMeta {
                        Picker(L("الحساب"), selection: $instanceId) {
                            Text(L("اختر حسابًا")).tag("")
                            ForEach(accounts) { a in Text(a.label).tag(a.id) }
                        }
                    }
                } footer: {
                    Text(submitToMeta ? L("سيُرسَل للاعتماد لدى Meta (PENDING).") : L("سيُحفَظ محليًا (LOCAL) دون إرسال إلى Meta."))
                }
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(L("قالب Meta جديد"))
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
        let req = CreateTemplateRequest(
            name: name, language: language, category: category,
            components: [TemplateComponent(type: "BODY", text: bodyText)],
            submitToMeta: submitToMeta, instanceId: submitToMeta ? instanceId : nil)
        do {
            try await Api.shared.createTemplate(req)
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
                    Text(a.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onSurface)
                    if a.isDefault {
                        Text(L("افتراضي")).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.primary)
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
        let (label, color) = ok ? (L("متصل"), Theme.success) : (L("متوقف"), Theme.warning)
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
                    HStack {
                        Button(L("طلب رمز SMS")) { Task { await requestCode("SMS") } }.buttonStyle(.bordered).disabled(regBusy)
                        Spacer()
                        Button(L("مكالمة صوتية")) { Task { await requestCode("VOICE") } }.buttonStyle(.bordered).disabled(regBusy)
                    }
                    TextField(L("رمز التحقق (٦ أرقام)"), text: $pin).keyboardType(.numberPad)
                    Button(L("تسجيل الرقم")) { Task { await register() } }
                        .disabled(regBusy || pin.count != 6)
                    if let regInfo { Text(regInfo).font(.caption).foregroundStyle(Theme.success) }
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
            regInfo = L("أُرسل الرمز عبر") + " " + (method == "VOICE" ? L("مكالمة") : "SMS") + "."
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
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
                    infoRow(L("مُفعّل"), s.enabled ? L("نعم") : L("لا"))
                    infoRow("SIP", s.sipEnabled ? L("مُفعّل") : L("متوقف"))
                    infoRow("Cloudflare", s.cloudflareHostname)
                    infoRow("WebRTC WSS", s.asteriskWebrtcWssUrl)
                    infoRow("UCM IP", s.ucmPublicIp)
                    infoRow(L("التحويلة الافتراضية"), s.ucmDefaultExtension)
                    infoRow("SIP Domain", s.whatsappSipDomain)
                }
                .glassCard(22)
                .padding(16)
            } else {
                Text(L("تعذّر تحميل الإعدادات")).foregroundStyle(Theme.onMuted).padding(.top, 40)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("الصوت والمكالمات"))
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

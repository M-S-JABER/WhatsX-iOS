import SwiftUI

// MARK: - Roles

struct RolesView: View {
    @State private var roles: [Role] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var createOpen = false

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = loadError, roles.isEmpty {
                LoadFailedView(message: err) { Task { loading = true; await load() } }
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
                                    Text(role.name).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                                    Text("\(role.permissions.count) " + L("صلاحية")).font(.wx(12)).foregroundStyle(Theme.onMuted)
                                }
                                Spacer()
                                if role.isSystem {
                                    Text(L("نظام")).font(.wx(11, .semibold)).foregroundStyle(Theme.onMuted)
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
        do { roles = try await Api.shared.roles().items; loadError = nil }
        catch { loadError = error.apiMessage }
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
            self.error = error.apiMessage
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
                        Text("\(selected.count) " + L("صلاحية مُفعّلة")).font(.wx(12)).foregroundStyle(Theme.onMuted)
                    }
                    ForEach(groups, id: \.0) { group, items in
                        Section(group) {
                            ForEach(items) { p in
                                Button { toggle(p.id) } label: {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: 6) {
                                                Text(p.title).font(.wx(14, .medium)).foregroundStyle(Theme.onSurface)
                                                if p.isCritical == true {
                                                    Text(L("حسّاس")).font(.wx(9, .bold)).foregroundStyle(Theme.danger)
                                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                                        .background(Theme.dangerBg, in: Capsule())
                                                }
                                            }
                                            if let d = p.description, !d.isEmpty {
                                                Text(d).font(.wx(11)).foregroundStyle(Theme.onMuted)
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
            self.error = error.apiMessage
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
            self.error = error.apiMessage
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
                            .font(.wx(12)).foregroundStyle(Theme.onMuted)
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
                Text(p.title).font(.wx(14, .medium)).foregroundStyle(Theme.onSurface)
                if p.isCritical == true {
                    Text(L("حسّاس")).font(.wx(9, .bold)).foregroundStyle(Theme.danger)
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
                .font(.wx(11)).foregroundStyle(Theme.onFaint)
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
            async let permsRequest = Api.shared.userPermissions(userId)
            // Consume the catalog BEFORE the throwing await — otherwise a
            // permissions failure abandons the in-flight catalog request.
            catalog = (try? await cat) ?? []
            let perms = try await permsRequest
            rolePerms = Set(perms.rolePermissions)
            var map: [String: Bool] = [:]
            for o in perms.overrides { map[o.permissionId] = o.allowed }
            overrides = map
        } catch {
            self.error = error.apiMessage
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
            self.error = error.apiMessage
        }
        saving = false
    }
}

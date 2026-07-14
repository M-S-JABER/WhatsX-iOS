import SwiftUI

// MARK: - Templates

struct TemplatesView: View {
    @State private var templates: [Template] = []
    @State private var ready: [ReadyMessage] = []
    @State private var accounts: [Instance] = []
    @State private var loading = true
    @State private var loadError: String?
    @State private var editorOpen = false
    @State private var createTemplateOpen = false
    @State private var editing: ReadyMessage?
    @State private var syncing = false
    @State private var banner: String?

    var body: some View {
        ScrollView {
            if loading {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            } else if let err = loadError {
                LoadFailedView(message: err) { Task { loading = true; await load() } }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if let banner {
                        Text(banner).font(.wx(12)).foregroundStyle(Theme.success)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !ready.isEmpty {
                        Text(L("الردود الجاهزة")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
                        ForEach(ready) { r in readyCard(r) }
                    }
                    if !templates.isEmpty {
                        Text(L("قوالب Meta")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
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
        let readyResp = try? await r
        let templatesResp = try? await t
        ready = readyResp?.items ?? []
        templates = templatesResp?.items ?? []
        accounts = (try? await a)?.items ?? []
        // Both primary lists failing means the load itself failed — show it.
        loadError = (readyResp == nil && templatesResp == nil) ? L("تعذّر الاتصال بالخادم") : nil
        loading = false
    }

    private func sync() async {
        syncing = true; banner = nil
        do {
            let r = try await Api.shared.syncTemplates()
            banner = L("تمت المزامنة:") + " \(r.syncedCount) " + L("قالب من Meta.")
            await load()
        } catch {
            banner = error.apiMessage
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
                Text(t.name).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                let tag = t.status ?? t.language ?? ""
                if !tag.isEmpty {
                    Text(tag).font(.wx(11, .semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
            if let body = t.bodyText, !body.isEmpty {
                Text(body).font(.wx(13)).foregroundStyle(Theme.onMuted).lineLimit(3)
            }
            HStack {
                Spacer()
                Button { Task { await deleteTemplate(t) } } label: {
                    Image(icon: .trash).font(.wx(14, .semibold)).foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                        .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel(L("حذف"))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(18)
    }

    private func readyCard(_ r: ReadyMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(r.name).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface)
                Spacer()
                let tag = r.isActive ? L("مُفعّل") : L("متوقّف")
                Text(tag).font(.wx(11, .semibold)).foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.primaryContainer, in: Capsule())
            }
            if !r.body.isEmpty { Text(r.body).font(.wx(13)).foregroundStyle(Theme.onMuted).lineLimit(3) }
            HStack(spacing: 8) {
                Spacer()
                Button { editing = r; editorOpen = true } label: {
                    Image(icon: .edit).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                        .frame(width: 32, height: 32)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel(L("تعديل"))
                Button { Task { await delete(r) } } label: {
                    Image(icon: .trash).font(.wx(14, .semibold)).foregroundStyle(Theme.danger)
                        .frame(width: 32, height: 32)
                        .background(Theme.dangerBg, in: RoundedRectangle(cornerRadius: 9))
                }
                .accessibilityLabel(L("حذف"))
            }
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
            self.error = error.apiMessage
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
            self.error = error.apiMessage
        }
        saving = false
    }
}

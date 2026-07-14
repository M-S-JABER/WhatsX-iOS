import SwiftUI

// MARK: - Ready-message quick picker

struct ReadyPickerSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReadyMessage] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary)
                } else if items.isEmpty {
                    Text(L("لا ردود جاهزة")).foregroundStyle(Theme.onMuted)
                } else {
                    List(items) { r in
                        Button { onPick(r.body); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                                Text(r.body).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(2)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("ردود جاهزة")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } } }
            .task {
                items = (try? await Api.shared.readyMessages())?.items ?? []
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Template picker + parameter fill

struct TemplatePickerSheet: View {
    let onSend: (String, String?, [String]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [Template] = []
    @State private var loading = true
    @State private var selected: Template?
    @State private var params: [String] = []
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Group {
                if let t = selected {
                    paramForm(t)
                } else if loading {
                    ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if templates.isEmpty {
                    Text(L("لا قوالب")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(templates, id: \.stableId) { t in
                        Button {
                            selected = t
                            params = Array(repeating: "", count: max(0, t.bodyParams))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.name).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                                if let preview = t.bodyText {
                                    Text(preview).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(2)
                                }
                                Text([t.status, t.language].compactMap { $0 }.joined(separator: " · "))
                                    .font(.wx(11)).foregroundStyle(Theme.onFaint)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(selected == nil ? L("القوالب") : L("إرسال قالب")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selected == nil ? L("إغلاق") : L("رجوع")) {
                        if selected == nil { dismiss() } else { selected = nil }
                    }
                }
                if let t = selected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("إرسال")) {
                            Task { sending = true; await onSend(t.name, t.language, params); sending = false; dismiss() }
                        }.disabled(sending)
                    }
                }
            }
            .task {
                templates = (try? await Api.shared.templates())?.items ?? []
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func paramForm(_ t: Template) -> some View {
        Form {
            Section(L("القالب")) {
                Text(t.name).font(.wx(17, .semibold)).foregroundStyle(Theme.onSurface)
                if let preview = t.bodyText { Text(preview).font(.wx(12)).foregroundStyle(Theme.onMuted) }
            }
            if t.bodyParams > 0 {
                Section(L("المتغيرات")) {
                    ForEach(0..<t.bodyParams, id: \.self) { i in
                        TextField(L("المتغير") + " \(i + 1)", text: Binding(
                            get: { i < params.count ? params[i] : "" },
                            set: { v in if i < params.count { params[i] = v } }
                        ))
                    }
                }
            } else {
                Section { Text(L("لا متغيرات في هذا القالب")).foregroundStyle(Theme.onMuted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }
}

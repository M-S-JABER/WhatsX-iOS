import SwiftUI

// Global search tab: searches every conversation (active + archived) by
// name, phone, or last-message preview and opens the chat directly. On
// iOS 26 the tab itself is the system search circle that morphs into the
// search field (Tab role .search in MainTabView).
struct GlobalSearchView: View {
    @State private var query = ""
    @State private var all: [Conversation] = []
    @State private var loading = false

    // The full conversations list (active + archived) when the query is
    // empty — pressing the search tab keeps you "on the same list" while the
    // bottom bar morphs into the search field; typing filters it live.
    private var results: [Conversation] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.phone ?? "").localizedCaseInsensitiveContains(q)
                || $0.preview.localizedCaseInsensitiveContains(q)
        }
    }

    @State private var searchActive = false

    var body: some View {
        NavigationStack {
            searchableCore
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .navigationTitle(L("المحادثات"))
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Conversation.self) { ChatView(conversation: $0) }
                .task { await load() }
                .refreshable { await load() }
        }
        // Activate the field the moment the tab opens: the search circle
        // morphs into the bar (system animation) and the keyboard pops up.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { searchActive = true }
        }
        .onDisappear { searchActive = false }
    }

    /// iOS 17+ gets programmatic activation (auto-focus + keyboard);
    /// iOS 16 falls back to plain searchable.
    @ViewBuilder
    private var searchableCore: some View {
        if #available(iOS 17.0, *) {
            core.searchable(text: $query, isPresented: $searchActive,
                            prompt: L("ابحث بالاسم أو الرقم أو الرسالة"))
        } else {
            core.searchable(text: $query, prompt: L("ابحث بالاسم أو الرقم أو الرسالة"))
        }
    }

    private var core: some View {
        Group {
            if loading && all.isEmpty {
                ProgressView().tint(Theme.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                hint(icon: "questionmark.bubble", text: L("لا نتائج مطابقة"))
            } else {
                List(results) { conv in
                    ZStack {
                        NavigationLink(value: conv) { EmptyView() }.opacity(0)
                        ConversationRow(conv: conv)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.outline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func hint(icon: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 42)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.onFaint)
            Text(text)
                .font(.subheadline).foregroundStyle(Theme.onMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        loading = true
        var merged: [Conversation] = []
        if let active = try? await Api.shared.conversations(archived: false, page: 1, pageSize: 300) {
            merged += active.items
        }
        if let archived = try? await Api.shared.conversations(archived: true, page: 1, pageSize: 300) {
            merged += archived.items
        }
        var seen = Set<String>()
        all = merged.filter { seen.insert($0.id).inserted }
        loading = false
    }
}

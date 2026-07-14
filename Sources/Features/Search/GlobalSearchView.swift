import SwiftUI

/// Universal search tab: one query across conversations, customers and the
/// call log. Customers and calls search server-side; conversations are
/// fetched once and filtered locally (the backend has no conversation-search
/// endpoint yet).
@MainActor
final class GlobalSearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var conversations: [Conversation] = []
    @Published var customers: [StatCustomer] = []
    @Published var calls: [VoiceCall] = []
    @Published var searching = false

    private var allConversations: [Conversation] = []
    private var searchTask: Task<Void, Never>?

    var hasResults: Bool { !conversations.isEmpty || !customers.isEmpty || !calls.isEmpty }

    /// Warm the local conversation pool once per appearance.
    func prepare() async {
        guard allConversations.isEmpty else { return }
        allConversations = (try? await Api.shared.conversations(archived: false, page: 1, pageSize: 100))?.items ?? []
    }

    /// Debounced fan-out: local conversation filter + server-side customer
    /// and call search, all for one keystroke burst.
    func queryChanged() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            conversations = []; customers = []; calls = []; searching = false
            return
        }
        searching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            async let customersReq = Api.shared.statisticsCustomers(search: q)
            async let callsReq = Api.shared.voiceCalls(limit: 25, search: q)
            self.conversations = self.allConversations.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || ($0.phone ?? "").localizedCaseInsensitiveContains(q)
                    || $0.preview.localizedCaseInsensitiveContains(q)
            }
            self.customers = (try? await customersReq)?.items ?? []
            self.calls = (try? await callsReq)?.items ?? []
            if !Task.isCancelled { self.searching = false }
        }
    }
}

struct GlobalSearchView: View {
    @StateObject private var vm = GlobalSearchViewModel()
    @State private var openConversation: Conversation?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text(L("البحث الشامل")).font(.wx(22, .bold)).foregroundStyle(Theme.onSurface)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                searchField

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
                            hint
                        } else if vm.searching && !vm.hasResults {
                            ProgressView().tint(Theme.primary)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else if !vm.hasResults {
                            Text(L("لا نتائج")).foregroundStyle(Theme.onMuted)
                                .frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            results
                        }
                    }
                    .padding(14).padding(.bottom, 24)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
        }
        .task { await vm.prepare() }
        .sheet(item: $openConversation) { ChatView(conversation: $0) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(icon: .search).foregroundStyle(Theme.onMuted)
            TextField(L("ابحث عن محادثة أو عميل أو مكالمة"), text: $vm.query)
                .foregroundStyle(Theme.onSurface)
                .focused($focused)
                .submitLabel(.search)
                .onChange(of: vm.query) { _ in vm.queryChanged() }
            if !vm.query.isEmpty {
                Button {
                    vm.query = ""
                    Haptics.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.onFaint)
                }
                .accessibilityLabel(L("إغلاق البحث"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private var hint: some View {
        VStack(spacing: 12) {
            Image(icon: .search).font(.wx(34)).foregroundStyle(Theme.onFaint)
            Text(L("ابحث عن محادثة أو عميل أو مكالمة"))
                .font(.wx(14)).foregroundStyle(Theme.onMuted)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    @ViewBuilder
    private var results: some View {
        if !vm.conversations.isEmpty {
            sectionTitle(L("المحادثات"))
            ForEach(vm.conversations) { conv in
                Button {
                    Haptics.tap()
                    openConversation = conv
                } label: { conversationRow(conv) }
                    .buttonStyle(.plain)
            }
        }
        if !vm.customers.isEmpty {
            sectionTitle(L("العملاء"))
            ForEach(vm.customers) { c in
                NavigationLink {
                    CustomerReportDetailView(conversationId: c.conversationId, title: c.title)
                } label: { customerRow(c) }
                    .buttonStyle(.plain)
            }
        }
        if !vm.calls.isEmpty {
            sectionTitle(L("المكالمات"))
            ForEach(vm.calls) { call in callRow(call) }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.wx(13, .bold)).foregroundStyle(Theme.onMuted)
            .padding(.top, 6)
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        HStack(spacing: 12) {
            Avatar(name: conv.title, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                if !conv.preview.isEmpty {
                    Text(conv.preview).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(1)
                }
            }
            Spacer()
            // chevron.forward is layout-direction aware (flips in RTL).
            Image(systemName: "chevron.forward").font(.wx(12)).foregroundStyle(Theme.onFaint)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .glassCard(Theme.Radius.card)
    }

    private func customerRow(_ c: StatCustomer) -> some View {
        HStack(spacing: 12) {
            Avatar(name: c.title, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                if let phone = c.phone, !phone.isEmpty {
                    Text(phone).font(.wx(12)).foregroundStyle(Theme.onMuted)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            Spacer()
            Image(icon: .pdf).font(.wx(14)).foregroundStyle(Theme.info)
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .glassCard(Theme.Radius.card)
    }

    private func callRow(_ call: VoiceCall) -> some View {
        HStack(spacing: 12) {
            Image(icon: call.isMissed ? .callMissed : (call.isInbound ? .callIn : .callOut))
                .font(.wx(16))
                .foregroundStyle(call.isMissed ? Theme.danger : (call.isInbound ? Theme.success : Theme.info))
                .frame(width: 42, height: 42)
                .background(Theme.surface2, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(call.title).font(.wx(15, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                Text(shortTime(call.startedAt)).font(.wx(12)).foregroundStyle(Theme.onMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .glassCard(Theme.Radius.card)
    }
}

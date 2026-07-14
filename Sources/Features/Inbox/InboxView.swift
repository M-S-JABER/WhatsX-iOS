import SwiftUI

enum InboxSegment: String, CaseIterable {
    case active, unread, archived
    var title: String {
        switch self { case .active: return L("النشطة"); case .unread: return L("غير المقروءة"); case .archived: return L("المؤرشفة") }
    }
}

@MainActor
final class InboxViewModel: ObservableObject {
    @Published var items: [Conversation] = []
    @Published var loading = false
    @Published var loadingMore = false
    @Published var error: String?
    @Published var segment: InboxSegment = .active
    @Published var instances: [Instance] = []
    @Published var selectedInstanceIds: Set<String> = []

    private var page = 1
    private var total = 0
    private let pageSize = 50
    private var pins: Set<String> = []
    private var realtimeRefreshTask: Task<Void, Never>?

    var showArchived: Bool { segment == .archived }

    /// Pinned conversations float to the top, preserving the backend order
    /// otherwise. Stored (not computed) — sorting the whole list on every
    /// body evaluation showed up in scrolling.
    @Published private(set) var shown: [Conversation] = []

    private func updateShown() {
        shown = items.enumerated().sorted { a, b in
            if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Floating archive button: flip between the active inbox and the archive.
    func toggleArchived() {
        segment = showArchived ? .active : .archived
        Task { await load() }
    }

    /// Load the WhatsApp accounts once for the filter chips (multi-account inboxes).
    func loadInstances() async {
        instances = (try? await Api.shared.instances())?.items ?? []
    }

    /// Primary-number picker (floating pill menu): show one account only, or all.
    func selectOnly(_ id: String?) {
        if let id { selectedInstanceIds = [id] } else { selectedInstanceIds.removeAll() }
        Task { await load() }
    }

    func toggleInstance(_ id: String?) {
        if let id {
            if selectedInstanceIds.contains(id) { selectedInstanceIds.remove(id) }
            else { selectedInstanceIds.insert(id) }
        } else {
            selectedInstanceIds.removeAll()
        }
        Task { await load() }
    }

    private var instanceFilter: String? {
        selectedInstanceIds.isEmpty ? nil : selectedInstanceIds.sorted().joined(separator: ",")
    }

    func load() async {
        loading = items.isEmpty
        error = nil
        do {
            async let convTask = Api.shared.conversations(
                archived: showArchived, page: 1, pageSize: pageSize, instanceIds: instanceFilter)
            async let pinsTask = Api.shared.pinnedConversationIds()
            let resp = try await convTask
            pins = Set((try? await pinsTask) ?? [])
            // Stamp the pinned state onto each conversation so rows can sort/mark it.
            page = 1
            total = resp.total
            items = resp.items.map { var c = $0; c.pinned = pins.contains(c.id); return c }
            updateShown()
            // Active inbox feeds the tab badge (archived view must not clobber it).
            if !showArchived {
                UnreadCenter.shared.total = items.reduce(0) { $0 + $1.unread }
            }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    /// Realtime message events: refetch page 1 and MERGE it over the loaded
    /// list instead of resetting to page 1 — the old full reload threw away
    /// every extra page (and the scroll position) on each incoming message.
    /// Bursts are coalesced into one refetch.
    func scheduleRealtimeRefresh() {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshFirstPage()
        }
    }

    func cancelRealtimeRefresh() {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
    }

    private func refreshFirstPage() async {
        do {
            async let convTask = Api.shared.conversations(
                archived: showArchived, page: 1, pageSize: pageSize, instanceIds: instanceFilter)
            async let pinsTask = Api.shared.pinnedConversationIds()
            let resp = try await convTask
            pins = Set((try? await pinsTask) ?? [])
            total = resp.total
            let fresh = resp.items.map { var c = $0; c.pinned = pins.contains(c.id); return c }
            let freshIds = Set(fresh.map { $0.id })
            items = fresh + items.filter { !freshIds.contains($0.id) }
            updateShown()
            if !showArchived {
                UnreadCenter.shared.total = items.reduce(0) { $0 + $1.unread }
            }
        } catch {}
    }

    /// Infinite scroll: pull the next page once the given row is near the end
    /// of the visible list.
    func loadMoreIfNeeded(after conv: Conversation) {
        guard items.count < total, !loadingMore, !loading else { return }
        let tail = shown.suffix(6).map { $0.id }
        guard tail.contains(conv.id) else { return }
        loadingMore = true
        Task {
            let next = page + 1
            if let resp = try? await Api.shared.conversations(
                archived: showArchived, page: next, pageSize: pageSize, instanceIds: instanceFilter) {
                page = next
                total = resp.total
                let existing = Set(items.map { $0.id })
                let fresh = resp.items
                    .filter { !existing.contains($0.id) }
                    .map { var c = $0; c.pinned = pins.contains(c.id); return c }
                items += fresh
                updateShown()
                if !showArchived {
                    UnreadCenter.shared.total = items.reduce(0) { $0 + $1.unread }
                }
            }
            loadingMore = false
        }
    }

    func archive(_ conv: Conversation) async {
        try? await Api.shared.archiveConversation(conv.id, archived: !conv.archived)
        await load()
    }
    func delete(_ conv: Conversation) async {
        try? await Api.shared.deleteConversation(conv.id)
        await load()
    }
    func pin(_ conv: Conversation) async {
        try? await Api.shared.pinConversation(conv.id, pinned: !conv.isPinned)
        await load()
    }
}

struct InboxView: View {
    @StateObject private var vm = InboxViewModel()
    @State private var showNew = false
    @State private var searchOpen = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    /// Conversations after the in-place bottom search filter.
    private var displayed: [Conversation] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vm.shown }
        return vm.shown.filter {
            $0.title.localizedCaseInsensitiveContains(q)
                || ($0.phone ?? "").localizedCaseInsensitiveContains(q)
                || $0.preview.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                bottomBar
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            // RTL: trailing = the visual top-LEFT corner.
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 10) {
                    accountsButton
                    archiveButton
                }
                .padding(.trailing, 16)
                .padding(.top, 6)
            }
        }
        .sheet(isPresented: $showNew) { NewConversationSheet() }
        .task {
            await vm.loadInstances()
            await vm.load()
        }
        .onReceive(Realtime.shared.events) { event in
            guard RealtimeEvent.inboxEvents.contains(event.name) else { return }
            // Pin/archive change the list's membership — do a full reload.
            // Message traffic just reorders/updates rows — merge page 1 in.
            if event.name.hasPrefix("conversation_") {
                Task { await vm.load() }
            } else {
                vm.scheduleRealtimeRefresh()
            }
        }
        .onDisappear { vm.cancelRealtimeRefresh() }
        // Second press on the chats tab (while already on it) flips
        // active ⇄ archive.
        .onReceive(InboxBus.shared.toggleArchive) { _ in
            withAnimation { vm.toggleArchived() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(vm.showArchived ? L("الأرشيف") : L("المحادثات"))
                .font(.wx(22, .bold)).foregroundStyle(Theme.onSurface)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 22)
    }

    /// Floating archive toggle (visual top-left): opens the archive; while
    /// inside it, turns amber and flips back to the active inbox.
    /// One size for all three floating circles (archive · accounts · compose).
    static let floatingButtonSide: CGFloat = 52

    private var archiveButton: some View {
        Button { withAnimation { vm.toggleArchived() } } label: {
            Image(systemName: vm.showArchived ? "archivebox.fill" : "archivebox")
                .font(.wx(20, .semibold))
                .foregroundStyle(vm.showArchived ? Theme.onPrimary : Theme.primary)
                .frame(width: Self.floatingButtonSide, height: Self.floatingButtonSide)
                .background(vm.showArchived ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(.clear), in: Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
    }

    /// Bottom floating row: the search circle that EXPANDS in place into a
    /// full-width bottom search bar (same slide/expand animation style as the
    /// chat's top search), plus the compose circle (hidden while searching).
    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !searchOpen { Spacer(minLength: 0) }
            searchContainer
            if !searchOpen { composeButton }
        }
    }

    private var searchContainer: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.wx(20, .semibold))
                .foregroundStyle(Theme.primary)
                .frame(width: searchOpen ? 26 : Self.floatingButtonSide,
                       height: Self.floatingButtonSide)
            if searchOpen {
                TextField(L("ابحث في المحادثات"), text: $searchText)
                    .font(.wx(15))
                    .foregroundStyle(Theme.onSurface)
                    .focused($searchFocused)
                    .submitLabel(.search)
                Button { closeSearch() } label: {
                    Image(systemName: "xmark")
                        .font(.wx(14, .semibold))
                        .foregroundStyle(Theme.onMuted)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
            }
        }
        .frame(maxWidth: searchOpen ? .infinity : Self.floatingButtonSide)
        .frame(height: Self.floatingButtonSide)
        .glassCapsule(interactive: true)
        .contentShape(Capsule())
        .onTapGesture { if !searchOpen { openSearch() } }
    }

    private func openSearch() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { searchOpen = true }
        // Focus right after the expansion starts so the keyboard rises with it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { searchFocused = true }
    }

    private func closeSearch() {
        searchFocused = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            searchOpen = false
            searchText = ""
        }
    }

    private var composeButton: some View {
        Button { showNew = true } label: {
            Image(systemName: "square.and.pencil")
                .font(.wx(21, .medium))
                .foregroundStyle(Theme.primary)
                .frame(width: Self.floatingButtonSide, height: Self.floatingButtonSide)
        }
        .buttonStyle(.plain)
        .glassCircle()
    }

    /// Top account picker (next to the archive button): multi-select menu;
    /// stays open while picking on iOS 16.4+.
    private var accountsButton: some View {
        Group {
            if #available(iOS 16.4, *) {
                accountsMenu.menuActionDismissBehavior(.disabled)
            } else {
                accountsMenu
            }
        }
    }

    private var accountsMenu: some View {
        Menu {
            Button { vm.selectOnly(nil) } label: {
                if vm.selectedInstanceIds.isEmpty {
                    Label(L("كل الحسابات"), systemImage: "checkmark")
                } else {
                    Text(L("كل الحسابات"))
                }
            }
            ForEach(vm.instances) { inst in
                Button { vm.toggleInstance(inst.id) } label: {
                    if vm.selectedInstanceIds.contains(inst.id) {
                        Label(inst.label, systemImage: "checkmark")
                    } else {
                        Text(inst.label)
                    }
                }
            }
        } label: {
            ZStack {
                Image(systemName: "circle.dashed")
                    .font(.wx(25, .regular))
                Image(systemName: "plus")
                    .font(.wx(12, .bold))
            }
            .foregroundStyle(Theme.primary)
            .frame(width: Self.floatingButtonSide, height: Self.floatingButtonSide)
            .overlay(alignment: .topTrailing) {
                if !vm.selectedInstanceIds.isEmpty {
                    Text("\(vm.selectedInstanceIds.count)")
                        .font(.wx(9, .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 16, height: 16)
                        .background(Theme.primary, in: Circle())
                        .offset(x: 2, y: -2)
                }
            }
        }
        .glassCircle()
    }

    private var content: some View {
        Group {
            if vm.loading && vm.items.isEmpty {
                Spacer(); ProgressView().tint(Theme.primary); Spacer()
            } else if displayed.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: !searchText.isEmpty ? "questionmark.bubble"
                            : (vm.segment == .archived ? "archivebox" : "bubble.left.and.bubble.right"))
                        .font(.wx(42)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.onFaint)
                    Text(!searchText.isEmpty ? L("لا نتائج مطابقة") : L("لا توجد محادثات"))
                        .foregroundStyle(Theme.onMuted)
                }
                Spacer()
            } else {
                List {
                    ForEach(displayed) { conv in
                        ZStack {
                            NavigationLink(value: conv) { EmptyView() }.opacity(0)
                            ConversationRow(conv: conv)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.background)
                        .listRowSeparatorTint(Theme.outline)
                        .listRowSeparator(.hidden, edges: .top)
                        .onAppear { if searchText.isEmpty { vm.loadMoreIfNeeded(after: conv) } }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await vm.delete(conv) } } label: {
                                Label(L("حذف"), systemImage: "trash")
                            }
                            Button { Task { await vm.archive(conv) } } label: {
                                Label(vm.showArchived ? L("إلغاء الأرشفة") : L("أرشفة"), systemImage: "archivebox")
                            }.tint(Theme.success)
                        }
                        .swipeActions(edge: .leading) {
                            Button { Task { await vm.pin(conv) } } label: {
                                Label(conv.isPinned ? L("إلغاء التثبيت") : L("تثبيت"), systemImage: conv.isPinned ? "pin.slash" : "pin")
                            }.tint(Theme.primary)
                        }
                    }
                    if vm.loadingMore {
                        HStack {
                            Spacer()
                            ProgressView().tint(Theme.primary)
                            Spacer()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.background)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 12)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: Conversation.self) { conv in
                    ChatView(conversation: conv)
                }
                .refreshable { await vm.load() }
            }
        }
    }
}

struct ConversationRow: View {
    let conv: Conversation
    var body: some View {
        HStack(spacing: 13) {
            Avatar(name: conv.title, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if conv.isPinned {
                        Image(systemName: "pin.fill").font(.wx(10)).foregroundStyle(Theme.primary)
                    }
                    Text(conv.title).font(.wx(15.5, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Spacer()
                    Text(shortTime(conv.lastAt)).font(.wx(11))
                        .foregroundStyle(conv.unread > 0 ? Theme.primary : Theme.onFaint)
                }
                HStack {
                    Text(conv.preview).font(.wx(13.5)).foregroundStyle(Theme.onMuted).lineLimit(1)
                    Spacer()
                    if conv.unread > 0 {
                        Text("\(conv.unread)").font(.wx(11, .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.primary, in: Capsule())
                    }
                }
                if let acct = conv.instance?.label {
                    Text(acct).font(.wx(10, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(AccountColor.color(conv.instance?.id ?? acct), in: Capsule())
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

// Very small relative-time formatter for list rows.
func shortTime(_ iso: String?) -> String {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) ?? flexibleDate(iso) else { return "" }
    let cal = Calendar.current
    if cal.isDateInToday(date) {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    if cal.isDateInYesterday(date) { return L("أمس") }
    let f = DateFormatter(); f.dateFormat = "dd/MM"; return f.string(from: date)
}

private func flexibleDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s)
}

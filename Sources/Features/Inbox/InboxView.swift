import SwiftUI
import UIKit

enum InboxSegment: String, CaseIterable {
    case active, unread, archived
    var title: String {
        switch self { case .active: return L("الكل"); case .unread: return L("غير المقروءة"); case .archived: return L("المؤرشفة") }
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
            self.error = error.apiMessage
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
    /// Global search results (customers/calls + conversations beyond the
    /// loaded pages) — the 2.0 persistent field feeds both this and the
    /// instant local filter.
    @StateObject private var globalVM = GlobalSearchViewModel()
    @State private var showNew = false
    @State private var searchText = ""
    /// iPad split mode: the conversation open in the detail pane.
    @State private var selectedConv: Conversation?
    /// Phone mode: programmatic push target (notification deep-link).
    @State private var path = NavigationPath()
    @FocusState private var searchFocused: Bool
    @Namespace private var segmentNamespace

    private var query: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Conversations after the segment filter and the live search filter.
    private var displayed: [Conversation] {
        var base = vm.shown
        if vm.segment == .unread { base = base.filter { $0.unread > 0 } }
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || ($0.phone ?? "").localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    /// Search hits from the global pool that the local list doesn't already show.
    private var globalExtraConversations: [Conversation] {
        guard !query.isEmpty else { return [] }
        let shownIds = Set(displayed.map { $0.id })
        return globalVM.conversations.filter { !shownIds.contains($0.id) }
    }

    var body: some View {
        GeometryReader { geo in
            // iPad with room for two panes: chat list + open conversation
            // side by side (like Mail/Messages). Phones keep the push flow.
            if UIDevice.current.userInterfaceIdiom == .pad && geo.size.width >= 700 {
                splitBody
            } else {
                phoneBody
            }
        }
        .sheet(isPresented: $showNew) { NewConversationSheet() }
        .task {
            await vm.loadInstances()
            await vm.load()
            await globalVM.prepare()
            // A notification tapped before the inbox existed (cold start)
            // left its conversation pending — honor it now.
            if let id = InboxBus.shared.consumePendingConversation() {
                await openConversation(id)
            }
        }
        .onReceive(InboxBus.shared.openConversation) { id in
            _ = InboxBus.shared.consumePendingConversation()
            Task { await openConversation(id) }
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

    /// Notification deep-link: resolve the conversation (from the loaded
    /// list when possible, the API otherwise) and open it in whichever
    /// layout is live — push on phones, detail pane on iPad.
    private func openConversation(_ id: String) async {
        guard !id.isEmpty else { return }
        let conv: Conversation?
        if let loaded = vm.shown.first(where: { $0.id == id }) {
            conv = loaded
        } else {
            conv = try? await Api.shared.conversation(id)
        }
        guard let conv else { return }
        selectedConv = conv
        path.append(conv)
    }

    private var phoneBody: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                searchBar
                controlsRow
                listContent(split: false)
            }
            .background(Theme.glowBackground())
            .navigationBarHidden(true)
        }
    }

    private var splitBody: some View {
        NavigationStack {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    header
                    searchBar
                    controlsRow
                    listContent(split: true)
                }
                .frame(width: 380)
                .background(Theme.surface1.ignoresSafeArea())

                Rectangle().fill(Theme.outline).frame(width: 1).ignoresSafeArea()

                detailPane
            }
            .background(Theme.glowBackground())
            .navigationBarHidden(true)
        }
    }

    /// Right pane on iPad: the selected conversation, or a friendly empty state.
    @ViewBuilder
    private var detailPane: some View {
        if let conv = selectedConv {
            // .id restarts the ChatView (VM and all) when switching rows.
            ChatView(conversation: conv).id(conv.id)
        } else {
            VStack(spacing: 14) {
                BrandMark(size: 72)
                Text(L("اختر محادثة")).font(.wx(19, .bold)).foregroundStyle(Theme.onSurface)
                Text(L("اختر محادثة من القائمة لعرضها هنا"))
                    .font(.wx(13)).foregroundStyle(Theme.onMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header · search · controls (design 4b)

    private var header: some View {
        HStack(spacing: 12) {
            Text(vm.showArchived ? L("الأرشيف") : L("المحادثات"))
                .font(.wx(30, .bold)).foregroundStyle(Theme.onSurface)
            Spacer()
            Button { showNew = true } label: {
                Image(systemName: "plus")
                    .font(.wx(19, .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(L("محادثة جديدة"))
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    /// The 2.0 persistent search field: filters the list instantly and fans
    /// out to customers/calls (GlobalSearchViewModel) for the same query.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.wx(16, .medium)).foregroundStyle(Theme.onMuted)
            TextField(L("ابحث عن محادثة أو عميل أو مكالمة"), text: $searchText)
                .font(.wx(15)).foregroundStyle(Theme.onSurface)
                .focused($searchFocused)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                    Haptics.tap()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.onFaint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("إغلاق البحث"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .glassCapsule()
        .padding(.horizontal, 16).padding(.bottom, 10)
        .onChange(of: searchText) { q in
            globalVM.query = q
            globalVM.queryChanged()
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            segmented
            Spacer(minLength: 8)
            accountsButton
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    /// Custom segmented control per the 2.0 spec (track + floating white
    /// thumb). Crossing the archive boundary reloads; all/unread is local.
    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(InboxSegment.allCases, id: \.self) { seg in
                Button { setSegment(seg) } label: {
                    Text(seg.title)
                        .font(.wx(13, vm.segment == seg ? .semibold : .medium))
                        .foregroundStyle(vm.segment == seg ? Theme.onSurface : Theme.onMuted)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background {
                            if vm.segment == seg {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.segmentedActive)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "activeSegment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.segmentedTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func setSegment(_ seg: InboxSegment) {
        guard seg != vm.segment else { return }
        Haptics.selection()
        let crossesArchive = (seg == .archived) != (vm.segment == .archived)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            vm.segment = seg
        }
        if crossesArchive { Task { await vm.load() } }
    }

    /// «الحسابات ▾» dropdown (multi-select; stays open while picking on 16.4+).
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
            HStack(spacing: 5) {
                Text(vm.selectedInstanceIds.isEmpty
                     ? L("الحسابات")
                     : L("الحسابات") + " · \(vm.selectedInstanceIds.count)")
                    .font(.wx(13, .semibold))
                Image(systemName: "chevron.down").font(.wx(10, .semibold))
            }
            .foregroundStyle(vm.selectedInstanceIds.isEmpty ? Theme.onMuted : Theme.amberText)
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .glassCapsule()
        .accessibilityLabel(L("تصفية الحسابات"))
    }

    // MARK: - List

    private func listContent(split: Bool) -> some View {
        Group {
            if vm.loading && vm.items.isEmpty {
                Spacer(); ProgressView().tint(Theme.primary); Spacer()
            } else if displayed.isEmpty && globalExtraConversations.isEmpty
                        && globalVM.customers.isEmpty && globalVM.calls.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: !query.isEmpty ? "questionmark.bubble"
                            : (vm.segment == .archived ? "archivebox" : "bubble.left.and.bubble.right"))
                        .font(.wx(42)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.onFaint)
                    Text(!query.isEmpty ? L("لا نتائج مطابقة") : L("لا توجد محادثات"))
                        .foregroundStyle(Theme.onMuted)
                }
                Spacer()
            } else {
                List {
                    ForEach(displayed) { conv in
                        conversationCell(conv, split: split)
                            .onAppear { if query.isEmpty { vm.loadMoreIfNeeded(after: conv) } }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Haptics.action(); Task { await vm.delete(conv) } } label: {
                                    Label(L("حذف"), systemImage: "trash")
                                }
                                Button { Haptics.action(); Task { await vm.archive(conv) } } label: {
                                    Label(vm.showArchived ? L("إلغاء الأرشفة") : L("أرشفة"), systemImage: "archivebox")
                                }.tint(Theme.success)
                            }
                            .swipeActions(edge: .leading) {
                                Button { Haptics.action(); Task { await vm.pin(conv) } } label: {
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
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 12)
                    }
                    globalResults(split: split)
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

    /// One list row wired for the live layout: tap-select in the split pane,
    /// hidden NavigationLink push on phones.
    private func conversationCell(_ conv: Conversation, split: Bool) -> some View {
        ZStack {
            if split {
                ConversationRow(conv: conv)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Haptics.tap()
                        selectedConv = conv
                    }
                    .background(selectedConv?.id == conv.id ? Theme.primarySoft : .clear)
            } else {
                NavigationLink(value: conv) { EmptyView() }.opacity(0)
                ConversationRow(conv: conv)
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.08))
        .listRowSeparator(.hidden, edges: .top)
        .alignmentGuide(.listRowSeparatorLeading) { d in
            // Inset the separator past the avatar block (design 4b).
            d[.leading] + 81
        }
    }

    /// Search fan-out: conversations beyond the loaded pages, customers and
    /// calls — same query, appended under the local matches.
    @ViewBuilder
    private func globalResults(split: Bool) -> some View {
        if !query.isEmpty {
            if globalVM.searching && !globalVM.hasResults {
                HStack { Spacer(); ProgressView().tint(Theme.primary); Spacer() }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(globalExtraConversations) { conv in
                conversationCell(conv, split: split)
            }
            if !globalVM.customers.isEmpty {
                searchSectionTitle(L("العملاء"))
                ForEach(globalVM.customers) { c in
                    ZStack {
                        NavigationLink {
                            CustomerReportDetailView(conversationId: c.conversationId, title: c.title)
                        } label: { EmptyView() }.opacity(0)
                        customerRow(c)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            if !globalVM.calls.isEmpty {
                searchSectionTitle(L("المكالمات"))
                ForEach(globalVM.calls) { call in
                    callRow(call)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }

    private func searchSectionTitle(_ t: String) -> some View {
        Text(t).font(.wx(13, .bold)).foregroundStyle(Theme.onMuted)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
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
        .padding(.horizontal, 16).padding(.vertical, 9)
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
        .padding(.horizontal, 16).padding(.vertical, 9)
    }
}

/// One conversation row per design 4b: avatar 52 wearing the account-color
/// ring (2.5px background gap + 2px color), name 17/600, amber time for
/// unread rows, amber-gradient unread counter — and escalated conversations
/// (upset patient, metadata.aiEscalate) lifted onto a glass card with the
/// red follow-up badge.
struct ConversationRow: View {
    let conv: Conversation
    private var isEscalated: Bool { conv.metadata?.aiEscalate != nil }

    private var ringColor: Color? {
        guard let inst = conv.instance else { return nil }
        return AccountColor.color(inst.id.isEmpty ? inst.label : inst.id)
    }

    var body: some View {
        if isEscalated {
            content
                .padding(.horizontal, 14).padding(.vertical, 11)
                .glassCard(22)
                .padding(.horizontal, 10).padding(.vertical, 5)
        } else {
            content
                .padding(.horizontal, 16).padding(.vertical, 11)
        }
    }

    private var content: some View {
        HStack(spacing: 13) {
            ringedAvatar
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    if conv.isPinned {
                        Image(systemName: "pin.fill").font(.wx(10)).foregroundStyle(Theme.primary)
                    }
                    if isEscalated {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.wx(10)).foregroundStyle(Theme.danger)
                    }
                    Text(conv.title).font(.wx(17, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Spacer()
                    Text(shortTime(conv.lastAt)).font(.wx(13, .semibold))
                        .foregroundStyle(conv.unread > 0 ? Theme.unreadTime : Theme.onFaint)
                }
                HStack {
                    Text(conv.preview).font(.wx(15)).foregroundStyle(Theme.onMuted).lineLimit(1)
                    Spacer()
                    if isEscalated {
                        Text(L("متابعة")).font(.wx(10, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.danger, in: Capsule())
                    }
                    if conv.unread > 0 {
                        Text("\(conv.unread)").font(.wx(12, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.amberAction, in: Capsule())
                    }
                }
            }
        }
    }

    /// The account ring: 2.5px background gap, then 2px of the account color.
    @ViewBuilder
    private var ringedAvatar: some View {
        if let ring = ringColor {
            Avatar(name: conv.title, size: 52)
                .padding(2.5)
                .overlay(Circle().strokeBorder(ring, lineWidth: 2))
        } else {
            Avatar(name: conv.title, size: 52)
        }
    }
}

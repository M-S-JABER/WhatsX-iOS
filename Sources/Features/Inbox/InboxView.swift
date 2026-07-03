import SwiftUI

enum InboxSegment: String, CaseIterable {
    case active, unread, archived
    var title: String {
        switch self { case .active: return "النشطة"; case .unread: return "غير المقروءة"; case .archived: return "المؤرشفة" }
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

    var showArchived: Bool { segment == .archived }

    var shown: [Conversation] {
        // Pinned conversations float to the top, preserving the backend order otherwise.
        items.enumerated().sorted { a, b in
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
            // Active inbox feeds the tab badge (archived view must not clobber it).
            if !showArchived {
                UnreadCenter.shared.total = items.reduce(0) { $0 + $1.unread }
            }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .overlay(alignment: .bottomTrailing) {
                floatingActions
                    .padding(.trailing, 16)
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
            Task { await vm.load() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(vm.showArchived ? "الأرشيف" : "المحادثات")
                .font(.title2.bold()).foregroundStyle(Theme.onSurface)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 22)
    }

    /// Floating archive toggle (visual top-left): opens the archive; while
    /// inside it, turns amber and flips back to the active inbox.
    private var archiveButton: some View {
        Button { withAnimation { vm.toggleArchived() } } label: {
            Image(systemName: vm.showArchived ? "archivebox.fill" : "archivebox")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(vm.showArchived ? Theme.onPrimary : Theme.primary)
                .frame(width: 40, height: 40)
                .background(vm.showArchived ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(.clear), in: Circle())
        }
        .buttonStyle(.plain)
        .glassCircle()
    }

    /// Floating compose button (bottom corner).
    private var floatingActions: some View {
        Button { showNew = true } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Theme.primary)
                .frame(width: 54, height: 54)
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
                    Label("كل الحسابات", systemImage: "checkmark")
                } else {
                    Text("كل الحسابات")
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
                    .font(.system(size: 21, weight: .regular))
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(Theme.primary)
            .frame(width: 40, height: 40)
            .overlay(alignment: .topTrailing) {
                if !vm.selectedInstanceIds.isEmpty {
                    Text("\(vm.selectedInstanceIds.count)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 15, height: 15)
                        .background(Theme.primary, in: Circle())
                        .offset(x: 3, y: -3)
                }
            }
        }
        .glassCircle()
    }

    private var content: some View {
        Group {
            if vm.loading && vm.items.isEmpty {
                Spacer(); ProgressView().tint(Theme.primary); Spacer()
            } else if vm.shown.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: vm.segment == .archived ? "archivebox" : "bubble.left.and.bubble.right")
                        .font(.system(size: 42)).symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.onFaint)
                    Text(vm.segment == .unread ? "لا محادثات غير مقروءة" : "لا توجد محادثات")
                        .foregroundStyle(Theme.onMuted)
                }
                Spacer()
            } else {
                List {
                    ForEach(vm.shown) { conv in
                        ZStack {
                            NavigationLink(value: conv) { EmptyView() }.opacity(0)
                            ConversationRow(conv: conv)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.background)
                        .listRowSeparatorTint(Theme.outline)
                        .onAppear { vm.loadMoreIfNeeded(after: conv) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await vm.delete(conv) } } label: {
                                Label("حذف", systemImage: "trash")
                            }
                            Button { Task { await vm.archive(conv) } } label: {
                                Label(vm.showArchived ? "إلغاء الأرشفة" : "أرشفة", systemImage: "archivebox")
                            }.tint(Theme.success)
                        }
                        .swipeActions(edge: .leading) {
                            Button { Task { await vm.pin(conv) } } label: {
                                Label(conv.isPinned ? "إلغاء التثبيت" : "تثبيت", systemImage: conv.isPinned ? "pin.slash" : "pin")
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
                        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.primary)
                    }
                    Text(conv.title).font(.system(size: 15.5, weight: .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Spacer()
                    Text(shortTime(conv.lastAt)).font(.caption2)
                        .foregroundStyle(conv.unread > 0 ? Theme.primary : Theme.onFaint)
                }
                HStack {
                    Text(conv.preview).font(.system(size: 13.5)).foregroundStyle(Theme.onMuted).lineLimit(1)
                    Spacer()
                    if conv.unread > 0 {
                        Text("\(conv.unread)").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.onPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.primary, in: Capsule())
                    }
                }
                if let acct = conv.instance?.label {
                    Text(acct).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
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
    if cal.isDateInYesterday(date) { return "أمس" }
    let f = DateFormatter(); f.dateFormat = "dd/MM"; return f.string(from: date)
}

private func flexibleDate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: s)
}

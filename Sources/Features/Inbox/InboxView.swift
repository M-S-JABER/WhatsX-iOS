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
    @Published var error: String?
    @Published var segment: InboxSegment = .active
    @Published var query = ""
    @Published var instances: [Instance] = []
    @Published var selectedInstanceIds: Set<String> = []

    var showArchived: Bool { segment == .archived }

    var shown: [Conversation] {
        var list = items
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.preview.localizedCaseInsensitiveContains(q) }
        }
        if segment == .unread { list = list.filter { $0.unread > 0 } }
        // Pinned conversations float to the top, preserving the backend order otherwise.
        return list.enumerated().sorted { a, b in
            if a.element.isPinned != b.element.isPinned { return a.element.isPinned }
            return a.offset < b.offset
        }.map { $0.element }
    }

    func select(_ seg: InboxSegment) {
        let crosses = (seg == .archived) != showArchived
        segment = seg
        if crosses { Task { await load() } }
    }

    /// Load the WhatsApp accounts once for the filter chips (multi-account inboxes).
    func loadInstances() async {
        instances = (try? await Api.shared.instances())?.items ?? []
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

    func load() async {
        loading = items.isEmpty
        error = nil
        let filter = selectedInstanceIds.isEmpty ? nil : selectedInstanceIds.sorted().joined(separator: ",")
        do {
            async let convTask = Api.shared.conversations(archived: showArchived, instanceIds: filter)
            async let pinsTask = Api.shared.pinnedConversationIds()
            let resp = try await convTask
            let pins = Set((try? await pinsTask) ?? [])
            // Stamp the pinned state onto each conversation so rows can sort/mark it.
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
                searchField
                segments
                if vm.instances.count > 1 { accountChips }
                content
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
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
            Text("المحادثات").font(.title2.bold()).foregroundStyle(Theme.onSurface)
            Spacer()
            Image(icon: .bell).font(.system(size: 20)).foregroundStyle(Theme.onMuted)
            Button { showNew = true } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(icon: .search).foregroundStyle(Theme.onMuted)
            TextField("ابحث في المحادثات", text: $vm.query)
                .foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12)
    }

    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(InboxSegment.allCases, id: \.self) { seg in
                let active = vm.segment == seg
                Button { vm.select(seg) } label: {
                    Text(seg.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(active ? Theme.primary : Theme.onMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(active ? Theme.surface : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.surface2, in: Capsule())
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    /// Multi-account filter (web parity: instance filter on Home) — shown only
    /// when the user can see more than one WhatsApp account.
    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("كل الحسابات", active: vm.selectedInstanceIds.isEmpty) { vm.toggleInstance(nil) }
                ForEach(vm.instances) { inst in
                    chip(inst.label, active: vm.selectedInstanceIds.contains(inst.id)) {
                        vm.toggleInstance(inst.id)
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 6)
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Theme.onPrimary : Theme.onMuted)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(active ? Theme.primary : Theme.surface2, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var content: some View {
        Group {
            if vm.loading && vm.items.isEmpty {
                Spacer(); ProgressView().tint(Theme.primary); Spacer()
            } else if vm.shown.isEmpty {
                Spacer()
                Text(vm.segment == .unread ? "لا محادثات غير مقروءة" : "لا توجد محادثات")
                    .foregroundStyle(Theme.onMuted)
                Spacer()
            } else {
                List(vm.shown) { conv in
                    ZStack {
                        NavigationLink(value: conv) { EmptyView() }.opacity(0)
                        ConversationRow(conv: conv)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Theme.background)
                    .listRowSeparatorTint(Theme.outline)
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
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationDestination(for: Conversation.self) { conv in
                    ChatView(conversation: conv)
                }
                .refreshable { await vm.load() }
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
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

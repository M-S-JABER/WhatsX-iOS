import SwiftUI

@MainActor
final class CallsViewModel: ObservableObject {
    @Published var items: [VoiceCall] = []
    @Published var loading = false
    @Published var filter = "all"           // quick direction chips
    @Published var search = ""
    @Published var instanceId: String? = nil
    @Published var agent: String? = nil
    @Published var hasRecording: Bool? = nil
    @Published var filters = VoiceCallFilters()

    func apply(_ f: String) { filter = f; Task { await load() } }
    func reload() { Task { await load() } }

    var advancedCount: Int {
        [instanceId != nil, agent != nil, hasRecording != nil].filter { $0 }.count
    }

    func load() async {
        loading = items.isEmpty
        let direction = filter == "in" ? "inbound" : (filter == "out" ? "outbound" : nil)
        let status = filter == "missed" ? "missed,rejected" : nil
        let q = search.trimmingCharacters(in: .whitespaces)
        do {
            items = try await Api.shared.voiceCalls(
                search: q.isEmpty ? nil : q, direction: direction, status: status,
                instanceId: instanceId, agent: agent, hasRecording: hasRecording).items
        } catch { }
        loading = false
    }

    func loadFilters() async {
        filters = (try? await Api.shared.voiceCallFilters()) ?? VoiceCallFilters()
    }

    func resetAdvanced() { instanceId = nil; agent = nil; hasRecording = nil }
}

struct CallsView: View {
    @StateObject private var vm = CallsViewModel()
    @State private var showSearch = false
    @State private var filterOpen = false
    private let chips = [("all", L("الكل")), ("in", L("واردة")), ("out", L("صادرة")), ("missed", L("فائتة"))]

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSearch { searchField }
            chipsRow
            content
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $filterOpen) { CallFilterSheet(vm: vm) }
        .task {
            await vm.load()
            await vm.loadFilters()
        }
        .onReceive(Realtime.shared.events) { event in
            guard RealtimeEvent.callEvents.contains(event.name) else { return }
            vm.reload()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(L("المكالمات")).font(.title2.bold()).foregroundStyle(Theme.onSurface)
            Spacer()
            Button { filterOpen = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(icon: .filter).font(.system(size: 20)).foregroundStyle(Theme.onMuted)
                    if vm.advancedCount > 0 {
                        Text("\(vm.advancedCount)").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 14, height: 14).background(Theme.primary, in: Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            Button { withAnimation { showSearch.toggle() }; if !showSearch { vm.search = ""; vm.reload() } } label: {
                Image(icon: showSearch ? .close : .search).font(.system(size: 20)).foregroundStyle(Theme.onMuted)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(icon: .search).foregroundStyle(Theme.onMuted)
            TextField(L("ابحث بالاسم أو الرقم"), text: $vm.search)
                .foregroundStyle(Theme.onSurface)
                .submitLabel(.search)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24))
        .padding(.horizontal, 12).padding(.bottom, 4)
        .onChange(of: vm.search) { _ in vm.reload() }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(chips, id: \.0) { key, label in
                    let active = vm.filter == key
                    Button { vm.apply(key) } label: {
                        Text(label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(active ? Theme.background : Theme.onMuted)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(active ? Theme.onSurface : Theme.surface2, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 14)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.items.isEmpty {
            Spacer(); ProgressView().tint(Theme.primary); Spacer()
        } else if vm.items.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "phone.and.waveform")
                    .font(.system(size: 42)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.onFaint)
                Text(L("لا مكالمات بعد")).foregroundStyle(Theme.onMuted)
            }
            Spacer()
        } else {
            List(vm.items) { call in
                CallRow(call: call)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Theme.background)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }
}

struct CallRow: View {
    let call: VoiceCall
    @State private var showPlayer = false
    private var dirIcon: WIcon { call.isMissed ? .callMissed : (call.isInbound ? .callIn : .callOut) }
    private var dirColor: Color { call.isMissed ? Theme.danger : (call.isInbound ? Theme.success : Theme.info) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 13) {
                Avatar(name: call.title, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(call.title).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(call.isMissed ? Theme.danger : Theme.onSurface).lineLimit(1)
                        Spacer()
                        Text(shortTime(call.startedAt)).font(.caption2).foregroundStyle(Theme.onMuted)
                    }
                    HStack(spacing: 6) {
                        Image(icon: dirIcon).font(.system(size: 13)).foregroundStyle(dirColor)
                        Text(statusText(call)).font(.system(size: 13.5)).foregroundStyle(Theme.onMuted).lineLimit(1)
                        if call.recordingPath != nil {
                            Image(icon: .history).font(.system(size: 11)).foregroundStyle(Theme.primary)
                        }
                    }
                }
                if call.recordingPath != nil {
                    Button { withAnimation { showPlayer.toggle() } } label: {
                        Image(icon: showPlayer ? .chevUp : .play).font(.system(size: 14)).foregroundStyle(Theme.primary)
                            .frame(width: 34, height: 34).background(Theme.primaryContainer, in: Circle())
                    }.buttonStyle(.plain)
                }
                if call.phone != nil {
                    Image(icon: .phoneCall).font(.system(size: 20)).foregroundStyle(Theme.primary)
                }
            }
            if showPlayer, let path = call.recordingPath, let url = Api.mediaURL(path) {
                AudioMessage(url: url, tint: Theme.onSurface)
                    .padding(.leading, 61)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func statusText(_ c: VoiceCall) -> String {
        let dur = c.durationSeconds > 0 ? " · \(c.durationSeconds / 60):\(String(format: "%02d", c.durationSeconds % 60))" : ""
        let base: String
        switch c.status {
        case "ended", "answered", "bridged": base = L("منتهية")
        case "missed": base = L("فائتة")
        case "rejected": base = L("مرفوضة")
        case "failed": base = L("فاشلة")
        default: base = c.status ?? ""
        }
        return base + dur
    }
}

// MARK: - Advanced filter sheet

struct CallFilterSheet: View {
    @ObservedObject var vm: CallsViewModel
    @Environment(\.dismiss) private var dismiss

    private var recSel: String { vm.hasRecording == true ? "yes" : (vm.hasRecording == false ? "no" : "all") }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("حساب واتساب")) {
                    Picker(L("الحساب"), selection: Binding(
                        get: { vm.instanceId ?? "" },
                        set: { vm.instanceId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(L("كل الحسابات")).tag("")
                        ForEach(vm.filters.accounts) { a in Text(a.label).tag(a.id) }
                    }
                }
                Section(L("الموظّف")) {
                    Picker(L("الموظّف"), selection: Binding(
                        get: { vm.agent ?? "" },
                        set: { vm.agent = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(L("كل الموظّفين")).tag("")
                        ForEach(vm.filters.agents, id: \.self) { a in Text(a).tag(a) }
                    }
                }
                Section(L("التسجيل")) {
                    Picker(L("التسجيل"), selection: Binding(
                        get: { recSel },
                        set: { v in vm.hasRecording = v == "yes" ? true : (v == "no" ? false : nil) }
                    )) {
                        Text(L("الكل")).tag("all")
                        Text(L("يحتوي تسجيلًا")).tag("yes")
                        Text(L("بدون تسجيل")).tag("no")
                    }.pickerStyle(.segmented)
                }
                Section {
                    Button(L("إعادة تعيين الفلاتر")) { vm.resetAdvanced() }.foregroundStyle(Theme.danger)
                }
            }
            .navigationTitle(L("تصفية المكالمات"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("تطبيق")) { vm.reload(); dismiss() } }
                ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

import SwiftUI

@MainActor
final class CallsViewModel: ObservableObject {
    @Published var items: [VoiceCall] = []
    @Published var loading = false
    @Published var filter = "all"           // segmented: all | missed
    @Published var search = ""
    @Published var instanceId: String? = nil
    @Published var agent: String? = nil
    @Published var hasRecording: Bool? = nil
    /// "inbound"/"outbound" — the 2.0 segmented keeps only all|missed, so
    /// direction moved into the advanced filter sheet.
    @Published var direction: String? = nil
    @Published var filters = VoiceCallFilters()

    private var realtimeReloadTask: Task<Void, Never>?

    func apply(_ f: String) { filter = f; Task { await load() } }
    func reload() { Task { await load() } }

    /// Coalesce realtime call-event bursts into a single refetch.
    func scheduleRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    var advancedCount: Int {
        [instanceId != nil, agent != nil, hasRecording != nil, direction != nil].filter { $0 }.count
    }

    func load() async {
        loading = items.isEmpty
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

    func resetAdvanced() { instanceId = nil; agent = nil; hasRecording = nil; direction = nil }
}

struct CallsView: View {
    @StateObject private var vm = CallsViewModel()
    @State private var showSearch = false
    @State private var filterOpen = false
    @Namespace private var segmentNamespace
    private let segments = [("all", L("الكل")), ("missed", L("الفائتة"))]

    var body: some View {
        VStack(spacing: 0) {
            header
            if showSearch { searchField }
            segmented
            content
        }
        .background(Theme.glowBackground())
        .sheet(isPresented: $filterOpen) { CallFilterSheet(vm: vm) }
        .task {
            await vm.load()
            await vm.loadFilters()
        }
        .onReceive(Realtime.shared.events) { event in
            guard RealtimeEvent.callEvents.contains(event.name) else { return }
            vm.scheduleRealtimeReload()
        }
    }

    /// 2.0 (design 4d): big title, phone-app style — advanced filters and
    /// search live behind glass circles.
    private var header: some View {
        HStack(spacing: 10) {
            Text(L("المكالمات")).font(.wx(30, .bold)).foregroundStyle(Theme.onSurface)
            Spacer()
            Button { filterOpen = true } label: {
                ZStack(alignment: .topTrailing) {
                    Image(icon: .filter).font(.wx(17, .semibold)).foregroundStyle(Theme.primary)
                        .frame(width: 42, height: 42)
                    if vm.advancedCount > 0 {
                        Text("\(vm.advancedCount)").font(.wx(9, .bold)).foregroundStyle(.white)
                            .frame(width: 15, height: 15).background(Theme.amberAction, in: Circle())
                            .offset(x: -3, y: 3)
                    }
                }
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(L("تصفية المكالمات"))
            Button { withAnimation { showSearch.toggle() }; if !showSearch { vm.search = ""; vm.reload() } } label: {
                Image(icon: showSearch ? .close : .search).font(.wx(17, .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.plain)
            .glassCircle()
            .accessibilityLabel(showSearch ? L("إغلاق البحث") : L("بحث"))
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
    }

    /// «الكل | الفائتة» — same floating-thumb segmented as the inbox.
    private var segmented: some View {
        HStack(spacing: 2) {
            ForEach(segments, id: \.0) { key, label in
                let active = vm.filter == key
                Button {
                    guard !active else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.apply(key) }
                } label: {
                    Text(label)
                        .font(.wx(13, active ? .semibold : .medium))
                        .foregroundStyle(active ? Theme.onSurface : Theme.onMuted)
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.segmentedActive)
                                    .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                                    .matchedGeometryEffect(id: "activeCallSegment", in: segmentNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .frame(width: 200)
        .background(Theme.segmentedTrack, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(icon: .search).foregroundStyle(Theme.onMuted)
            TextField(L("ابحث بالاسم أو الرقم"), text: $vm.search)
                .foregroundStyle(Theme.onSurface)
                .submitLabel(.search)
        }
        .padding(.horizontal, 14).frame(height: 44)
        .glassCapsule()
        .padding(.horizontal, 16).padding(.bottom, 10)
        .onChange(of: vm.search) { _ in vm.reload() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.items.isEmpty {
            Spacer(); ProgressView().tint(Theme.primary); Spacer()
        } else if vm.items.isEmpty {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "phone.and.waveform")
                    .font(.wx(42)).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.onFaint)
                Text(L("لا مكالمات بعد")).foregroundStyle(Theme.onMuted)
            }
            Spacer()
        } else {
            // Design 4d: the log sits on one glass panel (r20).
            List(vm.items) { call in
                CallRow(call: call)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Color(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.08))
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .glassCard(20)
            .padding(.horizontal, 12).padding(.bottom, 8)
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
                Avatar(name: call.title, size: 46)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(call.title).font(.wx(16, .semibold))
                            .foregroundStyle(call.isMissed ? Theme.missedCall : Theme.onSurface).lineLimit(1)
                        Spacer()
                        Text(shortTime(call.startedAt)).font(.wx(13)).foregroundStyle(Theme.onMuted)
                    }
                    HStack(spacing: 6) {
                        Image(icon: dirIcon).font(.wx(13)).foregroundStyle(dirColor)
                        Text(statusText(call)).font(.wx(13.5)).foregroundStyle(Theme.onMuted).lineLimit(1)
                        if call.recordingPath != nil {
                            Image(icon: .history).font(.wx(11)).foregroundStyle(Theme.primary)
                        }
                    }
                }
                if call.recordingPath != nil {
                    Button { withAnimation { showPlayer.toggle() } } label: {
                        Image(icon: showPlayer ? .chevUp : .play).font(.wx(14)).foregroundStyle(Theme.amberText)
                            .frame(width: 34, height: 34).background(Theme.surface1, in: Circle())
                    }.buttonStyle(.plain)
                }
                // Design 4d: tap-to-call-back (app builds with WebRTC only).
                if let phone = call.phone, !phone.isEmpty, CallCenter.shared.canCarryAudio {
                    Button {
                        Haptics.action()
                        CallCenter.shared.startOutbound(
                            to: phone.filter { $0.isNumber },
                            displayName: call.title, instanceId: nil)
                    } label: {
                        Image(icon: .phoneCall).font(.wx(15, .semibold)).foregroundStyle(Theme.amberText)
                            .frame(width: 34, height: 34).background(Theme.surface1, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L("معاودة الاتصال"))
                }
            }
            if showPlayer, let path = call.recordingPath, let url = Api.mediaURL(path) {
                AudioMessage(url: url, tint: Theme.onSurface)
                    .padding(.leading, 59)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
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
                Section(L("الاتجاه")) {
                    Picker(L("الاتجاه"), selection: Binding(
                        get: { vm.direction ?? "" },
                        set: { vm.direction = $0.isEmpty ? nil : $0 }
                    )) {
                        Text(L("الكل")).tag("")
                        Text(L("واردة")).tag("inbound")
                        Text(L("صادرة")).tag("outbound")
                    }.pickerStyle(.segmented)
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

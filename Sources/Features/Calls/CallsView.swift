import SwiftUI

@MainActor
final class CallsViewModel: ObservableObject {
    @Published var items: [VoiceCall] = []
    @Published var loading = false
    @Published var filter = "all"

    func apply(_ f: String) { filter = f; Task { await load() } }

    func load() async {
        loading = items.isEmpty
        let direction = filter == "in" ? "inbound" : (filter == "out" ? "outbound" : nil)
        let status = filter == "missed" ? "missed,rejected" : nil
        do { items = try await Api.shared.voiceCalls(direction: direction, status: status).items }
        catch { }
        loading = false
    }
}

struct CallsView: View {
    @StateObject private var vm = CallsViewModel()
    private let chips = [("all", "الكل"), ("in", "واردة"), ("out", "صادرة"), ("missed", "فائتة")]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("المكالمات").font(.title2.bold()).foregroundStyle(Theme.onSurface)
                Spacer()
                Image(icon: .search).font(.system(size: 20)).foregroundStyle(Theme.onMuted)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

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

            if vm.loading && vm.items.isEmpty {
                Spacer(); ProgressView().tint(Theme.primary); Spacer()
            } else if vm.items.isEmpty {
                Spacer(); Text("لا مكالمات بعد").foregroundStyle(Theme.onMuted); Spacer()
            } else {
                List(vm.items) { call in
                    CallRow(call: call)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Theme.background)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 84) }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await vm.load() }
    }
}

struct CallRow: View {
    let call: VoiceCall
    private var dirIcon: WIcon { call.isMissed ? .callMissed : (call.isInbound ? .callIn : .callOut) }
    private var dirColor: Color { call.isMissed ? Theme.danger : (call.isInbound ? Theme.success : Theme.info) }

    var body: some View {
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
                }
            }
            if call.phone != nil {
                Image(icon: .phoneCall).font(.system(size: 20)).foregroundStyle(Theme.primary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func statusText(_ c: VoiceCall) -> String {
        let dur = c.durationSeconds > 0 ? " · \(c.durationSeconds / 60):\(String(format: "%02d", c.durationSeconds % 60))" : ""
        let base: String
        switch c.status {
        case "ended", "answered", "bridged": base = "منتهية"
        case "missed": base = "فائتة"
        case "rejected": base = "مرفوضة"
        case "failed": base = "فاشلة"
        default: base = c.status ?? ""
        }
        return base + dur
    }
}

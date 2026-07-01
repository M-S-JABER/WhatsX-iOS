import SwiftUI

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var data: StatsResponse?
    @Published var loading = false
    @Published var range: String? = nil

    func apply(_ r: String?) { range = r; Task { await load() } }

    func load() async {
        loading = data == nil
        do { data = try await Api.shared.statistics(range: range) } catch { }
        loading = false
    }
}

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    private let ranges: [(String?, String)] = [(nil, "الكل"), ("24h", "24س"), ("7d", "7 أيام"), ("30d", "30 يومًا"), ("90d", "90 يومًا")]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("الإحصاءات").font(.title2.bold()).foregroundStyle(Theme.onSurface)
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)

                ScrollView {
                    VStack(spacing: 16) {
                        rangeChips
                        if let t = vm.data?.totals {
                            kpiGrid(t)
                        }
                        if let d = vm.data?.delivery {
                            statusCard(d)
                        }
                        if vm.loading && vm.data == nil { ProgressView().tint(Theme.primary).padding(.top, 40) }
                        reportsLink
                    }
                    .padding(16)
                    .padding(.bottom, 84)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .task { await vm.load() }
        }
    }

    private var reportsLink: some View {
        NavigationLink { CustomerReportsView() } label: {
            SettingRow(icon: .pdf, title: "تقارير العملاء", subtitle: "تقرير مفصّل لكل عميل", trailingChevron: true)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.outline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ranges, id: \.1) { key, label in
                    let active = vm.range == key
                    Button { vm.apply(key) } label: {
                        Text(label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(active ? Theme.background : Theme.onMuted)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(active ? Theme.onSurface : Theme.surface2, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func kpiGrid(_ t: StatTotals) -> some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                metric("المحادثات", "\(t.conversations)", Theme.onSurface)
                metric("الرسائل", "\(t.messages)", Theme.onSurface)
            }
            HStack(spacing: 11) {
                metric("الواردة", "\(t.incoming)", Theme.success)
                metric("الصادرة", "\(t.outgoing)", Theme.info)
            }
        }
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.onMuted)
            Text(value).font(.system(size: 28, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 15)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.outline, lineWidth: 1))
    }

    private func statusCard(_ d: Delivery) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("حالات الرسائل").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            HStack(spacing: 11) {
                statusTile("مُرسلة", d.sent, .check, Theme.onMuted)
                statusTile("مُسلّمة", d.delivered, .checkDouble, Theme.info)
            }
            HStack(spacing: 11) {
                statusTile("مقروءة", d.read, .checkDouble, Theme.info)
                statusTile("فاشلة", d.failed, .alert, Theme.danger)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.outline, lineWidth: 1))
    }

    private func statusTile(_ label: String, _ value: Int, _ icon: WIcon, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(icon: icon).font(.system(size: 13)).foregroundStyle(color)
                Text(label).font(.caption).foregroundStyle(color)
            }
            Text("\(value)").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }
}

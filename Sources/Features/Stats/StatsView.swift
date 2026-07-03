import SwiftUI

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var data: StatsResponse?
    @Published var loading = false
    @Published var range: String? = nil
    @Published var instanceId: String? = nil
    @Published var accounts: [Instance] = []

    func apply(_ r: String?) { range = r; Task { await load() } }
    func applyInstance(_ id: String?) { instanceId = id; Task { await load() } }

    func load() async {
        loading = data == nil
        do { data = try await Api.shared.statistics(range: range, instanceId: instanceId) } catch { }
        loading = false
    }

    func loadAccounts() async {
        accounts = (try? await Api.shared.instances())?.items ?? []
    }
}

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    private let ranges: [(String?, String)] = [(nil, "الكل"), ("24h", "24س"), ("7d", "7 أيام"), ("30d", "30 يومًا"), ("90d", "90 يومًا")]

    // Pushed inside the Settings navigation stack (no NavigationStack of its
    // own) — its NavigationLinks resolve against the enclosing stack.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    rangeChips
                    if vm.accounts.count > 1 { accountChips }
                    if let t = vm.data?.totals { kpiGrid(t) }
                    if let s = vm.data?.series, !s.isEmpty { seriesChart(s) }
                    if let d = vm.data?.delivery { statusCard(d) }
                    if let b = vm.data?.instanceBreakdown, b.count > 1 { instanceBreakdownCard(b) }
                    if let u = vm.data?.userStats, !u.isEmpty { userStatsCard(u) }
                    if vm.loading && vm.data == nil { ProgressView().tint(Theme.primary).padding(.top, 40) }
                    reportsLink
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("الإحصاءات")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await vm.load()
            await vm.loadAccounts()
        }
    }

    private var reportsLink: some View {
        NavigationLink { CustomerReportsView() } label: {
            SettingRow(icon: .pdf, title: "تقارير العملاء", subtitle: "تقرير مفصّل لكل عميل", trailingChevron: true, tint: Theme.info)
                .glassCard(22)
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

    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, "كل الحسابات")
                ForEach(vm.accounts) { a in chip(a.id, a.label) }
            }
        }
    }

    private func chip(_ id: String?, _ label: String) -> some View {
        let active = vm.instanceId == id
        return Button { vm.applyInstance(id) } label: {
            HStack(spacing: 5) {
                if let id { Circle().fill(AccountColor.color(id)).frame(width: 7, height: 7) }
                Text(label).font(.footnote.weight(.semibold))
            }
            .foregroundStyle(active ? Theme.onPrimary : Theme.onMuted)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? Theme.primary : Theme.surface2, in: Capsule())
        }.buttonStyle(.plain)
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
        .glassCard(20)
    }

    // MARK: - Time series (hand-rolled bar chart)

    private func seriesChart(_ points: [SeriesPoint]) -> some View {
        let maxV = max(points.map { max($0.incoming, $0.outgoing) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text("النشاط عبر الزمن").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            HStack(spacing: 14) {
                legend(Theme.success, "واردة")
                legend(Theme.info, "صادرة")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(points) { p in
                        VStack(spacing: 4) {
                            HStack(alignment: .bottom, spacing: 3) {
                                bar(CGFloat(p.incoming) / CGFloat(maxV), Theme.success)
                                bar(CGFloat(p.outgoing) / CGFloat(maxV), Theme.info)
                            }
                            .frame(height: 92, alignment: .bottom)
                            Text(bucketLabel(p.bucket)).font(.system(size: 8)).foregroundStyle(Theme.onFaint)
                                .frame(width: 26).lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func bar(_ frac: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3).fill(color)
            .frame(width: 10, height: max(3, frac * 92))
    }

    private func legend(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundStyle(Theme.onMuted)
        }
    }

    // MARK: - Delivery status

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
        .glassCard(22)
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

    // MARK: - Per-account breakdown

    private func instanceBreakdownCard(_ items: [StatInstance]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("حسب الحساب").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            ForEach(items) { inst in
                HStack(spacing: 10) {
                    Circle().fill(AccountColor.color(inst.id)).frame(width: 10, height: 10)
                    Text(inst.label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Spacer()
                    Text("\(inst.totals?.messages ?? 0) رسالة").font(.caption).foregroundStyle(Theme.onMuted)
                    Text("\(inst.totals?.conversations ?? 0) محادثة").font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    // MARK: - Agent performance

    private func userStatsCard(_ items: [UserStat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("أداء الموظفين").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            ForEach(Array(items.prefix(8))) { u in
                HStack(spacing: 12) {
                    Avatar(name: u.username, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(u.username).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                        Text("\(u.messagesSent) رسالة · \(u.conversationsCreated) محادثة")
                            .font(.caption2).foregroundStyle(Theme.onMuted)
                    }
                    Spacer()
                    if let avg = u.avgResponseSeconds {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(dur(Int(avg))).font(.caption.weight(.bold)).foregroundStyle(Theme.onSurface)
                            Text("زمن الرد").font(.system(size: 9)).foregroundStyle(Theme.onFaint)
                        }
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    // MARK: - Formatting

    private func dur(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)ث" }
        if seconds < 3600 { return "\(seconds / 60)د" }
        return "\(seconds / 3600)س"
    }

    private func bucketLabel(_ iso: String?) -> String {
        guard let iso else { return "" }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let date else { return "" }
        let f = DateFormatter(); f.dateFormat = "d/M"
        return f.string(from: date)
    }
}

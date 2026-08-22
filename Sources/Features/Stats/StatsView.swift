import SwiftUI

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var data: StatsResponse?
    @Published var loading = false
    @Published var loadError: String?
    @Published var range: String? = nil
    @Published var instanceId: String? = nil
    @Published var accounts: [Instance] = []

    func apply(_ r: String?) { range = r; Task { await load() } }
    func applyInstance(_ id: String?) { instanceId = id; Task { await load() } }

    func load() async {
        loading = data == nil
        do {
            data = try await Api.shared.statistics(range: range, instanceId: instanceId)
            loadError = nil
        } catch { loadError = error.apiMessage }
        loading = false
    }

    func loadAccounts() async {
        accounts = (try? await Api.shared.instances())?.items ?? []
    }
}

struct StatsView: View {
    @StateObject private var vm = StatsViewModel()
    @State private var exportURL: MediaItem?

    // Pushed inside the Settings navigation stack (no NavigationStack of its
    // own) — its NavigationLinks resolve against the enclosing stack.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                reportBody
                    .padding(16)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("الإحصاءات"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { exportPDF() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(vm.data == nil)
            }
        }
        .sheet(item: $exportURL) { item in
            ActivityShareSheet(items: [item.url])
        }
        .task {
            await vm.load()
            await vm.loadAccounts()
        }
    }

    /// The report content — shared between the screen and the PDF export.
    private var reportBody: some View {
        VStack(spacing: 16) {
            rangeChips
            if vm.accounts.count > 1 { accountChips }
            if let t = vm.data?.totals { kpiGrid(t) }
            if let s = vm.data?.series, !s.isEmpty { seriesChart(s) }
            if let d = vm.data?.delivery { statusCard(d) }
            if let b = vm.data?.instanceBreakdown, b.count > 1 { instanceBreakdownCard(b) }
            if let u = vm.data?.userStats, !u.isEmpty { userStatsCard(u) }
            if vm.loading && vm.data == nil { ProgressView().tint(Theme.primary).padding(.top, 40) }
            if !vm.loading, vm.data == nil, let err = vm.loadError {
                LoadFailedView(message: err) { Task { await vm.load() } }
            }
            reportsLink
        }
    }

    /// Render the on-screen report to a shareable PDF (web parity:
    /// Statistics.tsx exportPdf via jsPDF/html2canvas).
    @MainActor
    private func exportPDF() {
        let content = reportBody
            .padding(20)
            .frame(width: 640)
            .background(Theme.background)
            .environment(\.layoutDirection, L10n.isArabic ? .rightToLeft : .leftToRight)
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 640, height: nil)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("whatsx-statistics.pdf")
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        exportURL = MediaItem(url: url)
    }

    private var reportsLink: some View {
        NavigationLink { CustomerReportsView() } label: {
            SettingRow(icon: .pdf, title: L("تقارير العملاء"), subtitle: L("تقرير مفصّل لكل عميل"), trailingChevron: true, tint: Theme.info)
                .glassCard(22)
        }
        .buttonStyle(.plain)
    }

    private var rangeChips: some View {
        RangeChipsRow(selected: vm.range) { vm.apply($0) }
    }

    private var accountChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                chip(nil, L("كل الحسابات"))
                ForEach(vm.accounts) { a in chip(a.id, a.label) }
            }
        }
    }

    private func chip(_ id: String?, _ label: String) -> some View {
        let active = vm.instanceId == id
        return Button { vm.applyInstance(id) } label: {
            HStack(spacing: 5) {
                if let id { Circle().fill(AccountColor.color(id)).frame(width: 7, height: 7) }
                Text(label).font(.wx(13, .semibold))
            }
            .foregroundStyle(active ? Theme.onPrimary : Theme.onMuted)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(active ? Theme.primary : Theme.surface2, in: Capsule())
        }.buttonStyle(.plain)
    }

    /// Design 4e: TWO KPI cards — messages (with the colored in/out
    /// secondary line) and conversations.
    private func kpiGrid(_ t: StatTotals) -> some View {
        HStack(spacing: 11) {
            kpiCard(L("الرسائل"), "\(t.messages)") {
                HStack(spacing: 8) {
                    Text("↓ \(t.incoming)").font(.wx(12, .semibold)).foregroundStyle(Theme.success)
                    Text("↑ \(t.outgoing)").font(.wx(12, .semibold)).foregroundStyle(Theme.info)
                }
            }
            kpiCard(L("المحادثات"), "\(t.conversations)") {
                Text(L("خلال المدة المحددة")).font(.wx(12)).foregroundStyle(Theme.onFaint)
            }
        }
    }

    private func kpiCard(_ label: String, _ value: String,
                         @ViewBuilder secondary: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.wx(12.5, .semibold)).foregroundStyle(Theme.onMuted)
            Text(value).font(.wx(30, .bold)).foregroundStyle(Theme.onSurface)
                .monospacedDigit()
            secondary()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassCard(Theme.Radius.cardTight)
    }

    // MARK: - Time series (hand-rolled bar chart)

    private func seriesChart(_ points: [SeriesPoint]) -> some View {
        let maxV = max(points.map { max($0.incoming, $0.outgoing) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("النشاط عبر الزمن")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            HStack(spacing: 14) {
                legend(Theme.success, L("واردة"))
                legend(Theme.chartBeige, L("صادرة"))
            }
            // Busiest bucket gets the amber highlight (design 4e); labels
            // stay >= 11pt per the handoff's floor.
            let busiest = points.max(by: { ($0.incoming + $0.outgoing) < ($1.incoming + $1.outgoing) })?.id
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(points) { p in
                        VStack(spacing: 4) {
                            HStack(alignment: .bottom, spacing: 3) {
                                bar(CGFloat(p.incoming) / CGFloat(maxV), Theme.success)
                                bar(CGFloat(p.outgoing) / CGFloat(maxV), Theme.chartBeige)
                            }
                            .frame(height: 92, alignment: .bottom)
                            Text(bucketLabel(p.bucket))
                                .font(.wx(11, p.id == busiest ? .bold : .regular))
                                .foregroundStyle(p.id == busiest ? Theme.amberText : Theme.onFaint)
                                .frame(width: 30).lineLimit(1)
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
            Text(label).font(.wx(11)).foregroundStyle(Theme.onMuted)
        }
    }

    // MARK: - Delivery status

    /// Design 4e: «التسليم» is ONE proportional bar (read / delivered /
    /// sent / failed) with a compact key — four tiles collapse into it.
    private func statusCard(_ d: Delivery) -> some View {
        let segments: [(String, Int, Color)] = [
            (L("مقروءة"), d.read, Theme.success),
            (L("مُسلّمة"), d.delivered, Theme.chartBeigeMid),
            (L("مُرسلة"), d.sent, Theme.chartBeige),
            (L("فاشلة"), d.failed, Theme.danger),
        ]
        let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("التسليم")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        if seg.1 > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(seg.2)
                                .frame(width: max(geo.size.width * CGFloat(seg.1) / CGFloat(total) - 2, 4))
                        }
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    HStack(spacing: 4) {
                        Circle().fill(seg.2).frame(width: 8, height: 8)
                        Text("\(seg.0) \(seg.1)").font(.wx(12.5)).foregroundStyle(Theme.onMuted)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    // MARK: - Per-account breakdown

    private func instanceBreakdownCard(_ items: [StatInstance]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("حسب الحساب")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            ForEach(items) { inst in
                HStack(spacing: 10) {
                    Circle().fill(AccountColor.color(inst.id)).frame(width: 10, height: 10)
                    Text(inst.label).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                    Spacer()
                    Text("\(inst.totals?.messages ?? 0) " + L("رسالة")).font(.wx(12)).foregroundStyle(Theme.onMuted)
                    Text("\(inst.totals?.conversations ?? 0) " + L("محادثة")).font(.wx(12, .semibold)).foregroundStyle(Theme.primary)
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
            Text(L("أداء الموظفين")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            ForEach(Array(items.prefix(8))) { u in
                HStack(spacing: 12) {
                    Avatar(name: u.username, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(u.username).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                        Text("\(u.messagesSent) " + L("رسالة") + " · \(u.conversationsCreated) " + L("محادثة"))
                            .font(.wx(11)).foregroundStyle(Theme.onMuted)
                    }
                    Spacer()
                    if let avg = u.avgResponseSeconds {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(dur(Int(avg))).font(.wx(12, .bold)).foregroundStyle(Theme.onSurface)
                            Text(L("زمن الرد")).font(.wx(9)).foregroundStyle(Theme.onFaint)
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
        if seconds < 60 { return "\(seconds)" + L("ث") }
        if seconds < 3600 { return "\(seconds / 60)" + L("د") }
        return "\(seconds / 3600)" + L("س")
    }

    private func bucketLabel(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "d/M"
        return f.string(from: date)
    }
}

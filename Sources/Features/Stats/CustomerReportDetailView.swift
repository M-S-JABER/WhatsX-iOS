import SwiftUI

// Full per-customer report: totals, response-time stats, message-status breakdown,
// per-agent contribution, and a recent message timeline.
// Backed by GET /api/statistics/customer-report?conversationId=&range=.
struct CustomerReportDetailView: View {
    let conversationId: String
    let title: String

    @State private var report: CustomerReport?
    @State private var loading = true
    @State private var range: String? = nil


    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                rangeChips
                if loading && report == nil {
                    ProgressView().tint(Theme.primary).padding(.top, 40)
                } else if let r = report {
                    header(r)
                    totalsGrid(r.totals)
                    if let rs = r.responseStats { responseCard(rs) }
                    if let sb = r.statusBreakdown, !sb.isEmpty { statusCard(sb) }
                    if !r.agents.isEmpty { agentsCard(r.agents) }
                    if !r.timeline.isEmpty { timelineCard(r.timeline) }
                } else {
                    Text(L("لا بيانات")).foregroundStyle(Theme.onMuted).padding(.top, 40)
                }
            }
            .padding(16).padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = report == nil
        do { report = try await Api.shared.customerReport(conversationId: conversationId, range: range) }
        catch { }
        loading = false
    }

    private func apply(_ r: String?) { range = r; Task { await load() } }

    // MARK: - Sections

    private var rangeChips: some View {
        RangeChipsRow(selected: range) { apply($0) }
    }

    private func header(_ r: CustomerReport) -> some View {
        HStack(spacing: 13) {
            Avatar(name: r.conversation?.title ?? title, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.conversation?.title ?? title).font(.wx(16, .bold)).foregroundStyle(Theme.onSurface)
                let sub = [r.conversation?.phone, r.conversation?.instanceName].compactMap { $0 }.filter { !$0.isEmpty }
                if !sub.isEmpty {
                    Text(sub.joined(separator: " · ")).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func totalsGrid(_ t: CustomerReportTotals?) -> some View {
        let t = t ?? CustomerReportTotals()
        return VStack(spacing: 11) {
            HStack(spacing: 11) {
                metric(L("الرسائل"), "\(t.messages)", Theme.onSurface)
                metric(L("الواردة"), "\(t.incoming)", Theme.success)
                metric(L("الصادرة"), "\(t.outgoing)", Theme.info)
            }
            HStack(spacing: 11) {
                infoTile(L("أول رسالة"), relTime(t.firstAt))
                infoTile(L("آخر رسالة"), relTime(t.lastAt))
            }
        }
    }

    private func responseCard(_ rs: CustomerReportResponseStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("زمن الاستجابة")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            HStack(spacing: 11) {
                statTile(L("المتوسّط"), dur(rs.avgSeconds), Theme.primary)
                statTile(L("الأسرع"), dur(rs.minSeconds), Theme.success)
                statTile(L("الأبطأ"), dur(rs.maxSeconds), Theme.danger)
            }
            Text(L("عدد الردود المحسوبة:") + " \(rs.count)").font(.wx(12)).foregroundStyle(Theme.onFaint)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func statusCard(_ sb: [String: Int]) -> some View {
        let order: [(String, String, Color)] = [
            ("sent", L("مُرسلة"), Theme.onMuted), ("delivered", L("مُسلّمة"), Theme.info),
            ("read", L("مقروءة"), Theme.info), ("failed", L("فاشلة"), Theme.danger),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text(L("حالات الرسائل")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            HStack(spacing: 11) {
                ForEach(order, id: \.0) { key, label, color in
                    statTile(label, "\(sb[key] ?? 0)", color)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func agentsCard(_ agents: [CustomerReportAgent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("مساهمة الموظفين")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            ForEach(agents) { a in
                HStack(spacing: 12) {
                    Avatar(name: a.username, size: 34)
                    Text(a.username).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                    Spacer()
                    Text("\(a.sent) " + L("رسالة")).font(.wx(12)).foregroundStyle(Theme.onMuted)
                    Text("\(a.replies) " + (L10n.isArabic ? "رد" : "replies")).font(.wx(12, .semibold)).foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.primaryContainer, in: Capsule())
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func timelineCard(_ items: [CustomerReportTimelineItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("آخر الرسائل")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            ForEach(items) { m in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(m.isOutbound ? Theme.info : Theme.success).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.body?.isEmpty == false ? m.body! : (m.isOutbound ? L("رسالة صادرة") : L("رسالة واردة")))
                            .font(.wx(13.5)).foregroundStyle(Theme.onSurface).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(hm(m.createdAt)).font(.wx(11)).foregroundStyle(Theme.onFaint)
                            if let u = m.sentByUsername, !u.isEmpty {
                                Text("· \(u)").font(.wx(11)).foregroundStyle(Theme.onFaint)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    // MARK: - Tiles

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        MetricTile(label: label, value: value, color: color)
    }

    private func statTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.wx(11)).foregroundStyle(color)
            Text(value).font(.wx(16, .bold)).foregroundStyle(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }

    private func infoTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.wx(12)).foregroundStyle(Theme.onMuted)
            Text(value).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(18)
    }

    // MARK: - Formatting

    private func dur(_ seconds: Int?) -> String {
        guard let s = seconds else { return "—" }
        if s < 60 { return "\(s)" + L("ث") }
        if s < 3600 { return "\(s / 60)" + L("د") }
        if s < 86400 { return "\(s / 3600)" + L("س") }
        return "\(s / 86400)" + L("ي")
    }

    private func relTime(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "—" }
        let f = DateFormatter(); f.locale = L10n.dateLocale; f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private func hm(_ iso: String?) -> String { clockTime(iso) }
}

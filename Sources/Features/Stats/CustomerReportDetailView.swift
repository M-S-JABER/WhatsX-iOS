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

    private let ranges: [(String?, String)] = [
        (nil, "الكل"), ("24h", "24س"), ("7d", "7 أيام"), ("30d", "30 يومًا"), ("90d", "90 يومًا"),
    ]

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
                    Text("لا بيانات").foregroundStyle(Theme.onMuted).padding(.top, 40)
                }
            }
            .padding(16).padding(.bottom, 84)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(ranges, id: \.1) { key, label in
                    let active = range == key
                    Button { apply(key) } label: {
                        Text(label).font(.subheadline.weight(.semibold))
                            .foregroundStyle(active ? Theme.background : Theme.onMuted)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(active ? Theme.onSurface : Theme.surface2, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func header(_ r: CustomerReport) -> some View {
        HStack(spacing: 13) {
            Avatar(name: r.conversation?.title ?? title, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(r.conversation?.title ?? title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.onSurface)
                let sub = [r.conversation?.phone, r.conversation?.instanceName].compactMap { $0 }.filter { !$0.isEmpty }
                if !sub.isEmpty {
                    Text(sub.joined(separator: " · ")).font(.caption).foregroundStyle(Theme.onMuted).lineLimit(1)
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
                metric("الرسائل", "\(t.messages)", Theme.onSurface)
                metric("الواردة", "\(t.incoming)", Theme.success)
                metric("الصادرة", "\(t.outgoing)", Theme.info)
            }
            HStack(spacing: 11) {
                infoTile("أول رسالة", relTime(t.firstAt))
                infoTile("آخر رسالة", relTime(t.lastAt))
            }
        }
    }

    private func responseCard(_ rs: CustomerReportResponseStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("زمن الاستجابة").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            HStack(spacing: 11) {
                statTile("المتوسّط", dur(rs.avgSeconds), Theme.primary)
                statTile("الأسرع", dur(rs.minSeconds), Theme.success)
                statTile("الأبطأ", dur(rs.maxSeconds), Theme.danger)
            }
            Text("عدد الردود المحسوبة: \(rs.count)").font(.caption).foregroundStyle(Theme.onFaint)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(22)
    }

    private func statusCard(_ sb: [String: Int]) -> some View {
        let order: [(String, String, Color)] = [
            ("sent", "مُرسلة", Theme.onMuted), ("delivered", "مُسلّمة", Theme.info),
            ("read", "مقروءة", Theme.info), ("failed", "فاشلة", Theme.danger),
        ]
        return VStack(alignment: .leading, spacing: 12) {
            Text("حالات الرسائل").font(.callout.bold()).foregroundStyle(Theme.onMuted)
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
            Text("مساهمة الموظفين").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            ForEach(agents) { a in
                HStack(spacing: 12) {
                    Avatar(name: a.username, size: 34)
                    Text(a.username).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                    Spacer()
                    Text("\(a.sent) رسالة").font(.caption).foregroundStyle(Theme.onMuted)
                    Text("\(a.replies) رد").font(.caption.weight(.semibold)).foregroundStyle(Theme.primary)
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
            Text("آخر الرسائل").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            ForEach(items) { m in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(m.isOutbound ? Theme.info : Theme.success).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.body?.isEmpty == false ? m.body! : (m.isOutbound ? "رسالة صادرة" : "رسالة واردة"))
                            .font(.system(size: 13.5)).foregroundStyle(Theme.onSurface).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(hm(m.createdAt)).font(.caption2).foregroundStyle(Theme.onFaint)
                            if let u = m.sentByUsername, !u.isEmpty {
                                Text("· \(u)").font(.caption2).foregroundStyle(Theme.onFaint)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.onMuted)
            Text(value).font(.system(size: 24, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 14)
        .glassCard(18)
    }

    private func statTile(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(color)
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }

    private func infoTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.onMuted)
            Text(value).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard(18)
    }

    // MARK: - Formatting

    private func dur(_ seconds: Int?) -> String {
        guard let s = seconds else { return "—" }
        if s < 60 { return "\(s)ث" }
        if s < 3600 { return "\(s / 60)د" }
        if s < 86400 { return "\(s / 3600)س" }
        return "\(s / 86400)ي"
    }

    private func relTime(_ iso: String?) -> String {
        guard let date = parseISO(iso) else { return "—" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ar"); f.dateFormat = "dd/MM/yyyy"
        return f.string(from: date)
    }

    private func hm(_ iso: String?) -> String {
        guard let date = parseISO(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private func parseISO(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

import SwiftUI

enum IntegTab: String, CaseIterable {
    case overview, external, flow, logs
    var title: String {
        switch self {
        case .overview: return "نظرة عامة"; case .external: return "الأنظمة"
        case .flow: return "التدفّق"; case .logs: return "السجلّ"
        }
    }
}

@MainActor
final class IntegrationsViewModel: ObservableObject {
    @Published var overview: IntegrationsOverview?
    @Published var monitor: [IntegrationMonitorItem] = []
    @Published var integrations: [PublicIntegration] = []
    @Published var logs: [IntegrationLog] = []
    @Published var flow: [MessageFlowEvent] = []
    @Published var loading = false

    func loadOverview() async {
        do { overview = try await Api.shared.integrationsOverview() } catch {}
        await loadMonitor()
    }
    func loadMonitor() async {
        do { monitor = try await Api.shared.integrationMonitorMessages().items } catch {}
    }
    func loadIntegrations() async { do { integrations = try await Api.shared.integrations().items } catch {} }
    func loadLogs() async { do { logs = try await Api.shared.integrationLogs().items } catch {} }
    func loadFlow() async { do { flow = try await Api.shared.messageFlow().items } catch {} }
    func retry(_ id: String) async {
        _ = try? await Api.shared.retryMessageFlow(id)
        await loadFlow()
    }

    func test(_ id: String) async { try? await Api.shared.integrationTest(id) }
    func toggle(_ item: PublicIntegration) async {
        if item.isEnabled { try? await Api.shared.integrationDisable(item.id) }
        else { try? await Api.shared.integrationEnable(item.id) }
        await loadIntegrations()
    }
    func delete(_ id: String) async {
        try? await Api.shared.deleteIntegration(id)
        await loadIntegrations()
    }
}

struct IntegrationsView: View {
    @StateObject private var vm = IntegrationsViewModel()
    @State private var tab: IntegTab = .overview
    @State private var editing: PublicIntegration?
    @State private var showForm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("التكاملات").font(.title2.bold()).foregroundStyle(Theme.onSurface)
                Spacer()
                if tab == .external {
                    Image(icon: .add).font(.system(size: 20)).foregroundStyle(Theme.primary)
                        .onTapGesture { editing = nil; showForm = true }
                }
                Image(icon: .refresh).font(.system(size: 20)).foregroundStyle(Theme.onMuted)
                    .onTapGesture { Task { await reload() } }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)

            tabbar

            ScrollView {
                VStack(spacing: 14) {
                    switch tab {
                    case .overview: overviewTab
                    case .external: externalTab
                    case .flow: flowTab
                    case .logs: logsTab
                    }
                }
                .padding(14).padding(.bottom, 24)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task { await reload() }
        .onReceive(Realtime.shared.events) { event in
            guard event.name == "integration_message_created" || event.name == "integration_message_status" else { return }
            Task { await vm.loadMonitor() }
        }
        .sheet(isPresented: $showForm) {
            IntegrationFormSheet(integration: editing) { await vm.loadIntegrations() }
        }
    }

    private var tabbar: some View {
        HStack(spacing: 4) {
            ForEach(IntegTab.allCases, id: \.self) { t in
                let active = tab == t
                Button { tab = t; Task { await reload() } } label: {
                    VStack(spacing: 6) {
                        Text(t.title).font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(active ? Theme.onSurface : Theme.onMuted)
                        Rectangle().fill(active ? Theme.primary : .clear).frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .overlay(Rectangle().fill(Theme.outline).frame(height: 1), alignment: .bottom)
    }

    private func reload() async {
        switch tab {
        case .overview: await vm.loadOverview()
        case .external: await vm.loadIntegrations()
        case .flow: await vm.loadFlow()
        case .logs: await vm.loadLogs()
        }
    }

    // MARK: Overview
    @ViewBuilder private var overviewTab: some View {
        if let s = vm.overview?.summary {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                metric("التكاملات", "\(s.totalIntegrations)", Theme.onSurface)
                metric("حسابات متصلة", "\(s.whatsappAccountsConnected)", Theme.onSurface)
                metric("نجاح Webhook", fmtRate(s.webhookSuccessRate), Theme.success)
                metric("إخفاقات", "\(s.failedIntegrations)", Theme.warning)
            }
        }
        if let h = vm.overview?.health {
            Text("صحّة الأرقام").font(.callout.bold()).foregroundStyle(Theme.onMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                healthTile("سليمة", h.healthy, Theme.success)
                healthTile("تحذير", h.warning, Theme.warning)
                healthTile("منقطعة", h.disconnected, Theme.danger)
                healthTile("فاشلة", h.failed, Theme.danger)
            }
        }
        if vm.overview == nil { ProgressView().tint(Theme.primary).padding(.top, 40) }

        // Template sends pushed by external systems (web parity: the
        // integration monitor list on the Overview tab).
        Text("قوالب النظام الخارجي").font(.callout.bold()).foregroundStyle(Theme.onMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        if vm.monitor.isEmpty {
            Text("لا رسائل من الأنظمة الخارجية بعد")
                .font(.subheadline).foregroundStyle(Theme.onMuted)
                .frame(maxWidth: .infinity).padding(.vertical, 18)
                .glassCard(16)
        } else {
            ForEach(vm.monitor) { m in monitorRow(m) }
        }
    }

    private func monitorRow(_ m: IntegrationMonitorItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(m.name?.isEmpty == false ? m.name! : (m.phone ?? "—"))
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                Spacer()
                monitorStatusBadge(m.status)
            }
            HStack(spacing: 6) {
                Image(icon: .template).font(.system(size: 12)).foregroundStyle(Theme.primary)
                Text([m.templateName, m.templateLanguage].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.onMuted).lineLimit(1)
            }
            HStack {
                if let phone = m.phone, m.name?.isEmpty == false {
                    Text(phone).font(.caption2).foregroundStyle(Theme.onFaint)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer()
                if let acct = m.instance?.label {
                    Text(acct).font(.caption2).foregroundStyle(Theme.onFaint).lineLimit(1)
                }
                Text(monitorTime(m.createdAt)).font(.caption2).foregroundStyle(Theme.onFaint)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(16)
    }

    private func monitorStatusBadge(_ status: String?) -> some View {
        let s = (status ?? "").lowercased()
        let color: Color = s.contains("fail") || s.contains("error") || s.contains("reject") ? Theme.danger
            : s.contains("read") ? Theme.info
            : s.contains("deliver") || s.contains("sent") || s.contains("accept") ? Theme.success
            : Theme.warning
        return Text(status ?? "—")
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.13), in: Capsule())
    }

    private func monitorTime(_ iso: String?) -> String {
        guard let date = parseISODate(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "d/M HH:mm"
        return f.string(from: date)
    }

    private func metric(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.onMuted)
            Text(value).font(.system(size: 26, weight: .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassCard(20)
    }

    private func healthTile(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.subheadline).foregroundStyle(Theme.onMuted)
            Spacer()
            Text("\(value)").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }

    // MARK: External
    @ViewBuilder private var externalTab: some View {
        if vm.integrations.isEmpty {
            Text("لا أنظمة خارجية").foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            ForEach(vm.integrations) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(icon: .webhook).foregroundStyle(Theme.onSurface)
                            .frame(width: 40, height: 40)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.onSurface)
                            if let url = item.endpoint ?? item.baseUrl { Text(url).font(.caption).foregroundStyle(Theme.onMuted).lineLimit(1) }
                        }
                        Spacer()
                        healthChip(item.health)
                    }
                    if let err = item.lastErrorMessage, !err.isEmpty {
                        Text(err).font(.caption).foregroundStyle(Theme.danger).lineLimit(2)
                    }
                    HStack(spacing: 7) {
                        Text(item.isEnabled ? "مُفعّل" : "مُعطّل").font(.caption).foregroundStyle(Theme.onMuted)
                        Spacer()
                        Button { editing = item; showForm = true } label: {
                            Image(icon: .edit).font(.system(size: 15))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.outline, lineWidth: 1))
                                .foregroundStyle(Theme.onSurface)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.delete(item.id) } } label: {
                            Image(icon: .trash).font(.system(size: 15))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.outline, lineWidth: 1))
                                .foregroundStyle(Theme.danger)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.test(item.id) } } label: {
                            Text("اختبار").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.onSurface)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.toggle(item) } } label: {
                            Text(item.isEnabled ? "تعطيل" : "تفعيل").font(.footnote.weight(.semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.outline, lineWidth: 1))
                                .foregroundStyle(Theme.onSurface)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(22)
            }
        }
    }

    private func healthChip(_ health: String) -> some View {
        let (label, color): (String, Color) = {
            switch health {
            case "healthy": return ("سليمة", Theme.success)
            case "warning": return ("تحذير", Theme.warning)
            case "failed", "disconnected": return ("منقطعة", Theme.danger)
            default: return ("تهيئة", Theme.onMuted)
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Message flow
    @ViewBuilder private var flowTab: some View {
        if vm.flow.isEmpty {
            Text("لا أحداث تدفّق").foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            ForEach(vm.flow) { e in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(icon: e.direction == "inbound" ? .callIn : .callOut).font(.system(size: 14))
                            .foregroundStyle(e.direction == "inbound" ? Theme.success : Theme.info)
                        Text(e.eventType ?? "حدث").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                        Spacer()
                        flowStatusChip(e.status)
                    }
                    if let s = e.source, let d = e.destination, !(s.isEmpty && d.isEmpty) {
                        Text("\(s) ← \(d)").font(.caption2).foregroundStyle(Theme.onMuted).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        if let c = e.responseCode { Text("HTTP \(c)").font(.caption2).foregroundStyle(Theme.onFaint) }
                        if let l = e.latencyMs { Text("\(l)ms").font(.caption2).foregroundStyle(Theme.onFaint) }
                        Spacer()
                        Text(shortTime(e.timestamp)).font(.caption2).foregroundStyle(Theme.onFaint)
                    }
                    if let err = e.errorMessage, !err.isEmpty {
                        Text(err).font(.caption).foregroundStyle(Theme.danger).lineLimit(2)
                    }
                    if e.isRetryable {
                        HStack {
                            Spacer()
                            Button { Task { await vm.retry(e.id) } } label: {
                                HStack(spacing: 5) {
                                    Image(icon: .refresh).font(.system(size: 12))
                                    Text("إعادة المحاولة").font(.footnote.weight(.semibold))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.primaryContainer, in: Capsule())
                                .foregroundStyle(Theme.primary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(15).frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(20)
            }
        }
    }

    private func flowStatusChip(_ status: String?) -> some View {
        let s = (status ?? "").lowercased()
        let (label, color): (String, Color) = {
            switch s {
            case "delivered", "sent", "success", "ok": return (status ?? "", Theme.success)
            case "failed", "error": return (status ?? "", Theme.danger)
            case "retry", "scheduled", "pending": return (status ?? "", Theme.warning)
            default: return (status ?? "—", Theme.info)
            }
        }()
        return Text(label.isEmpty ? "—" : label)
            .font(.caption2.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Logs
    @ViewBuilder private var logsTab: some View {
        if vm.logs.isEmpty {
            Text("لا سجلّات").foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(vm.logs.enumerated()), id: \.element.id) { idx, log in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(sevColor(log.severity)).frame(width: 9, height: 9).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.component).font(.system(size: 13, weight: .semibold)).monospaced().foregroundStyle(Theme.onSurface)
                            Text(log.summary).font(.caption).foregroundStyle(Theme.onMuted)
                        }
                        Spacer()
                        Text(shortTime(log.timestamp)).font(.caption2).foregroundStyle(Theme.onFaint)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 13)
                    if idx < vm.logs.count - 1 { Rectangle().fill(Theme.outline).frame(height: 1).padding(.leading, 16) }
                }
            }
            .glassCard(24)
        }
    }

    private func sevColor(_ s: String) -> Color {
        switch s { case "success": return Theme.success; case "warning": return Theme.warning
        case "error", "critical": return Theme.danger; default: return Theme.info }
    }
}

// MARK: - Form Sheet

struct IntegrationFormSheet: View {
    let integration: PublicIntegration?
    let onSaved: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var baseUrl = ""
    @State private var endpoint = ""
    @State private var authType = "none"
    @State private var timeout = "10000"
    @State private var enabled = true
    @State private var saving = false
    @State private var error: String?

    private var isEditing: Bool { integration != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("الاسم", text: $name)
                TextField("رابط الأساس", text: $baseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("المسار", text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("المصادقة", selection: $authType) {
                    Text("بدون").tag("none")
                    Text("Bearer").tag("bearer")
                    Text("مفتاح API").tag("api_key")
                }
                TextField("المهلة (مللي ثانية)", text: $timeout)
                    .keyboardType(.numberPad)
                Toggle("مُفعّل", isOn: $enabled)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(isEditing ? "تعديل النظام" : "نظام جديد")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { Task { await save() } }
                        .disabled(saving || name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            if let it = integration {
                name = it.name
                baseUrl = it.baseUrl ?? ""
                endpoint = it.endpoint ?? ""
                authType = it.authType ?? "none"
                enabled = it.isEnabled
            }
        }
    }

    private func save() async {
        saving = true; error = nil
        let trimmedBase = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let it = integration {
                _ = try await Api.shared.updateIntegration(it.id, UpdateIntegrationRequest(
                    name: name,
                    baseUrl: trimmedBase.isEmpty ? nil : trimmedBase,
                    endpoint: trimmedEndpoint.isEmpty ? nil : trimmedEndpoint,
                    authType: authType,
                    timeoutMs: Int(timeout),
                    isEnabled: enabled
                ))
            } else {
                _ = try await Api.shared.createIntegration(CreateIntegrationRequest(
                    name: name,
                    baseUrl: trimmedBase.isEmpty ? nil : trimmedBase,
                    endpoint: trimmedEndpoint.isEmpty ? nil : trimmedEndpoint,
                    authType: authType,
                    timeoutMs: Int(timeout),
                    isEnabled: enabled
                ))
            }
            await onSaved()
            dismiss()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        saving = false
    }
}

func fmtRate(_ rate: Double?) -> String {
    guard let rate else { return "—" }
    let pct = rate <= 1.0 ? rate * 100 : rate
    return "\(Int(pct))%"
}

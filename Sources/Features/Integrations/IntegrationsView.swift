import SwiftUI

enum IntegTab: String, CaseIterable {
    case overview, external, flow, webhook, logs
    var title: String {
        switch self {
        case .overview: return L("نظرة عامة"); case .external: return L("الأنظمة")
        case .flow: return L("التدفّق"); case .webhook: return "Webhook"
        case .logs: return L("السجلّ")
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
    @Published var webhook: WebhookCenter?
    @Published var webhookPath = ""
    @Published var webhookToken = ""
    @Published var loading = false
    /// Failure message of the current tab's last load (nil = loaded fine).
    @Published var loadError: String?

    func loadWebhook() async {
        do {
            webhook = try await Api.shared.webhookCenter()
            loadError = nil
        } catch {
            loadError = error.apiMessage
        }
        if let config = try? await Api.shared.webhookConfig() {
            webhookPath = config.path ?? webhook?.metaWebhookPath ?? ""
            webhookToken = config.verifyToken ?? ""
        } else {
            webhookPath = webhook?.metaWebhookPath ?? ""
        }
    }

    /// Returns nil on success, or the error message.
    func saveWebhook() async -> String? {
        do {
            _ = try await Api.shared.updateWebhookConfig(
                path: webhookPath,
                verifyToken: webhookToken.isEmpty ? nil : webhookToken)
            await loadWebhook()
            return nil
        } catch {
            return (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func loadOverview() async {
        do { overview = try await Api.shared.integrationsOverview(); loadError = nil }
        catch { loadError = error.apiMessage }
        await loadMonitor()
    }
    /// Secondary list on the overview tab — its own empty state covers it.
    func loadMonitor() async {
        do { monitor = try await Api.shared.integrationMonitorMessages().items } catch {}
    }
    func loadIntegrations() async {
        do { integrations = try await Api.shared.integrations().items; loadError = nil }
        catch { loadError = error.apiMessage }
    }
    func loadLogs() async {
        do { logs = try await Api.shared.integrationLogs().items; loadError = nil }
        catch { loadError = error.apiMessage }
    }
    func loadFlow() async {
        do { flow = try await Api.shared.messageFlow().items; loadError = nil }
        catch { loadError = error.apiMessage }
    }
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
    @State private var openConversation: Conversation?
    @State private var notice: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("التكاملات")).font(.wx(22, .bold)).foregroundStyle(Theme.onSurface)
                Spacer()
                if tab == .external {
                    Image(icon: .add).font(.wx(20)).foregroundStyle(Theme.primary)
                        .onTapGesture { editing = nil; showForm = true }
                }
                Image(icon: .refresh).font(.wx(20)).foregroundStyle(Theme.onMuted)
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
                    case .webhook: webhookTab
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
        .sheet(item: $openConversation) { conv in
            ChatView(conversation: conv)
        }
        .alert(L("التكاملات"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button(L("حسنًا"), role: .cancel) {}
        } message: { Text(notice ?? "") }
    }

    private var tabbar: some View {
        HStack(spacing: 4) {
            ForEach(IntegTab.allCases, id: \.self) { t in
                let active = tab == t
                Button { tab = t; Task { await reload() } } label: {
                    VStack(spacing: 6) {
                        Text(t.title).font(.wx(14, .semibold))
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
        case .webhook: await vm.loadWebhook()
        case .logs: await vm.loadLogs()
        }
    }

    // MARK: Webhook (web parity: the webhook configuration tab)
    @ViewBuilder private var webhookTab: some View {
        if let hook = vm.webhook {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                metric(L("الحالة"),
                       hook.verificationStatus == "configured" ? L("مُهيّأ") : L("يحتاج تهيئة"),
                       hook.verificationStatus == "configured" ? Theme.success : Theme.warning)
                metric(L("إخفاقات"), "\(hook.failedWebhookCount ?? 0)",
                       (hook.failedWebhookCount ?? 0) > 0 ? Theme.danger : Theme.onSurface)
            }
            if let last = hook.lastReceivedWebhook {
                Text(L("آخر استقبال") + ": " + monitorTime(last))
                    .font(.wx(12)).foregroundStyle(Theme.onMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let shared = hook.sharedWebhookUrl {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L("رابط الويب هوك المشترك")).font(.wx(12, .semibold)).foregroundStyle(Theme.onMuted)
                    HStack(spacing: 8) {
                        Text(shared).font(.wx(11.5)).foregroundStyle(Theme.onSurface)
                            .lineLimit(2)
                            .environment(\.layoutDirection, .leftToRight)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = shared
                            notice = L("نُسخ الرابط ✓")
                        } label: {
                            Image(icon: .copy).font(.wx(15)).foregroundStyle(Theme.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(16)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(L("تهيئة")).font(.wx(12, .semibold)).foregroundStyle(Theme.onMuted)
                TextField(L("مسار الويب هوك"), text: $vm.webhookPath)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.wx(13)).environment(\.layoutDirection, .leftToRight)
                    .padding(10)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 10))
                SecureField("Verify Token", text: $vm.webhookToken)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .font(.wx(13)).environment(\.layoutDirection, .leftToRight)
                    .padding(10)
                    .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    Task {
                        let failure = await vm.saveWebhook()
                        notice = failure ?? L("حُفظت إعدادات الويب هوك ✓")
                    }
                } label: {
                    Text(L("حفظ")).font(.wx(14, .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.primary, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Theme.onPrimary)
                }
                .buttonStyle(.plain)
                .disabled(vm.webhookPath.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(16)
        } else if let err = vm.loadError {
            LoadFailedView(message: err) { Task { await vm.loadWebhook() } }
        } else {
            ProgressView().tint(Theme.primary).padding(.top, 40)
        }
    }

    // MARK: Overview
    @ViewBuilder private var overviewTab: some View {
        if let s = vm.overview?.summary {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                metric(L("التكاملات"), "\(s.totalIntegrations)", Theme.onSurface)
                metric(L("حسابات متصلة"), "\(s.whatsappAccountsConnected)", Theme.onSurface)
                metric(L("نجاح Webhook"), fmtRate(s.webhookSuccessRate), Theme.success)
                metric(L("إخفاقات"), "\(s.failedIntegrations)", Theme.warning)
            }
        }
        if let h = vm.overview?.health {
            Text(L("صحّة الأرقام")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 11) {
                healthTile(L("سليمة"), h.healthy, Theme.success)
                healthTile(L("تحذير"), h.warning, Theme.warning)
                healthTile(L("منقطعة"), h.disconnected, Theme.danger)
                healthTile(L("فاشلة"), h.failed, Theme.danger)
            }
        }
        if vm.overview == nil {
            if let err = vm.loadError {
                LoadFailedView(message: err) { Task { await vm.loadOverview() } }
            } else {
                ProgressView().tint(Theme.primary).padding(.top, 40)
            }
        }

        // Template sends pushed by external systems (web parity: the
        // integration monitor list on the Overview tab).
        Text(L("قوالب النظام الخارجي")).font(.wx(16, .bold)).foregroundStyle(Theme.onMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
        if vm.monitor.isEmpty {
            Text(L("لا رسائل من الأنظمة الخارجية بعد"))
                .font(.wx(15)).foregroundStyle(Theme.onMuted)
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
                    .font(.wx(14.5, .semibold)).foregroundStyle(Theme.onSurface)
                    .lineLimit(1)
                Spacer()
                monitorStatusBadge(m.status)
            }
            HStack(spacing: 6) {
                Image(icon: .template).font(.wx(12)).foregroundStyle(Theme.primary)
                Text([m.templateName, m.templateLanguage].compactMap { $0 }.joined(separator: " · "))
                    .font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(1)
            }
            HStack {
                if let phone = m.phone, m.name?.isEmpty == false {
                    Text(phone).font(.wx(11)).foregroundStyle(Theme.onFaint)
                        .environment(\.layoutDirection, .leftToRight)
                }
                Spacer()
                if let acct = m.instance?.label {
                    Text(acct).font(.wx(11)).foregroundStyle(Theme.onFaint).lineLimit(1)
                }
                Text(monitorTime(m.createdAt)).font(.wx(11)).foregroundStyle(Theme.onFaint)
            }

            // Row actions (web parity: open chat · request call · open link).
            HStack(spacing: 8) {
                if let convId = m.conversationId, !convId.isEmpty {
                    Button { openChat(convId) } label: {
                        actionPill(L("فتح المحادثة"), "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.plain)
                }
                if let instId = m.instance?.id, !instId.isEmpty,
                   let phone = m.phone, !phone.isEmpty {
                    Button { requestCall(instanceId: instId, phone: phone) } label: {
                        actionPill(L("طلب اتصال"), "phone.badge.plus")
                    }
                    .buttonStyle(.plain)
                }
                if let link = m.resolvedUrl, let url = URL(string: link) {
                    Link(destination: url) {
                        actionPill(L("فتح الرابط"), "arrow.up.right.square")
                    }
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(16)
    }

    private func actionPill(_ title: String, _ icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.wx(11))
            Text(title).font(.wx(11, .semibold))
        }
        .foregroundStyle(Theme.primary)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.primarySoft, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.primaryContainer, lineWidth: 1))
    }

    private func openChat(_ conversationId: String) {
        Task {
            if let conv = try? await Api.shared.conversation(conversationId) {
                openConversation = conv
            } else {
                notice = L("تعذّر فتح المحادثة")
            }
        }
    }

    private func requestCall(instanceId: String, phone: String) {
        Task {
            do {
                try await Api.shared.requestCallPermission(to: phone.filter { $0.isNumber }, instanceId: instanceId)
                notice = L("أُرسل طلب إذن الاتصال إلى العميل ✓")
            } catch {
                notice = (error as? ApiError)?.message ?? error.localizedDescription
            }
        }
    }

    private func monitorStatusBadge(_ status: String?) -> some View {
        let s = (status ?? "").lowercased()
        let color: Color = s.contains("fail") || s.contains("error") || s.contains("reject") ? Theme.danger
            : s.contains("read") ? Theme.info
            : s.contains("deliver") || s.contains("sent") || s.contains("accept") ? Theme.success
            : Theme.warning
        return Text(status ?? "—")
            .font(.wx(11, .semibold)).foregroundStyle(color)
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
            Text(label).font(.wx(12)).foregroundStyle(Theme.onMuted)
            Text(value).font(.wx(26, .bold)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .glassCard(20)
    }

    private func healthTile(_ label: String, _ value: Int, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.wx(15)).foregroundStyle(Theme.onMuted)
            Spacer()
            Text("\(value)").font(.wx(18, .bold)).foregroundStyle(Theme.onSurface)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.outline, lineWidth: 1))
    }

    // MARK: External
    @ViewBuilder private var externalTab: some View {
        if vm.integrations.isEmpty, let err = vm.loadError {
            LoadFailedView(message: err) { Task { await vm.loadIntegrations() } }
        } else if vm.integrations.isEmpty {
            Text(L("لا أنظمة خارجية")).foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            ForEach(vm.integrations) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Image(icon: .webhook).foregroundStyle(Theme.onSurface)
                            .frame(width: 40, height: 40)
                            .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.wx(14.5, .semibold)).foregroundStyle(Theme.onSurface)
                            if let url = item.endpoint ?? item.baseUrl { Text(url).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(1) }
                        }
                        Spacer()
                        healthChip(item.health)
                    }
                    if let err = item.lastErrorMessage, !err.isEmpty {
                        Text(err).font(.wx(12)).foregroundStyle(Theme.danger).lineLimit(2)
                    }
                    HStack(spacing: 7) {
                        Text(item.isEnabled ? L("مُفعّل") : L("مُعطّل")).font(.wx(12)).foregroundStyle(Theme.onMuted)
                        Spacer()
                        Button { editing = item; showForm = true } label: {
                            Image(icon: .edit).font(.wx(15))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.outline, lineWidth: 1))
                                .foregroundStyle(Theme.onSurface)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.delete(item.id) } } label: {
                            Image(icon: .trash).font(.wx(15))
                                .frame(width: 36, height: 36)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.outline, lineWidth: 1))
                                .foregroundStyle(Theme.danger)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.test(item.id) } } label: {
                            Text(L("اختبار")).font(.wx(13, .semibold))
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(Theme.onSurface)
                        }.buttonStyle(.plain)
                        Button { Task { await vm.toggle(item) } } label: {
                            Text(item.isEnabled ? L("تعطيل") : L("تفعيل")).font(.wx(13, .semibold))
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
            case "healthy": return (L("سليمة"), Theme.success)
            case "warning": return (L("تحذير"), Theme.warning)
            case "failed", "disconnected": return (L("منقطعة"), Theme.danger)
            default: return (L("تهيئة"), Theme.onMuted)
            }
        }()
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.wx(11, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Message flow
    @ViewBuilder private var flowTab: some View {
        if vm.flow.isEmpty, let err = vm.loadError {
            LoadFailedView(message: err) { Task { await vm.loadFlow() } }
        } else if vm.flow.isEmpty {
            Text(L("لا أحداث تدفّق")).foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            ForEach(vm.flow) { e in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(icon: e.direction == "inbound" ? .callIn : .callOut).font(.wx(14))
                            .foregroundStyle(e.direction == "inbound" ? Theme.success : Theme.info)
                        Text(e.eventType ?? L("حدث")).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                        Spacer()
                        flowStatusChip(e.status)
                    }
                    if let s = e.source, let d = e.destination, !(s.isEmpty && d.isEmpty) {
                        Text("\(s) ← \(d)").font(.wx(11)).foregroundStyle(Theme.onMuted).lineLimit(1)
                    }
                    HStack(spacing: 10) {
                        if let c = e.responseCode { Text("HTTP \(c)").font(.wx(11)).foregroundStyle(Theme.onFaint) }
                        if let l = e.latencyMs { Text("\(l)ms").font(.wx(11)).foregroundStyle(Theme.onFaint) }
                        Spacer()
                        Text(shortTime(e.timestamp)).font(.wx(11)).foregroundStyle(Theme.onFaint)
                    }
                    if let err = e.errorMessage, !err.isEmpty {
                        Text(err).font(.wx(12)).foregroundStyle(Theme.danger).lineLimit(2)
                    }
                    if e.isRetryable {
                        HStack {
                            Spacer()
                            Button { Task { await vm.retry(e.id) } } label: {
                                HStack(spacing: 5) {
                                    Image(icon: .refresh).font(.wx(12))
                                    Text(L("إعادة المحاولة")).font(.wx(13, .semibold))
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
            .font(.wx(11, .semibold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }

    // MARK: Logs
    @ViewBuilder private var logsTab: some View {
        if vm.logs.isEmpty, let err = vm.loadError {
            LoadFailedView(message: err) { Task { await vm.loadLogs() } }
        } else if vm.logs.isEmpty {
            Text(L("لا سجلّات")).foregroundStyle(Theme.onMuted).padding(.top, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(vm.logs.enumerated()), id: \.element.id) { idx, log in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(sevColor(log.severity)).frame(width: 9, height: 9).padding(.top, 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(log.component).font(.wx(13, .semibold)).monospaced().foregroundStyle(Theme.onSurface)
                            Text(log.summary).font(.wx(12)).foregroundStyle(Theme.onMuted)
                        }
                        Spacer()
                        Text(shortTime(log.timestamp)).font(.wx(11)).foregroundStyle(Theme.onFaint)
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
                TextField(L("الاسم"), text: $name)
                TextField(L("رابط الأساس"), text: $baseUrl)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField(L("المسار"), text: $endpoint)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker(L("المصادقة"), selection: $authType) {
                    Text(L("بدون")).tag("none")
                    Text("Bearer").tag("bearer")
                    Text(L("مفتاح API")).tag("api_key")
                }
                TextField(L("المهلة (مللي ثانية)"), text: $timeout)
                    .keyboardType(.numberPad)
                Toggle(L("مُفعّل"), isOn: $enabled)
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(isEditing ? L("تعديل النظام") : L("نظام جديد"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("حفظ")) { Task { await save() } }
                        .disabled(saving || name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) { Button(L("إلغاء")) { dismiss() } }
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

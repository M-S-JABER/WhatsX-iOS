import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import MapKit
import AVKit

struct ChatView: View {
    @StateObject private var vm: ChatViewModel
    @StateObject private var recorder = VoiceRecorder()
    @Environment(\.dismiss) private var dismiss

    @State private var showPhotoPicker = false
    @State private var showDocImporter = false
    @State private var showReady = false
    @State private var showTemplates = false
    @State private var showInfo = false
    @State private var showChatSearch = false
    @State private var chatQuery = ""
    @State private var matchIndex = 0
    @State private var showCallMenu = false
    @State private var callNotice: String?
    @State private var lightboxItem: MediaItem?
    @State private var docItem: MediaItem?
    @State private var photoItem: PhotosPickerItem?
    /// Whether the view is scrolled to the newest message — auto-scroll on
    /// new messages must not yank the operator out of reading history.
    @State private var atBottom = true
    /// Live "customer is typing…" flag, driven by realtime typing events
    /// (activates whenever the backend broadcasts them for this conversation).
    @State private var customerTyping = false
    @State private var typingHideTask: Task<Void, Never>?

    /// True when this chat is PUSHED over a tab root: the floating tab bar
    /// hides for the whole visit so the composer owns the bottom edge.
    /// Sheet presentations and the iPad split pane leave it false.
    private let hidesTabBar: Bool

    init(conversation: Conversation, hidesTabBar: Bool = false) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
        self.hidesTabBar = hidesTabBar
    }

    /// Ids of messages matching the in-chat search, in timeline order.
    private var searchMatches: [String] {
        let q = chatQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return vm.messages.filter { $0.body?.localizedCaseInsensitiveContains(q) == true }.map { $0.id }
    }

    private var highlightedMessageId: String? {
        let matches = searchMatches
        guard !matches.isEmpty else { return nil }
        return matches[min(matchIndex, matches.count - 1)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                topBar
                if showChatSearch { chatSearchBar(proxy) }
                messages
                if let target = vm.replyTarget { replyBar(target) }
                QuickReplyBar(vm: vm)
                composer
            }
            .onChange(of: vm.messages.count) { _ in
                // Follow the tail only when the user is already at the bottom
                // or just sent something themselves.
                guard atBottom || vm.messages.last?.isOutbound == true else { return }
                if let last = vm.messages.last {
                    withAnimation { proxy.scrollTo("m-\(last.id)", anchor: .bottom) }
                }
            }
        }
        .background(chatBackground)
        .navigationBarHidden(true)
        // The custom top bar hides the system one — bring the edge-swipe
        // back gesture along explicitly.
        .swipeBackEnabled()
        .task { await vm.load() }
        .onAppear {
            Notifier.shared.activeConversationId = vm.conversation.id
            if hidesTabBar { InboxBus.shared.chatDidAppear() }
        }
        .onDisappear {
            vm.cancelRealtimeReload()
            if Notifier.shared.activeConversationId == vm.conversation.id {
                Notifier.shared.activeConversationId = nil
            }
            if hidesTabBar { InboxBus.shared.chatDidDisappear() }
        }
        .onReceive(Realtime.shared.events) { event in
            guard event.conversationId == nil || event.conversationId == vm.conversation.id else { return }
            // Typing events light the indicator for a beat; a new incoming
            // message clears it (the "typing" turned into a message).
            if event.name.lowercased().contains("typing") {
                showTypingIndicator()
                return
            }
            if RealtimeEvent.aiDraftEvents.contains(event.name) {
                withAnimation(.easeOut(duration: 0.2)) { vm.handleDraftEvent(event) }
                return
            }
            guard RealtimeEvent.chatEvents.contains(event.name) else { return }
            if event.name == "message_incoming" { hideTypingIndicator() }
            vm.scheduleRealtimeReload()
        }
        .confirmationDialog(L("الاتصال"), isPresented: $showCallMenu, titleVisibility: .visible) {
            if CallCenter.shared.canCarryAudio {
                Button(L("بدء مكالمة صوتية")) {
                    let digits = (vm.conversation.phone ?? "").filter { $0.isNumber }
                    CallCenter.shared.startOutbound(
                        to: digits,
                        displayName: vm.conversation.displayName,
                        instanceId: vm.conversation.instanceId)
                }
            }
            Button(L("طلب إذن الاتصال عبر واتساب")) {
                Task {
                    let digits = (vm.conversation.phone ?? "").filter { $0.isNumber }
                    do {
                        try await Api.shared.requestCallPermission(to: digits, instanceId: vm.conversation.instanceId)
                        callNotice = L("أُرسل طلب إذن الاتصال إلى العميل ✓")
                    } catch {
                        callNotice = CallPermissionNotice.friendly(error.apiMessage)
                    }
                }
            }
            Button(L("إلغاء"), role: .cancel) {}
        } message: {
            Text(CallCenter.shared.canCarryAudio
                 ? L("المكالمة تتطلب إذن اتصال مسبقاً من العميل؛ أرسل الطلب أولاً إن لم يكن ممنوحاً.")
                 : L("المكالمات الصوتية الحية متاحة من نسخة الويب؛ من هنا يمكن إرسال طلب إذن الاتصال للعميل."))
        }
        .alert(L("الاتصال"), isPresented: Binding(get: { callNotice != nil }, set: { if !$0 { callNotice = nil } })) {
            Button(L("حسنًا"), role: .cancel) {}
        } message: { Text(callNotice ?? "") }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data), let jpeg = img.jpegData(compressionQuality: 0.85) {
                    await vm.sendMedia(data: jpeg, filename: "image.jpg", mimeType: "image/jpeg")
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $showDocImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    await vm.sendMedia(data: data, filename: url.lastPathComponent, mimeType: mimeType(for: url))
                }
            }
        }
        .sheet(isPresented: $showReady) { ReadyPickerSheet { vm.insertReady($0) } }
        .sheet(isPresented: $showInfo) {
            ConversationInfoView(conversation: vm.conversation, messages: vm.messages)
        }
        .fullScreenCover(item: $lightboxItem) { ImageLightbox(item: $0) }
        .sheet(item: $docItem) { DocPreviewSheet(item: $0) }
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet { name, lang, params in await vm.sendTemplate(name: name, language: lang, params: params) }
        }
        .alert(L("تعذّر الإرسال"), isPresented: Binding(get: { vm.attachError != nil }, set: { if !$0 { vm.attachError = nil } })) {
            Button(L("حسنًا"), role: .cancel) {}
        } message: { Text(vm.attachError ?? "") }
        .alert(L("إذن الميكروفون مطلوب"), isPresented: $recorder.permissionDenied) {
            Button(L("فتح الإعدادات")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L("إلغاء"), role: .cancel) {}
        } message: {
            Text(L("فعّل إذن الميكروفون من إعدادات النظام لتسجيل الرسائل الصوتية."))
        }
    }

    private func showTypingIndicator() {
        withAnimation(.easeOut(duration: 0.2)) { customerTyping = true }
        typingHideTask?.cancel()
        typingHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { customerTyping = false }
        }
    }

    private func hideTypingIndicator() {
        typingHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { customerTyping = false }
    }

    /// WhatsX 2.0 (design 4c): a FLOATING glass header — back, avatar 38,
    /// name + live status, ONE prominent amber call action, and everything
    /// secondary (in-chat search, conversation info) behind «⋯».
    private var topBar: some View {
        HStack(spacing: 8) {
            Button { dismiss() } label: {
                Image(icon: .back).font(.wx(19)).foregroundStyle(Theme.onMuted)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("رجوع"))
            Avatar(name: vm.conversation.title, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.conversation.title).font(.wx(16.5, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                if customerTyping {
                    HStack(spacing: 4) {
                        TypingDots()
                        Text(L("يكتب الآن…")).font(.wx(12, .semibold)).foregroundStyle(Theme.success)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if let acct = vm.conversation.instance?.label {
                    Text(acct).font(.wx(12)).foregroundStyle(Theme.onMuted)
                }
            }
            // Long-press the name to copy the customer's number (web parity).
            .contextMenu {
                if let phone = vm.conversation.phone, !phone.isEmpty {
                    Button { UIPasteboard.general.string = phone } label: {
                        Label(phone, systemImage: "doc.on.doc")
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
            }
            Spacer()
            Button { showCallMenu = true } label: {
                Image(icon: .phoneCall).font(.wx(16, .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.amberAction, in: Circle())
                    .shadow(color: Theme.amberShadow, radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(vm.conversation.phone?.isEmpty != false)
            .accessibilityLabel(L("الاتصال"))
            Menu {
                Button { withAnimation { showChatSearch.toggle() } } label: {
                    Label(L("بحث في المحادثة"), systemImage: "magnifyingglass")
                }
                Button { showInfo = true } label: {
                    Label(L("معلومات المحادثة"), systemImage: "info.circle")
                }
            } label: {
                Image(icon: .more).font(.wx(18, .semibold)).foregroundStyle(Theme.onMuted)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel(L("المزيد"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .glassCard(Theme.Radius.chatHeader)
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 6)
    }

    private var messages: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if vm.timeline.isEmpty, !vm.loading, let err = vm.loadError {
                    LoadFailedView(message: err) { Task { await vm.load() } }
                        .padding(.top, 60)
                }
                ForEach(vm.timeline) { entry in
                    switch entry {
                    case .message(let msg):
                        SwipeToReply(onReply: { vm.replyTarget = msg }) {
                            MessageBubble(msg: msg,
                                          onRetry: msg.status == "failed" ? { Task { await vm.retry(msg) } } : nil,
                                          onSendTemplate: msg.status == "failed" ? { showTemplates = true } : nil,
                                          highlighted: highlightedMessageId == msg.id,
                                          onImageTap: { lightboxItem = MediaItem(url: $0) },
                                          onDocTap: { docItem = MediaItem(url: $0) })
                        }
                            .contextMenu {
                                Button { vm.replyTarget = msg } label: {
                                    Label(L("رد"), systemImage: "arrowshape.turn.up.left")
                                }
                                if let body = msg.body, !body.isEmpty {
                                    Button { UIPasteboard.general.string = body } label: {
                                        Label(L("نسخ"), systemImage: "doc.on.doc")
                                    }
                                }
                            }
                            .id(entry.id)
                    case .call(let call):
                        CallEventRow(call: call)
                            .id(entry.id)
                    case .day(let label):
                        Text(label)
                            .font(.wx(11.5, .medium)).foregroundStyle(Theme.onMuted)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(Theme.surface2, in: Capsule())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .id(entry.id)
                    }
                }
                // Bottom sentinel: tracks whether the user is at the tail so
                // incoming messages only auto-scroll when they should.
                Color.clear.frame(height: 1)
                    .onAppear { atBottom = true }
                    .onDisappear { atBottom = false }
            }
            .padding(.horizontal, 12).padding(.vertical, 12)
        }
    }

    private func chatSearchBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 10) {
            Image(icon: .search).font(.wx(14)).foregroundStyle(Theme.onMuted)
            TextField(L("ابحث في الرسائل"), text: $chatQuery)
                .font(.wx(14)).foregroundStyle(Theme.onSurface)
            if !searchMatches.isEmpty {
                Text("\(min(matchIndex, searchMatches.count - 1) + 1)/\(searchMatches.count)")
                    .font(.wx(12)).foregroundStyle(Theme.onMuted)
            }
            Button { stepMatch(-1, proxy) } label: {
                Image(systemName: "chevron.up").font(.wx(13, .semibold))
            }
            .disabled(searchMatches.isEmpty)
            Button { stepMatch(1, proxy) } label: {
                Image(systemName: "chevron.down").font(.wx(13, .semibold))
            }
            .disabled(searchMatches.isEmpty)
            Button {
                showChatSearch = false
                chatQuery = ""
                matchIndex = 0
            } label: {
                Image(systemName: "xmark").font(.wx(13, .semibold)).foregroundStyle(Theme.onMuted)
            }
        }
        .padding(.horizontal, 14).frame(height: 42)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.outline).frame(height: 1), alignment: .bottom)
        .onChange(of: chatQuery) { _ in
            matchIndex = 0
            if let id = highlightedMessageId {
                withAnimation { proxy.scrollTo("m-\(id)", anchor: .center) }
            }
        }
    }

    private func stepMatch(_ delta: Int, _ proxy: ScrollViewProxy) {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        matchIndex = (min(matchIndex, matches.count - 1) + delta + matches.count) % matches.count
        withAnimation { proxy.scrollTo("m-\(matches[matchIndex])", anchor: .center) }
    }

    private func replyBar(_ target: Message) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.primary).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(target.isOutbound ? L("أنت") : vm.conversation.title)
                    .font(.wx(12, .bold)).foregroundStyle(Theme.primary)
                Text(target.body?.isEmpty == false ? target.body! : L("وسائط"))
                    .font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(1)
            }
            Spacer()
            Button { vm.replyTarget = nil } label: {
                Image(systemName: "xmark.circle.fill").font(.wx(17)).foregroundStyle(Theme.onMuted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(Theme.surface1)
        .overlay(Rectangle().fill(Theme.outline).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private var composer: some View {
        if recorder.isRecording {
            recordingBar
        } else {
            normalComposer
        }
    }

    /// WhatsX 2.0 composer (design 4c): a glass capsule holding ONE «+»
    /// button (attach / template / ready replies) and the field, plus a
    /// separate amber-gradient circle that morphs mic ⇄ send with the
    /// field's emptiness.
    private var normalComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 4) {
                Menu {
                    Button { showPhotoPicker = true } label: {
                        Label(L("صورة"), systemImage: "photo")
                    }
                    Button { showDocImporter = true } label: {
                        Label(L("مستند"), systemImage: "doc")
                    }
                    Button { showTemplates = true } label: {
                        Label(L("قالب"), systemImage: "doc.text")
                    }
                    Button { showReady = true } label: {
                        Label(L("الردود الجاهزة"), systemImage: "bolt")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.wx(17, .semibold)).foregroundStyle(Theme.onMuted)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2.opacity(0.7), in: Circle())
                }
                .accessibilityLabel(L("إرفاق"))
                TextField(L("اكتب رسالة…"), text: $vm.input, axis: .vertical)
                    .font(.wx(16))
                    .lineLimit(1...4).foregroundStyle(Theme.onSurface)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 6).frame(minHeight: 46)
            .glassCard(24)

            Button {
                Haptics.action()
                if vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recorder.start()
                } else {
                    Task { await vm.send() }
                }
            } label: {
                Image(icon: vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .mic : .send)
                    .font(.wx(19)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.amberAction, in: Circle())
                    .shadow(color: Theme.amberShadow, radius: 7, y: 3)
            }
            .disabled(vm.sending)
            .accessibilityLabel(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? L("تسجيل رسالة صوتية") : L("إرسال"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// Recording state (design 4n): trash · red-dot capsule with the timer ·
    /// amber send.
    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                recorder.cancel()
            } label: {
                Image(icon: .trash).font(.wx(20)).foregroundStyle(Theme.danger).frame(width: 44, height: 44)
            }
            .accessibilityLabel(L("إلغاء التسجيل"))
            HStack(spacing: 8) {
                Circle().fill(Theme.danger).frame(width: 10, height: 10)
                    .opacity(Int(recorder.elapsed) % 2 == 0 ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.4), value: Int(recorder.elapsed))
                Text(L("جارٍ التسجيل") + "  \(timeStr(recorder.elapsed))")
                    .font(.wx(14, .medium)).foregroundStyle(Theme.onSurface)
                Spacer()
                Image(systemName: "waveform")
                    .font(.wx(16)).foregroundStyle(Theme.amberText)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .glassCard(24)

            Button {
                Haptics.action()
                if let data = recorder.stop() { Task { await vm.sendVoiceNote(data) } }
            } label: {
                Image(icon: .send).font(.wx(19)).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.amberAction, in: Circle())
                    .shadow(color: Theme.amberShadow, radius: 7, y: 3)
            }
            .accessibilityLabel(L("إرسال الرسالة الصوتية"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func timeStr(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var chatBackground: some View {
        Theme.glowBackground()
    }
}

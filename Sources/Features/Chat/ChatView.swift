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

    @State private var showAttachMenu = false
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

    init(conversation: Conversation) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
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
        .task { await vm.load() }
        .onAppear { Notifier.shared.activeConversationId = vm.conversation.id }
        .onDisappear {
            vm.cancelRealtimeReload()
            if Notifier.shared.activeConversationId == vm.conversation.id {
                Notifier.shared.activeConversationId = nil
            }
        }
        .onReceive(Realtime.shared.events) { event in
            guard RealtimeEvent.chatEvents.contains(event.name),
                  event.conversationId == nil || event.conversationId == vm.conversation.id
            else { return }
            vm.scheduleRealtimeReload()
        }
        .confirmationDialog(L("الاتصال"), isPresented: $showCallMenu, titleVisibility: .visible) {
            Button(L("طلب إذن الاتصال عبر واتساب")) {
                Task {
                    let digits = (vm.conversation.phone ?? "").filter { $0.isNumber }
                    do {
                        try await Api.shared.requestCallPermission(to: digits, instanceId: vm.conversation.instanceId)
                        callNotice = L("أُرسل طلب إذن الاتصال إلى العميل ✓")
                    } catch {
                        callNotice = error.apiMessage
                    }
                }
            }
            Button(L("إلغاء"), role: .cancel) {}
        } message: {
            Text(L("المكالمات الصوتية الحية متاحة من نسخة الويب؛ من هنا يمكن إرسال طلب إذن الاتصال للعميل."))
        }
        .alert(L("الاتصال"), isPresented: Binding(get: { callNotice != nil }, set: { if !$0 { callNotice = nil } })) {
            Button(L("حسنًا"), role: .cancel) {}
        } message: { Text(callNotice ?? "") }
        .confirmationDialog(L("إرفاق"), isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button(L("صورة")) { showPhotoPicker = true }
            Button(L("مستند")) { showDocImporter = true }
            Button(L("قالب")) { showTemplates = true }
            Button(L("إلغاء"), role: .cancel) {}
        }
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
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: { Image(icon: .back).font(.wx(20)).foregroundStyle(Theme.onMuted) }
                .accessibilityLabel(L("رجوع"))
            Avatar(name: vm.conversation.title, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.conversation.title).font(.wx(16, .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                if let acct = vm.conversation.instance?.label {
                    Text(acct).font(.wx(11)).foregroundStyle(Theme.onMuted)
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
            Button { withAnimation { showChatSearch.toggle() } } label: {
                Image(icon: .search).font(.wx(18))
                    .foregroundStyle(showChatSearch ? Theme.primary : Theme.onMuted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("بحث في المحادثة"))
            Button { showCallMenu = true } label: {
                Image(icon: .phoneCall).font(.wx(20)).foregroundStyle(Theme.primary).padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .disabled(vm.conversation.phone?.isEmpty != false)
            .accessibilityLabel(L("الاتصال"))
            Button { showInfo = true } label: {
                Image(icon: .info).font(.wx(19)).foregroundStyle(Theme.onMuted).padding(.leading, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("معلومات المحادثة"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.outline).frame(height: 1), alignment: .bottom)
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
                        MessageBubble(msg: msg,
                                      onRetry: msg.status == "failed" ? { Task { await vm.retry(msg) } } : nil,
                                      highlighted: highlightedMessageId == msg.id,
                                      onImageTap: { lightboxItem = MediaItem(url: $0) },
                                      onDocTap: { docItem = MediaItem(url: $0) })
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

    private var normalComposer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 2) {
                Image(icon: .emoji).foregroundStyle(Theme.onMuted).frame(width: 32, height: 34)
                TextField(L("اكتب رسالة…"), text: $vm.input, axis: .vertical)
                    .lineLimit(1...4).foregroundStyle(Theme.onSurface)
                Button { showReady = true } label: {
                    Image(icon: .bolt).foregroundStyle(Theme.onMuted).frame(width: 32, height: 34)
                }
                .accessibilityLabel(L("الردود الجاهزة"))
                Button { showAttachMenu = true } label: {
                    Image(icon: .attach).foregroundStyle(Theme.onMuted).frame(width: 32, height: 34)
                }
                .accessibilityLabel(L("إرفاق"))
            }
            .padding(.horizontal, 6).frame(minHeight: 48)
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
                    .font(.wx(20)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.primary, in: Circle())
            }
            .disabled(vm.sending)
            .accessibilityLabel(vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? L("تسجيل رسالة صوتية") : L("إرسال"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.background)
    }

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
                Text(L("جارٍ التسجيل") + "  \(timeStr(recorder.elapsed))")
                    .font(.wx(14, .medium)).foregroundStyle(Theme.onSurface)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 48)
            .glassCard(24)

            Button {
                Haptics.action()
                if let data = recorder.stop() { Task { await vm.sendVoiceNote(data) } }
            } label: {
                Image(icon: .send).font(.wx(20)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48).background(Theme.primary, in: Circle())
            }
            .accessibilityLabel(L("إرسال الرسالة الصوتية"))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.background)
    }

    private func timeStr(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private var chatBackground: some View {
        Theme.background.overlay(
            RadialGradient(colors: [Theme.primary.opacity(0.05), .clear],
                           center: .init(x: 0.2, y: 0.1), startRadius: 0, endRadius: 320)
        ).ignoresSafeArea()
    }
}

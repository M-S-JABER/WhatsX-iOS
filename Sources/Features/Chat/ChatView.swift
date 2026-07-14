import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers
import MapKit
import AVKit

// Records a short voice note to a temp .m4a file (AAC) for upload via /api/upload.
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in self?.beginRecording() }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vn-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        guard let rec = try? AVAudioRecorder(url: url, settings: settings) else { return }
        rec.record()
        recorder = rec; fileURL = url; isRecording = true; elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsed += 1 }
        }
    }

    /// Stops and returns the recorded audio data (nil if empty/too short).
    func stop() -> Data? {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard elapsed >= 1, let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return data
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var calls: [VoiceCall] = []
    @Published var loading = false
    @Published var loadError: String?
    @Published var input = ""
    @Published var sending = false
    @Published var attachError: String?
    @Published var replyTarget: Message? = nil
    /// Messages merged chronologically with the conversation's call events —
    /// rebuilt only when messages/calls change, never during body evaluation
    /// (the merge+sort is too heavy to run on every keystroke).
    @Published private(set) var timeline: [ChatEntry] = []
    let conversation: Conversation

    private var realtimeReloadTask: Task<Void, Never>?

    init(conversation: Conversation) { self.conversation = conversation }

    private func rebuildTimeline() {
        let entries: [(entry: ChatEntry, date: Date, order: Int)] =
            messages.enumerated().map { (i, m) in (ChatEntry.message(m), parseISODate(m.createdAt) ?? .distantPast, i) }
            + calls.enumerated().map { (i, c) in (ChatEntry.call(c), parseISODate(c.startedAt) ?? .distantPast, i) }
        let sorted = entries.sorted { a, b in
            if a.date != b.date { return a.date < b.date }
            return a.order < b.order
        }
        var out: [ChatEntry] = []
        var lastDay: String? = nil
        for item in sorted {
            if item.date != .distantPast {
                let day = dayLabel(item.date)
                if day != lastDay {
                    out.append(.day(day))
                    lastDay = day
                }
            }
            out.append(item.entry)
        }
        timeline = out
    }

    func load() async {
        loading = messages.isEmpty
        await loadMessages()
        // Requires calls.view — silently absent for roles without it.
        calls = (try? await Api.shared.conversationCalls(conversationId: conversation.id).items) ?? []
        rebuildTimeline()
        loading = false
    }

    /// Refetch the transcript only — realtime message events don't touch the
    /// call log, so reloading calls on every event was wasted work.
    func loadMessages() async {
        do {
            messages = try await Api.shared.messages(conversationId: conversation.id).items
            loadError = nil
        } catch { loadError = error.apiMessage }
        rebuildTimeline()
    }

    /// Coalesces realtime bursts: many events within a beat trigger ONE
    /// refetch, and an in-flight refetch is cancelled instead of racing the
    /// next one (two concurrent loads used to finish in either order).
    func scheduleRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.loadMessages()
        }
    }

    /// Call when the screen goes away — a pending refetch must not mutate a
    /// dismissed view's state.
    func cancelRealtimeReload() {
        realtimeReloadTask?.cancel()
        realtimeReloadTask = nil
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        input = ""
        do {
            try await Api.shared.sendMessage(conversationId: conversation.id, body: text,
                                             replyToMessageId: replyTarget?.id)
            replyTarget = nil
            await loadMessages()
        } catch {
            // Restore the failed text only if the box is still empty —
            // overwriting would eat whatever the user typed meanwhile.
            if input.isEmpty { input = text }
            attachError = error.apiMessage
        }
        sending = false
    }

    func sendMedia(data: Data, filename: String, mimeType: String, caption: String? = nil) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            let up = try await Api.shared.uploadMedia(data: data, filename: filename, mimeType: mimeType)
            try await Api.shared.sendMedia(conversationId: conversation.id, mediaUrl: up.url, caption: caption,
                                           replyToMessageId: replyTarget?.id)
            replyTarget = nil
            await loadMessages()
        } catch { attachError = (error as? ApiError)?.message ?? error.localizedDescription }
        sending = false
    }

    func sendVoiceNote(_ data: Data) async {
        await sendMedia(data: data, filename: "voice-note.m4a", mimeType: "audio/mp4")
    }

    func sendTemplate(name: String, language: String?, params: [String]) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            try await Api.shared.sendTemplate(conversationId: conversation.id, name: name, language: language, params: params)
            await loadMessages()
        } catch { attachError = (error as? ApiError)?.message ?? error.localizedDescription }
        sending = false
    }

    func insertReady(_ text: String) {
        input = input.isEmpty ? text : input + "\n" + text
    }

    func retry(_ msg: Message) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            if let mediaUrl = msg.media?.url, !mediaUrl.isEmpty {
                try await Api.shared.sendMedia(conversationId: conversation.id, mediaUrl: mediaUrl, caption: msg.body)
            } else if let body = msg.body, !body.isEmpty {
                try await Api.shared.sendMessage(conversationId: conversation.id, body: body)
            }
            await loadMessages()
        } catch { attachError = (error as? ApiError)?.message ?? error.localizedDescription }
        sending = false
    }
}

/// One row of the chat timeline: a message bubble, an inline call event,
/// or a day separator.
enum ChatEntry: Identifiable, Equatable {
    case message(Message)
    case call(VoiceCall)
    case day(String)
    var id: String {
        switch self {
        case .message(let m): return "m-\(m.id)"
        case .call(let c): return "c-\(c.id)"
        case .day(let d): return "d-\(d)"
        }
    }
}

func dayLabel(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return L("اليوم") }
    if cal.isDateInYesterday(date) { return L("أمس") }
    let f = DateFormatter()
    f.locale = L10n.dateLocale
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: date)
}

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
                        callNotice = (error as? ApiError)?.message ?? error.localizedDescription
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
            Button { recorder.cancel() } label: {
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

struct MessageBubble: View {
    let msg: Message
    var onRetry: (() -> Void)? = nil
    var highlighted: Bool = false
    var onImageTap: ((URL) -> Void)? = nil
    var onDocTap: ((URL) -> Void)? = nil
    private var outbound: Bool { msg.isOutbound }
    private var failed: Bool { msg.status == "failed" }
    private var fg: Color { outbound ? Theme.bubbleOutFg : Theme.bubbleInFg }

    var body: some View {
        HStack {
            if outbound { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                if let reply = msg.replyTo {
                    quoteView(reply)
                }
                if let media = msg.media, let url = Api.mediaURL(media.url) {
                    mediaView(media, url)
                }
                // Shared contacts (vCards) with tap-to-copy phones.
                ForEach(Array(msg.sharedContacts.enumerated()), id: \.offset) { _, contact in
                    contactCard(contact)
                }
                if msg.isTemplateMessage {
                    templateCard
                } else if msg.media == nil, let location = parseSharedLocation(msg.body) {
                    LocationCard(location: location, fg: fg)
                } else if let body = msg.body, !body.isEmpty, msg.sharedContacts.isEmpty {
                    Text(body).font(.wx(14.5)).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                    // Link preview card for the first URL in the text.
                    if let link = firstURL(in: body), parseSharedLocation(body) == nil {
                        LinkPreviewCard(url: link, fg: fg)
                    }
                }
                HStack(spacing: 3) {
                    Text(clockTime(msg.createdAt)).font(.wx(10.5))
                    if outbound {
                        // Sent = single tick, delivered = circled, read = filled
                        // blue — the WhatsApp semantics the flat icon lost.
                        Image(systemName: statusSymbol).font(.wx(11))
                            .foregroundStyle(statusColor)
                            .accessibilityLabel(statusLabel)
                    }
                }
                .foregroundStyle((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)

                if failed, let reason = msg.failureReason {
                    Text(reason).font(.wx(11)).foregroundStyle(Theme.danger).lineLimit(3)
                }
                if failed, let onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(icon: .refresh).font(.wx(11))
                            Text(L("إعادة الإرسال")).font(.wx(12, .semibold))
                        }
                        .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(outbound ? Theme.bubbleOut : Theme.bubbleIn,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.primary, lineWidth: highlighted ? 2 : 0))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .frame(maxWidth: 300, alignment: outbound ? .trailing : .leading)
            if !outbound { Spacer(minLength: 40) }
        }
    }

    private var statusSymbol: String {
        if failed { return WIcon.alert.symbol() }
        switch msg.status {
        case "read": return "checkmark.circle.fill"
        case "delivered": return "checkmark.circle"
        default: return "checkmark"
        }
    }

    private var statusColor: Color {
        if failed { return Theme.danger }
        if msg.status == "read" { return Theme.info }
        return fg.opacity(0.6)
    }

    private var statusLabel: String {
        if failed { return L("فشل الإرسال") }
        switch msg.status {
        case "read": return L("قُرئت")
        case "delivered": return L("وصلت")
        default: return L("أُرسلت")
        }
    }

    /// Quoted-reply preview rendered above the message content.
    private func quoteView(_ reply: ReplySummary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(reply.direction == "outbound" ? L("أنت") : (reply.senderLabel?.isEmpty == false ? reply.senderLabel! : L("رد على")))
                .font(.wx(11, .semibold)).foregroundStyle(Theme.primary)
            Text(reply.content?.isEmpty == false ? reply.content! : L("وسائط"))
                .font(.wx(12)).foregroundStyle(fg.opacity(0.75)).lineLimit(2)
        }
        .padding(.leading, 9).padding(.trailing, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fg.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.primary).frame(width: 3)
        }
    }

    @ViewBuilder
    private func mediaView(_ media: MessageMedia, _ url: URL) -> some View {
        if isImage(media) {
            RemoteImage(url: url, targetSize: 230) { Theme.surface2 }
                .frame(width: 220, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture { onImageTap?(url) }
        } else if isVideo(media) {
            VideoBubble(url: url)
        } else if isAudio(media) {
            AudioMessage(url: url, tint: outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
        } else {
            Button { onDocTap?(url) } label: {
                HStack(spacing: 10) {
                    Image(icon: .doc).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                    Text(L("مستند")).font(.wx(13)).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                    Spacer()
                    Image(icon: .download).foregroundStyle((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.7))
                }
                .padding(10).frame(minWidth: 200)
                .background((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    /// Template message card: name/language header, resolved body, and the
    /// interactive buttons (web parity: templatePreview.resolvedButtons).
    private var templateCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(icon: .template).font(.wx(11)).foregroundStyle(Theme.primary)
                Text([msg.templateName ?? L("قالب"), msg.templateLanguage].compactMap { $0 }.joined(separator: " · "))
                    .font(.wx(11, .semibold)).foregroundStyle(Theme.primary).lineLimit(1)
            }
            if let text = msg.templatePreview?.resolvedBodyText ?? msg.body, !text.isEmpty {
                Text(text).font(.wx(14.5)).foregroundStyle(fg)
            }
            let buttons = msg.templatePreview?.resolvedButtons ?? []
            if !buttons.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                        templateButton(button)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func templateButton(_ button: TemplatePreviewButton) -> some View {
        let label = HStack(spacing: 5) {
            Image(systemName: button.type == "url" ? "arrow.up.right.square" : "arrowshape.turn.up.left")
                .font(.wx(11, .semibold))
            Text(button.text?.isEmpty == false ? button.text! : L("فتح الرابط"))
                .font(.wx(12.5, .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(fg.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))

        if let urlString = button.resolvedUrl, let url = URL(string: urlString) {
            Link(destination: url) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    /// Shared-contact card with tap-to-copy phone numbers.
    private func contactCard(_ contact: SharedContact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.wx(20)).foregroundStyle(Theme.primary)
                Text(contact.name.isEmpty ? (contact.phones.first ?? "—") : contact.name)
                    .font(.wx(13.5, .semibold)).foregroundStyle(fg).lineLimit(1)
            }
            ForEach(contact.phones, id: \.self) { phone in
                Button { UIPasteboard.general.string = phone } label: {
                    HStack(spacing: 6) {
                        Text(phone).font(.wx(12.5)).foregroundStyle(fg.opacity(0.8))
                            .environment(\.layoutDirection, .leftToRight)
                        Image(systemName: "doc.on.doc")
                            .font(.wx(10)).foregroundStyle(fg.opacity(0.55))
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9).frame(minWidth: 200, alignment: .leading)
        .background(fg.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private func isImage(_ m: MessageMedia) -> Bool {
        m.mediaType == "image" || (m.mimeType?.hasPrefix("image/") ?? false)
    }
    private func isVideo(_ m: MessageMedia) -> Bool {
        m.mediaType == "video" || (m.mimeType?.hasPrefix("video/") ?? false)
    }
    private func isAudio(_ m: MessageMedia) -> Bool {
        m.mediaType == "audio" || (m.mimeType?.hasPrefix("audio/") ?? false)
    }
}

// MARK: - Shared location (web parity: LocationPreview)

/// A WhatsApp location share, detected in the message body as a
/// `https://maps.google.com/?q=lat,lng` link with the place name/address on
/// the preceding lines (same parsing as the web MessageBubble).
struct SharedLocation: Equatable {
    let lat: Double
    let lng: Double
    let name: String?
    let address: String?
    let mapsUrl: URL
}

/// Compiled once — this runs per bubble per render; recompiling the pattern
/// every call was measurable scroll jank.
private let sharedLocationRegex = try? NSRegularExpression(
    pattern: #"https?://maps\.google\.com/\?q=(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#,
    options: [.caseInsensitive])

func parseSharedLocation(_ body: String?) -> SharedLocation? {
    guard let body, !body.isEmpty else { return nil }
    guard let re = sharedLocationRegex,
          let match = re.firstMatch(in: body, options: [], range: NSRange(body.startIndex..., in: body)),
          let urlRange = Range(match.range, in: body),
          let latRange = Range(match.range(at: 1), in: body),
          let lngRange = Range(match.range(at: 2), in: body),
          let lat = Double(body[latRange]),
          let lng = Double(body[lngRange]),
          let url = URL(string: String(body[urlRange]))
    else { return nil }
    let lines = body[body.startIndex..<urlRange.lowerBound]
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    let address = lines.dropFirst().joined(separator: L("، "))
    return SharedLocation(lat: lat, lng: lng,
                          name: lines.first,
                          address: address.isEmpty ? nil : address,
                          mapsUrl: url)
}

/// Location bubble content: static map thumbnail + place name/address;
/// tapping opens the original maps link.
struct LocationCard: View {
    let location: SharedLocation
    let fg: Color

    private struct MapPin: Identifiable {
        let id = "pin"
        let coordinate: CLLocationCoordinate2D
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }

    var body: some View {
        Link(destination: location.mapsUrl) {
            VStack(alignment: .leading, spacing: 6) {
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))),
                    interactionModes: [],
                    annotationItems: [MapPin(coordinate: coordinate)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: .red)
                }
                .frame(width: 230, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Image(icon: .place).font(.wx(12)).foregroundStyle(Theme.primary)
                        Text(location.name?.isEmpty == false ? location.name! : L("موقع"))
                            .font(.wx(13, .semibold)).foregroundStyle(fg)
                            .lineLimit(1)
                    }
                    Text(location.address ?? String(format: "%.5f, %.5f", location.lat, location.lng))
                        .font(.wx(11.5)).foregroundStyle(fg.opacity(0.7)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inline call event

/// A centered call-event chip in the chat timeline (web parity: call bubbles
/// merged chronologically between messages).
struct CallEventRow: View {
    let call: VoiceCall
    private var inbound: Bool { call.direction == "inbound" }
    private var missed: Bool {
        let s = (call.outcome ?? call.status ?? "").lowercased()
        return s.contains("missed") || s.contains("no_answer") || s.contains("failed") || s.contains("rejected")
    }

    var body: some View {
        HStack {
            Spacer(minLength: 30)
            HStack(spacing: 8) {
                Image(systemName: inbound ? "phone.arrow.down.left" : "phone.arrow.up.right")
                    .font(.wx(13))
                    .foregroundStyle(missed ? Theme.danger : Theme.success)
                Text(label).font(.wx(12.5, .medium)).foregroundStyle(Theme.onMuted)
                Text(clockTime(call.startedAt)).font(.wx(11)).foregroundStyle(Theme.onFaint)
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
            .glassCapsule()
            Spacer(minLength: 30)
        }
        .padding(.vertical, 4)
    }

    private var label: String {
        var parts: [String] = [inbound ? L("مكالمة واردة") : L("مكالمة صادرة")]
        if missed {
            parts.append(L("لم يُرَدّ عليها"))
        } else if call.durationSeconds > 0 {
            let s = call.durationSeconds
            parts.append(String(format: "%02d:%02d", s / 60, s % 60))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Ready-message quick picker

struct ReadyPickerSheet: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ReadyMessage] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView().tint(Theme.primary)
                } else if items.isEmpty {
                    Text(L("لا ردود جاهزة")).foregroundStyle(Theme.onMuted)
                } else {
                    List(items) { r in
                        Button { onPick(r.body); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                                Text(r.body).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(2)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(L("ردود جاهزة")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } } }
            .task {
                items = (try? await Api.shared.readyMessages())?.items ?? []
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Template picker + parameter fill

struct TemplatePickerSheet: View {
    let onSend: (String, String?, [String]) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var templates: [Template] = []
    @State private var loading = true
    @State private var selected: Template?
    @State private var params: [String] = []
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Group {
                if let t = selected {
                    paramForm(t)
                } else if loading {
                    ProgressView().tint(Theme.primary).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if templates.isEmpty {
                    Text(L("لا قوالب")).foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(templates, id: \.stableId) { t in
                        Button {
                            selected = t
                            params = Array(repeating: "", count: max(0, t.bodyParams))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.name).font(.wx(14, .semibold)).foregroundStyle(Theme.onSurface)
                                if let preview = t.bodyText {
                                    Text(preview).font(.wx(12)).foregroundStyle(Theme.onMuted).lineLimit(2)
                                }
                                Text([t.status, t.language].compactMap { $0 }.joined(separator: " · "))
                                    .font(.wx(11)).foregroundStyle(Theme.onFaint)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(selected == nil ? L("القوالب") : L("إرسال قالب")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selected == nil ? L("إغلاق") : L("رجوع")) {
                        if selected == nil { dismiss() } else { selected = nil }
                    }
                }
                if let t = selected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("إرسال")) {
                            Task { sending = true; await onSend(t.name, t.language, params); sending = false; dismiss() }
                        }.disabled(sending)
                    }
                }
            }
            .task {
                templates = (try? await Api.shared.templates())?.items ?? []
                loading = false
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func paramForm(_ t: Template) -> some View {
        Form {
            Section(L("القالب")) {
                Text(t.name).font(.wx(17, .semibold)).foregroundStyle(Theme.onSurface)
                if let preview = t.bodyText { Text(preview).font(.wx(12)).foregroundStyle(Theme.onMuted) }
            }
            if t.bodyParams > 0 {
                Section(L("المتغيرات")) {
                    ForEach(0..<t.bodyParams, id: \.self) { i in
                        TextField(L("المتغير") + " \(i + 1)", text: Binding(
                            get: { i < params.count ? params[i] : "" },
                            set: { v in if i < params.count { params[i] = v } }
                        ))
                    }
                }
            } else {
                Section { Text(L("لا متغيرات في هذا القالب")).foregroundStyle(Theme.onMuted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }
}

// Formatters are expensive to create and these run per row per render —
// build them once. All call sites are on the main actor.
private let isoFractionalParser: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlainParser = ISO8601DateFormatter()
private let clockFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
}()

func parseISODate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    return isoFractionalParser.date(from: iso) ?? isoPlainParser.date(from: iso)
}

func clockTime(_ iso: String?) -> String {
    guard let date = parseISODate(iso) else { return "" }
    return clockFormatter.string(from: date)
}

func mimeType(for url: URL) -> String {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
}

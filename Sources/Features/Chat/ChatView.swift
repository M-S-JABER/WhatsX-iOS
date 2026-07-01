import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

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
    @Published var loading = false
    @Published var input = ""
    @Published var sending = false
    @Published var attachError: String?
    let conversation: Conversation

    init(conversation: Conversation) { self.conversation = conversation }

    func load() async {
        loading = messages.isEmpty
        do { messages = try await Api.shared.messages(conversationId: conversation.id).items }
        catch { }
        loading = false
    }

    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        input = ""
        do {
            try await Api.shared.sendMessage(conversationId: conversation.id, body: text)
            await load()
        } catch { input = text }
        sending = false
    }

    func sendMedia(data: Data, filename: String, mimeType: String, caption: String? = nil) async {
        guard !sending else { return }
        sending = true; attachError = nil
        do {
            let up = try await Api.shared.uploadMedia(data: data, filename: filename, mimeType: mimeType)
            try await Api.shared.sendMedia(conversationId: conversation.id, mediaUrl: up.url, caption: caption)
            await load()
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
            await load()
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
            await load()
        } catch { attachError = (error as? ApiError)?.message ?? error.localizedDescription }
        sending = false
    }
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
    @State private var photoItem: PhotosPickerItem?

    init(conversation: Conversation) {
        _vm = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            messages
            composer
        }
        .background(chatBackground)
        .navigationBarHidden(true)
        .task { await vm.load() }
        .confirmationDialog("إرفاق", isPresented: $showAttachMenu, titleVisibility: .visible) {
            Button("صورة") { showPhotoPicker = true }
            Button("مستند") { showDocImporter = true }
            Button("قالب") { showTemplates = true }
            Button("إلغاء", role: .cancel) {}
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
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet { name, lang, params in await vm.sendTemplate(name: name, language: lang, params: params) }
        }
        .alert("تعذّر الإرسال", isPresented: Binding(get: { vm.attachError != nil }, set: { if !$0 { vm.attachError = nil } })) {
            Button("حسنًا", role: .cancel) {}
        } message: { Text(vm.attachError ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            Button { dismiss() } label: { Image(icon: .back).font(.system(size: 20)).foregroundStyle(Theme.onMuted) }
            Avatar(name: vm.conversation.title, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(vm.conversation.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.onSurface).lineLimit(1)
                if let acct = vm.conversation.instance?.label {
                    Text(acct).font(.caption2).foregroundStyle(Theme.onMuted)
                }
            }
            Spacer()
            Image(icon: .phoneCall).font(.system(size: 20)).foregroundStyle(Theme.primary)
            Image(icon: .more).font(.system(size: 20)).foregroundStyle(Theme.onMuted).padding(.leading, 8)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.outline).frame(height: 1), alignment: .bottom)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.messages) { msg in
                        MessageBubble(msg: msg, onRetry: msg.status == "failed" ? { Task { await vm.retry(msg) } } : nil)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
            }
            .onChange(of: vm.messages.count) { _ in
                if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
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
                TextField("اكتب رسالة…", text: $vm.input, axis: .vertical)
                    .lineLimit(1...4).foregroundStyle(Theme.onSurface)
                Button { showReady = true } label: {
                    Image(icon: .bolt).foregroundStyle(Theme.onMuted).frame(width: 32, height: 34)
                }
                Button { showAttachMenu = true } label: {
                    Image(icon: .attach).foregroundStyle(Theme.onMuted).frame(width: 32, height: 34)
                }
            }
            .padding(.horizontal, 6).frame(minHeight: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.outline, lineWidth: 1))

            Button {
                if vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recorder.start()
                } else {
                    Task { await vm.send() }
                }
            } label: {
                Image(icon: vm.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .mic : .send)
                    .font(.system(size: 20)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.primary, in: Circle())
            }
            .disabled(vm.sending)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.background)
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            Button { recorder.cancel() } label: {
                Image(icon: .trash).font(.system(size: 20)).foregroundStyle(Theme.danger).frame(width: 44, height: 44)
            }
            HStack(spacing: 8) {
                Circle().fill(Theme.danger).frame(width: 10, height: 10)
                Text("جارٍ التسجيل  \(timeStr(recorder.elapsed))")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.onSurface)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.outline, lineWidth: 1))

            Button {
                if let data = recorder.stop() { Task { await vm.sendVoiceNote(data) } }
            } label: {
                Image(icon: .send).font(.system(size: 20)).foregroundStyle(Theme.onPrimary)
                    .frame(width: 48, height: 48).background(Theme.primary, in: Circle())
            }
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
    private var outbound: Bool { msg.isOutbound }
    private var failed: Bool { msg.status == "failed" }

    var body: some View {
        HStack {
            if outbound { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 3) {
                if let media = msg.media, let url = Api.mediaURL(media.url) {
                    mediaView(media, url)
                }
                if let body = msg.body, !body.isEmpty {
                    Text(body).font(.system(size: 14.5)).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                }
                HStack(spacing: 3) {
                    Text(clockTime(msg.createdAt)).font(.system(size: 10.5))
                    if outbound {
                        Image(icon: failed ? .alert : .checkDouble).font(.system(size: 11))
                            .foregroundStyle(failed ? Theme.danger : (outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.6))
                    }
                }
                .foregroundStyle((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .trailing)

                if failed, let onRetry {
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(icon: .refresh).font(.system(size: 11))
                            Text("إعادة الإرسال").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(outbound ? Theme.bubbleOut : Theme.bubbleIn,
                        in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .frame(maxWidth: 300, alignment: outbound ? .trailing : .leading)
            if !outbound { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func mediaView(_ media: MessageMedia, _ url: URL) -> some View {
        if isImage(media) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Theme.surface2 }
                .frame(width: 220, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if isAudio(media) {
            AudioMessage(url: url, tint: outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
        } else {
            HStack(spacing: 10) {
                Image(icon: .doc).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                Text("مستند").font(.footnote).foregroundStyle(outbound ? Theme.bubbleOutFg : Theme.bubbleInFg)
                Spacer()
                Image(icon: .download).foregroundStyle((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.7))
            }
            .padding(10).frame(minWidth: 200)
            .background((outbound ? Theme.bubbleOutFg : Theme.bubbleInFg).opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func isImage(_ m: MessageMedia) -> Bool {
        m.mediaType == "image" || (m.mimeType?.hasPrefix("image/") ?? false)
    }
    private func isAudio(_ m: MessageMedia) -> Bool {
        m.mediaType == "audio" || (m.mimeType?.hasPrefix("audio/") ?? false)
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
                    Text("لا ردود جاهزة").foregroundStyle(Theme.onMuted)
                } else {
                    List(items) { r in
                        Button { onPick(r.body); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                Text(r.body).font(.caption).foregroundStyle(Theme.onMuted).lineLimit(2)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("ردود جاهزة").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
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
                    Text("لا قوالب").foregroundStyle(Theme.onMuted).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(templates, id: \.stableId) { t in
                        Button {
                            selected = t
                            params = Array(repeating: "", count: max(0, t.bodyParams))
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.onSurface)
                                if let preview = t.bodyText {
                                    Text(preview).font(.caption).foregroundStyle(Theme.onMuted).lineLimit(2)
                                }
                                Text([t.status, t.language].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption2).foregroundStyle(Theme.onFaint)
                            }
                        }
                        .listRowBackground(Theme.background)
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(selected == nil ? "القوالب" : "إرسال قالب").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selected == nil ? "إغلاق" : "رجوع") {
                        if selected == nil { dismiss() } else { selected = nil }
                    }
                }
                if let t = selected {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("إرسال") {
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
            Section("القالب") {
                Text(t.name).font(.headline).foregroundStyle(Theme.onSurface)
                if let preview = t.bodyText { Text(preview).font(.caption).foregroundStyle(Theme.onMuted) }
            }
            if t.bodyParams > 0 {
                Section("المتغيرات") {
                    ForEach(0..<t.bodyParams, id: \.self) { i in
                        TextField("المتغير \(i + 1)", text: Binding(
                            get: { i < params.count ? params[i] : "" },
                            set: { v in if i < params.count { params[i] = v } }
                        ))
                    }
                }
            } else {
                Section { Text("لا متغيرات في هذا القالب").foregroundStyle(Theme.onMuted) }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
    }
}

func clockTime(_ iso: String?) -> String {
    guard let iso else { return "" }
    let parser = ISO8601DateFormatter(); parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    guard let date else { return "" }
    let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
}

func mimeType(for url: URL) -> String {
    UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
}

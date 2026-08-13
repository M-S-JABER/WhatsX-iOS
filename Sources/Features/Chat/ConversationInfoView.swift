import SwiftUI

// Conversation info sheet (web parity: ConversationInfoDrawer) — a contact
// card plus galleries of everything shared in the thread, extracted
// client-side from the loaded messages: images, documents, and links.
struct ConversationInfoView: View {
    let conversation: Conversation
    let messages: [Message]
    @Environment(\.dismiss) private var dismiss
    @State private var tab: InfoTab = .about

    enum InfoTab: String, CaseIterable {
        case about, media, files, links
        var title: String {
            switch self {
            case .about: return L("حول")
            case .media: return L("الوسائط")
            case .files: return L("الملفات")
            case .links: return L("الروابط")
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker(L("القسم"), selection: $tab) {
                    ForEach(InfoTab.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 10)

                ScrollView {
                    switch tab {
                    case .about: aboutSection
                    case .media: mediaSection
                    case .files: filesSection
                    case .links: linksSection
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(conversation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L("إغلاق")) { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 10) {
            Avatar(name: conversation.title, size: 76)
                .padding(.top, 14)
            Text(conversation.title).font(.wx(20, .bold)).foregroundStyle(Theme.onSurface)
            if let phone = conversation.phone, !phone.isEmpty {
                Text(phone).font(.wx(15)).foregroundStyle(Theme.onMuted)
                    .environment(\.layoutDirection, .leftToRight)
            }

            VStack(spacing: 0) {
                if let acct = conversation.instance?.label {
                    infoRow(L("حساب واتساب"), acct)
                }
                if let status = conversation.metadata?.status, !status.isEmpty {
                    infoRow(L("الحالة"), status)
                }
                if let about = conversation.metadata?.about, !about.isEmpty {
                    infoRow(L("نبذة"), about)
                }
                if let seen = conversation.metadata?.lastSeenAt, let date = parseISODate(seen) {
                    infoRow(L("آخر ظهور"), seenText(date))
                }
                if let site = conversation.metadata?.website, !site.isEmpty {
                    HStack {
                        Text(L("الموقع")).font(.wx(13)).foregroundStyle(Theme.onMuted)
                        Spacer()
                        if let url = URL(string: site) {
                            Link(site, destination: url)
                                .font(.wx(13, .medium)).foregroundStyle(Theme.primary)
                                .lineLimit(1)
                        } else {
                            Text(site).font(.wx(13)).foregroundStyle(Theme.onSurface).lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                }
            }
            .glassCard(18)
            .padding(.horizontal, 16)

            if let labels = conversation.metadata?.labels, !labels.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("التصنيفات")).font(.wx(13, .semibold)).foregroundStyle(Theme.onMuted)
                    FlowChips(labels: labels)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
            Spacer(minLength: 20)
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).font(.wx(13)).foregroundStyle(Theme.onMuted)
            Spacer()
            Text(value).font(.wx(13, .medium)).foregroundStyle(Theme.onSurface)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func seenText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.dateLocale
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: date)
    }

    // MARK: - Shared content extraction

    private var imageMessages: [Message] {
        messages.filter { m in
            guard let media = m.media, media.url?.isEmpty == false else { return false }
            return media.mediaType == "image" || (media.mimeType?.hasPrefix("image/") ?? false)
        }
    }

    private var fileMessages: [Message] {
        messages.filter { m in
            guard let media = m.media, media.url?.isEmpty == false else { return false }
            let isImage = media.mediaType == "image" || (media.mimeType?.hasPrefix("image/") ?? false)
            let isAudio = media.mediaType == "audio" || (media.mimeType?.hasPrefix("audio/") ?? false)
            return !isImage && !isAudio
        }
    }

    private var sharedLinks: [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        var seen = Set<String>()
        var out: [URL] = []
        for m in messages {
            guard let body = m.body, !body.isEmpty else { continue }
            let range = NSRange(body.startIndex..., in: body)
            for match in detector.matches(in: body, options: [], range: range) {
                guard let url = match.url, url.scheme?.hasPrefix("http") == true else { continue }
                if seen.insert(url.absoluteString).inserted { out.append(url) }
            }
        }
        return out
    }

    // MARK: - Media / files / links tabs

    private var mediaSection: some View {
        Group {
            if imageMessages.isEmpty {
                emptyState(L("لا وسائط مشتركة"))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                    ForEach(imageMessages) { m in
                        if let url = Api.mediaURL(m.media?.url) {
                            RemoteImage(url: url, targetSize: 120) { Theme.surface2 }
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .frame(height: 110)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 16)
            }
        }
    }

    private var filesSection: some View {
        Group {
            if fileMessages.isEmpty {
                emptyState(L("لا ملفات مشتركة"))
            } else {
                VStack(spacing: 8) {
                    ForEach(fileMessages) { m in
                        if let url = Api.mediaURL(m.media?.url) {
                            Link(destination: url) {
                                HStack(spacing: 10) {
                                    Image(icon: .doc).foregroundStyle(Theme.primary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.media?.mimeType ?? L("مستند"))
                                            .font(.wx(13, .medium)).foregroundStyle(Theme.onSurface)
                                            .lineLimit(1)
                                        Text(clockTime(m.createdAt)).font(.wx(11)).foregroundStyle(Theme.onFaint)
                                    }
                                    Spacer()
                                    Image(icon: .download).foregroundStyle(Theme.onMuted)
                                }
                                .padding(12)
                                .glassCard(14)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private var linksSection: some View {
        Group {
            if sharedLinks.isEmpty {
                emptyState(L("لا روابط مشتركة"))
            } else {
                VStack(spacing: 8) {
                    ForEach(sharedLinks, id: \.absoluteString) { url in
                        Link(destination: url) {
                            HStack(spacing: 10) {
                                Image(systemName: "link").font(.wx(15)).foregroundStyle(Theme.primary)
                                Text(url.absoluteString)
                                    .font(.wx(13)).foregroundStyle(Theme.onSurface)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .environment(\.layoutDirection, .leftToRight)
                                Spacer()
                            }
                            .padding(12)
                            .glassCard(14)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.wx(15)).foregroundStyle(Theme.onMuted)
            .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

/// Simple wrapping chip row for read-only labels.
private struct FlowChips: View {
    let labels: [String]

    var body: some View {
        // A simple grid keeps iOS 16 compatibility (Layout-based flow not needed).
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.wx(12))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.primarySoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.primaryContainer, lineWidth: 1))
            }
        }
    }
}

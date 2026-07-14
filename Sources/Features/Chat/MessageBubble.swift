import SwiftUI
import MapKit
import UIKit

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

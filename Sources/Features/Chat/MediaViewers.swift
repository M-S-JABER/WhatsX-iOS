import SwiftUI
import WebKit
import UIKit
import AVKit
import AVFoundation

// Rich media viewers (web parity: MessageBubble lightbox / OfficePreview).

/// Identifiable wrapper so URLs can drive fullScreenCover/sheet(item:).
struct MediaItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// Full-screen image lightbox with pinch-zoom and drag-pan (web parity:
/// the MessageBubble image lightbox).
struct ImageLightbox: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: item.url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = max(1, min(6, lastScale * value))
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1.02 { resetZoom() }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard scale > 1 else { return }
                        offset = CGSize(width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring()) {
                    if scale > 1 { resetZoom() } else { scale = 2.5; lastScale = 2.5 }
                }
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.wx(15, .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding(16)
        }
    }

    private func resetZoom() {
        withAnimation(.spring()) {
            scale = 1; lastScale = 1
            offset = .zero; lastOffset = .zero
        }
    }
}

/// Document preview sheet — WKWebView renders PDFs and Office files natively
/// (web parity: the iframe/OfficePreview document viewers).
struct DocPreviewSheet: View {
    let item: MediaItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebDocView(url: item.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(L("مستند"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("إغلاق")) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Link(destination: item.url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

struct WebDocView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// UIActivityViewController wrapper for sharing generated files (PDF export).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Compact link-preview card for the first URL in a message body
/// (web parity: extractFirstUrl + the URL chip card).
struct LinkPreviewCard: View {
    let url: URL
    let fg: Color

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 9) {
                Image(systemName: "link")
                    .font(.wx(14, .semibold)).foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primary.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.host ?? url.absoluteString)
                        .font(.wx(12.5, .semibold)).foregroundStyle(fg).lineLimit(1)
                    if !url.path.isEmpty && url.path != "/" {
                        Text(url.path)
                            .font(.wx(11)).foregroundStyle(fg.opacity(0.65)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.wx(11, .semibold)).foregroundStyle(fg.opacity(0.55))
            }
            .padding(8)
            .frame(minWidth: 200)
            .background(fg.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .environment(\.layoutDirection, .leftToRight)
        }
        .buttonStyle(.plain)
    }
}

/// Built once — creating an NSDataDetector per bubble per render is costly.
private let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

/// Extract the first http(s) URL from a message body.
func firstURL(in body: String?) -> URL? {
    guard let body, !body.isEmpty, let detector = linkDetector
    else { return nil }
    let range = NSRange(body.startIndex..., in: body)
    for match in detector.matches(in: body, options: [], range: range) {
        if let url = match.url, url.scheme?.hasPrefix("http") == true { return url }
    }
    return nil
}

/// Video bubble that OWNS its player. Building `AVPlayer(url:)` inline in a
/// bubble's body allocated a fresh player + network stack on every re-render
/// (every keystroke, every realtime event) and never tore them down.
struct VideoBubble: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(width: 230, height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .onAppear {
                guard player == nil else { return }
                // Same cookie pass-through as AudioMessage — media is behind
                // the session auth.
                let cookies = HTTPCookieStorage.shared.cookies ?? []
                let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
                player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            }
            .onDisappear {
                player?.pause()
                player = nil
            }
    }
}

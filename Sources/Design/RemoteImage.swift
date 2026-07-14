import SwiftUI
import ImageIO
import UIKit

/// Downsampled remote image with an in-memory cache. Unlike AsyncImage, the
/// bitmap is decoded at the TARGET pixel size (CGImageSource thumbnailing),
/// so a 4000px photo shown in a 48pt avatar or a 110pt grid cell costs a
/// thumbnail's memory, not the full frame. Requests go through the shared
/// cookie storage, so authenticated media loads like the rest of the app.
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    /// Longest edge the image will be displayed at, in points.
    let targetSize: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            let maxPixel = targetSize * UIScreen.main.scale
            if let cached = ImageCache.shared.cached(url: url, maxPixel: maxPixel) {
                image = cached
                return
            }
            let loaded = await ImageCache.shared.load(url: url, maxPixel: maxPixel)
            if !Task.isCancelled { image = loaded }
        }
    }
}

/// Downloads + downsamples images, keeping decoded thumbnails in an NSCache.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = .shared
        cfg.httpShouldSetCookies = true
        cfg.urlCache = URLCache.shared
        return URLSession(configuration: cfg)
    }()

    init() {
        cache.countLimit = 300
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(url.absoluteString)@\(Int(maxPixel))" as NSString
    }

    func cached(url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    /// Runs off the main actor (nonisolated async): network + decode never
    /// block the UI.
    func load(url: URL, maxPixel: CGFloat) async -> UIImage? {
        guard let (data, _) = try? await session.data(from: url) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: key(url, maxPixel))
        return image
    }
}

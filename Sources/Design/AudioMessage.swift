import SwiftUI
import AVFoundation

// Voice-note player for chat bubbles: round primary play button + a static bar
// waveform + duration. Plays authenticated media by passing the session cookies
// to AVURLAsset (AsyncImage already uses the shared cookie storage automatically).
struct AudioMessage: View {
    let url: URL
    let tint: Color

    @State private var player: AVPlayer?
    @State private var playing = false
    @State private var observer: Any?

    private let heights: [CGFloat] = [8, 14, 20, 12, 24, 16, 22, 10, 18, 24, 14, 8, 20, 12, 16, 22, 10, 6, 14, 18]

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.wx(16))
                    .foregroundStyle(Theme.onPrimary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primary, in: Circle())
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    Capsule().fill(tint.opacity(0.5)).frame(width: 2.5, height: h)
                }
            }
            .frame(height: 26)
        }
        .frame(minWidth: 180)
        .onDisappear {
            player?.pause()
            playing = false
            // The end-of-play observer captures the player — failing to
            // remove it leaked a player per voice note viewed.
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }
            player = nil
        }
    }

    private func toggle() {
        if player == nil {
            let cookies = HTTPCookieStorage.shared.cookies ?? []
            let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPCookiesKey: cookies])
            let item = AVPlayerItem(asset: asset)
            let p = AVPlayer(playerItem: item)
            observer = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { _ in
                playing = false
                p.seek(to: .zero)
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            }
            player = p
        }
        if playing {
            player?.pause()
        } else {
            // .playback beats the silent switch — a voice note the operator
            // taps must be audible regardless of the mute toggle.
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
        playing.toggle()
    }
}

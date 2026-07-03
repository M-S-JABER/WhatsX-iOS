import SwiftUI

// Circular avatar: shows the remote image when present, else colored initials.
// The fill color is derived from the name (multi-color, like Android's Avatar).
struct Avatar: View {
    let name: String
    var imageURL: URL? = nil
    var size: CGFloat = 48

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return letters.isEmpty ? L("؟") : letters
    }

    var body: some View {
        ZStack {
            AccountColor.color(name)
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Text(initials).font(.wx(size * 0.38, .semibold)).foregroundStyle(.white)
                }
            } else {
                Text(initials).font(.wx(size * 0.38, .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

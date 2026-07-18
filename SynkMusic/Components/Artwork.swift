import SwiftUI

// Remote artwork with a note-icon fallback, rounded (album) or circular (artist).
struct Artwork: View {
    let url: String
    var round: Bool = false
    var corner: CGFloat = 8

    var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                fallback
            }
        }
        .background(Theme.surface2)
        .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: corner, style: .continuous)))
    }

    private var fallback: some View {
        ZStack {
            Theme.surface2
            SynkIcon(vector: SynkIcons.musicNote, size: 28, tint: Theme.faint)
        }
    }
}

enum Format {
    static func time(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    static func time(_ seconds: Double) -> String {
        time(Int(seconds.isFinite ? seconds : 0))
    }
}

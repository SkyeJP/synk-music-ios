import SwiftUI

struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerController
    var onExpand: () -> Void

    var body: some View {
        if let track = player.current {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Artwork(url: track.coverURL, corner: 6)
                        .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.displayTitle)
                            .font(SynkFont.sans(14, .semibold))
                            .foregroundStyle(Theme.fg)
                            .lineLimit(1)
                        Text(track.artist)
                            .font(SynkFont.sans(12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)

                    LikeButton(track: track)

                    Button { player.toggle() } label: {
                        SynkIcon(vector: player.isPlaying ? SynkIcons.pause : SynkIcons.play,
                                 size: 22, tint: Theme.fg)
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                GeometryReader { geo in
                    let frac = player.duration > 0 ? player.position / player.duration : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.line).frame(height: 2)
                        Rectangle().fill(Theme.fg)
                            .frame(width: max(0, geo.size.width * frac), height: 2)
                    }
                }
                .frame(height: 2)
            }
            .background(Theme.surface1)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 0.5))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .onTapGesture(perform: onExpand)
        }
    }
}

import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack {
            Theme.surface1.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Queue")
                        .font(SynkFont.sans(20, .bold))
                        .foregroundStyle(Theme.fg)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                        .padding(.bottom, 8)

                    ForEach(Array(player.queue.enumerated()), id: \.offset) { i, t in
                        HStack(spacing: 12) {
                            if i == player.index {
                                SynkIcon(vector: player.isPlaying ? SynkIcons.pause : SynkIcons.play,
                                         size: 14, tint: Theme.fg)
                                    .frame(width: 26)
                            } else {
                                Text("\(i + 1)")
                                    .font(SynkFont.sans(13))
                                    .foregroundStyle(Theme.faint)
                                    .frame(width: 26, alignment: .leading)
                            }
                            Artwork(url: t.coverURL, corner: 6).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.displayTitle)
                                    .font(SynkFont.sans(15, .medium))
                                    .foregroundStyle(i == player.index ? Theme.fg : Theme.fg)
                                    .lineLimit(1)
                                Text(t.artist).font(SynkFont.sans(13)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                        .onTapGesture { player.playIndex(i) }
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }
}

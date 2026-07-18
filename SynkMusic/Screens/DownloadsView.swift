import SwiftUI

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let tracks = downloads.downloadedTracks
                if tracks.isEmpty {
                    Text("No downloads yet")
                        .font(SynkFont.sans(14))
                        .foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    ForEach(tracks) { t in
                        TrackRow(track: t, showLike: false) { player.playNow(t, in: tracks) }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

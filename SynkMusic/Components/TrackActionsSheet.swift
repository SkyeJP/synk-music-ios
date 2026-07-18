import SwiftUI

// The "…" sheet: download toggle + add-to-playlist, mirroring the Android
// AddToPlaylistSheet.
struct TrackActionsSheet: View {
    let track: Track
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var settings: SettingsStore

    @State private var playlists: [Playlist] = []
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(SynkFont.sans(17, .bold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(track.artist)
                    .font(SynkFont.sans(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.bottom, 16)

            // Download / remove
            Button {
                downloads.toggle(track, quality: settings.audioQuality)
            } label: {
                let done = downloads.isDownloaded(track)
                let busy = downloads.downloading.contains(downloads.key(track))
                HStack(spacing: 14) {
                    SynkIcon(vector: done ? SynkIcons.check : SynkIcons.download,
                             size: 22, tint: done ? Theme.fg : Theme.muted)
                    Text(busy ? "Downloading…" : done ? "Remove download" : "Download")
                        .font(SynkFont.sans(15, .medium))
                        .foregroundStyle(Theme.fg)
                    Spacer()
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Eyebrow(text: "Add to playlist").padding(.top, 8).padding(.bottom, 6)

            if let status = status {
                Text(status).font(SynkFont.sans(13)).foregroundStyle(Theme.muted).padding(.vertical, 8)
            }

            if playlists.isEmpty {
                Text("No playlists yet").font(SynkFont.sans(14)).foregroundStyle(Theme.faint).padding(.vertical, 16)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(playlists) { pl in
                            Button { add(to: pl) } label: {
                                HStack(spacing: 12) {
                                    Artwork(url: pl.coverURL, corner: 6).frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pl.name.isEmpty ? "Playlist" : pl.name)
                                            .font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                                        Text("\(pl.trackCount) songs").font(SynkFont.sans(12)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface1.ignoresSafeArea())
        .task {
            playlists = (try? await API.shared.playlists().data) ?? []
        }
    }

    private func add(to pl: Playlist) {
        Task {
            do {
                try await API.shared.addToPlaylist(pl.id, hashes: [track.hash])
                status = "Added to \(pl.name)"
            } catch {
                status = "Couldn't add"
            }
        }
    }
}

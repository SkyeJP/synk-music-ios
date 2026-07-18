import SwiftUI

struct TrackRow: View {
    let track: Track
    var index: Int? = nil
    var showLike: Bool = true
    var onTap: () -> Void

    @State private var showSheet = false

    var body: some View {
        HStack(spacing: 12) {
            if let index = index {
                Text("\(index + 1)")
                    .font(SynkFont.sans(13))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 26, alignment: .leading)
            }
            Artwork(url: track.coverURL, corner: 6)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.displayTitle)
                    .font(SynkFont.sans(15, .medium))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(track.artist)
                    .font(SynkFont.sans(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)

            if showLike { LikeButton(track: track) }
            Button { showSheet = true } label: {
                SynkIcon(vector: SynkIcons.more, size: 18, tint: Theme.muted)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .sheet(isPresented: $showSheet) {
            TrackActionsSheet(track: track)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct LikeButton: View {
    let track: Track
    var size: CGFloat = 20
    @EnvironmentObject private var likes: LikesStore

    var body: some View {
        Button { likes.toggle(track) } label: {
            SynkIcon(
                vector: likes.isLiked(track) ? SynkIcons.heartFilled : SynkIcons.heart,
                size: size,
                tint: likes.isLiked(track) ? Theme.fg : Theme.muted
            )
            .frame(width: size + 16, height: size + 16)
        }
        .buttonStyle(.plain)
    }
}

struct DownloadButton: View {
    let track: Track
    var size: CGFloat = 22
    var tint: Color = Theme.muted
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        let key = downloads.key(track)
        let done = downloads.isDownloaded(track)
        let busy = downloads.downloading.contains(key)
        Button {
            downloads.toggle(track, quality: settings.audioQuality)
        } label: {
            SynkIcon(
                vector: done ? SynkIcons.check : SynkIcons.download,
                size: size,
                tint: (done || busy) ? Theme.fg : tint
            )
            .frame(width: size + 16, height: size + 16)
        }
        .buttonStyle(.plain)
    }
}

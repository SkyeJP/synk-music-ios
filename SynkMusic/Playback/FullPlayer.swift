import SwiftUI

struct FullPlayer: View {
    @EnvironmentObject private var player: PlayerController
    var onClose: () -> Void

    @State private var showLyrics = false
    @State private var showQueue = false
    @State private var dominant: Color = Theme.surface3
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        if let track = player.current {
            ZStack {
                LinearGradient(
                    colors: [dominant.opacity(0.85), dominant.opacity(0.35), Theme.ink],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: dominant)

                VStack(spacing: 0) {
                    header(track)

                    Spacer(minLength: 0)

                    Artwork(url: track.coverURL, corner: 10)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .padding(.horizontal, 8)
                        .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

                    Spacer(minLength: 24)

                    titleBlock(track)
                    scrubber
                    transport
                    bottomActions
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .task(id: track.coverURL) {
                dominant = await DominantColor.extract(from: track.coverURL) ?? Theme.surface3
            }
            .sheet(isPresented: $showLyrics) {
                LyricsView(track: track)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showQueue) {
                QueueView()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func header(_ track: Track) -> some View {
        HStack {
            Button(action: onClose) {
                SynkIcon(vector: SynkIcons.chevronDown, size: 28, tint: Theme.fg)
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Eyebrow(text: "Playing from", color: Theme.fg.opacity(0.7))
                Text(track.album.isEmpty ? "SYNK Music" : track.album)
                    .font(SynkFont.sans(13, .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
            }
            Spacer()
            DownloadButton(track: track, tint: Theme.fg)
        }
    }

    private func titleBlock(_ track: Track) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.displayTitle)
                    .font(SynkFont.sans(22, .bold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(track.artist)
                    .font(SynkFont.sans(15))
                    .foregroundStyle(Theme.fg.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer()
            LikeButton(track: track, size: 26)
        }
        .padding(.bottom, 16)
    }

    private var scrubber: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : player.position },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { player.seek(to: scrubValue) }
                }
            )
            .tint(Theme.fg)

            HStack {
                Text(Format.time(scrubbing ? scrubValue : player.position))
                Spacer()
                Text(Format.time(player.duration))
            }
            .font(SynkFont.sans(11))
            .foregroundStyle(Theme.fg.opacity(0.65))
        }
        .padding(.bottom, 12)
    }

    private var transport: some View {
        HStack {
            Button { player.toggleShuffle() } label: {
                SynkIcon(vector: player.shuffle ? SynkIcons.shuffleActive : SynkIcons.shuffle,
                         size: 22, tint: player.shuffle ? Theme.fg : Theme.fg.opacity(0.6))
            }.buttonStyle(.plain)
            Spacer()
            Button { player.previous() } label: {
                SynkIcon(vector: SynkIcons.skipPrevious, size: 36, tint: Theme.fg)
            }.buttonStyle(.plain)
            Spacer()
            Button { player.toggle() } label: {
                ZStack {
                    Circle().fill(Theme.fg).frame(width: 72, height: 72)
                    SynkIcon(vector: player.isPlaying ? SynkIcons.pause : SynkIcons.play,
                             size: 32, tint: Theme.ink)
                }
            }.buttonStyle(.plain)
            Spacer()
            Button { player.next() } label: {
                SynkIcon(vector: SynkIcons.skipNext, size: 36, tint: Theme.fg)
            }.buttonStyle(.plain)
            Spacer()
            Button { player.cycleRepeat() } label: {
                SynkIcon(vector: SynkIcons.repeatIcon, size: 22,
                         tint: player.repeatMode != .off ? Theme.fg : Theme.fg.opacity(0.6))
            }.buttonStyle(.plain)
        }
        .padding(.vertical, 16)
    }

    private var bottomActions: some View {
        HStack(spacing: 40) {
            Button { showLyrics = true } label: {
                Text("Lyrics").font(SynkFont.sans(14, .semibold)).foregroundStyle(Theme.fg)
            }.buttonStyle(.plain)
            Button { showQueue = true } label: {
                Text("Queue").font(SynkFont.sans(14, .semibold)).foregroundStyle(Theme.fg)
            }.buttonStyle(.plain)
        }
        .padding(.top, 8)
    }
}

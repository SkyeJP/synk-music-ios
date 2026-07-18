import SwiftUI

@MainActor
final class LyricsViewModel: ObservableObject {
    @Published var lines: [LyricLine] = []
    @Published var synced = false
    @Published var loading = true
    @Published var error = false

    func load(_ track: Track) async {
        loading = true; error = false
        defer { loading = false }
        do {
            let res = try await API.shared.lyrics(
                artist: track.artist, title: track.displayTitle,
                duration: track.durationSeconds > 0 ? track.durationSeconds : nil,
                isrc: track.isrc
            )
            lines = res.lyrics
            synced = res.synced
            error = res.lyrics.isEmpty
        } catch {
            self.error = true
        }
    }
}

struct LyricsView: View {
    let track: Track
    @StateObject private var vm = LyricsViewModel()
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        ZStack {
            Theme.surface1.ignoresSafeArea()
            if vm.loading {
                ProgressView().tint(Theme.fg)
            } else if vm.error {
                VStack(spacing: 8) {
                    SynkIcon(vector: SynkIcons.musicNote, size: 40, tint: Theme.faint)
                    Text("No lyrics available").font(SynkFont.sans(15)).foregroundStyle(Theme.muted)
                }
            } else {
                lyricsScroller
            }
        }
        .task { await vm.load(track) }
    }

    private var currentIndex: Int {
        guard vm.synced else { return -1 }
        let ms = Int(player.position * 1000)
        var idx = -1
        for (i, line) in vm.lines.enumerated() where line.time <= ms { idx = i }
        return idx
    }

    private var lyricsScroller: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(vm.lines.enumerated()), id: \.offset) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(SynkFont.lyrics(24, .bold))
                            .foregroundStyle(colorFor(i))
                            .id(i)
                            .onTapGesture {
                                if vm.synced { player.seek(to: Double(line.time) / 1000) }
                            }
                            .animation(.easeInOut(duration: 0.25), value: currentIndex)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: currentIndex) { _, idx in
                guard idx >= 0 else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }

    private func colorFor(_ i: Int) -> Color {
        guard vm.synced else { return Theme.fg.opacity(0.85) }
        if i == currentIndex { return Theme.fg }
        if i < currentIndex { return Theme.faint }
        return Theme.muted.opacity(0.6)
    }
}

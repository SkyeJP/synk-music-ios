import SwiftUI

@MainActor
final class DetailViewModel: ObservableObject {
    @Published var title = ""
    @Published var subtitle = ""
    @Published var kind = ""
    @Published var image = ""
    @Published var round = false
    @Published var tracks: [Track] = []
    @Published var loading = true

    func loadAlbum(_ hash: String) async {
        async let info = try? API.shared.albumInfo(hash)
        async let trks = try? API.shared.albumTracks(hash)
        if let a = await info {
            title = a.displayTitle; subtitle = a.artist; kind = "Album"; image = a.image
        }
        tracks = (await trks)?.tracks ?? []
        loading = false
    }

    func loadArtist(_ hash: String) async {
        async let info = try? API.shared.artistInfo(hash)
        async let trks = try? API.shared.artistTracks(hash)
        if let a = await info {
            title = a.name; subtitle = ""; kind = "Artist"; image = a.image; round = true
        }
        tracks = (await trks)?.tracks ?? []
        loading = false
    }

    func loadPlaylist(_ id: String) async {
        if let d = try? await API.shared.playlist(id) {
            title = d.info.name; kind = "Playlist"; subtitle = "\(d.info.trackCount) songs"
            image = d.info.coverURL; tracks = d.tracks
        }
        loading = false
    }
}

struct DetailView: View {
    let route: Route
    @StateObject private var vm = DetailViewModel()
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Artwork(url: vm.image, round: vm.round, corner: 14)
                    .frame(width: 200, height: 200)
                    .padding(.top, 8)

                Eyebrow(text: vm.kind).padding(.top, 16)
                Text(vm.title)
                    .font(SynkFont.sans(24, .bold))
                    .foregroundStyle(Theme.fg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                if !vm.subtitle.isEmpty {
                    Text(vm.subtitle).font(SynkFont.sans(14)).foregroundStyle(Theme.muted)
                }

                HStack(spacing: 10) {
                    Button {
                        if let first = vm.tracks.first { player.playNow(first, in: vm.tracks) }
                    } label: {
                        HStack(spacing: 6) {
                            SynkIcon(vector: SynkIcons.play, size: 18, tint: Theme.ink)
                            Text("Play").font(SynkFont.sans(15, .semibold)).foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Theme.fg).clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    if vm.kind != "Artist" && !vm.tracks.isEmpty {
                        Button { downloadAll() } label: {
                            let allDone = vm.tracks.allSatisfy { downloads.isDownloaded($0) }
                            SynkIcon(vector: allDone ? SynkIcons.check : SynkIcons.download,
                                     size: 24, tint: allDone ? Theme.fg : Theme.muted)
                                .frame(width: 46, height: 46)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 20)

                LazyVStack(spacing: 0) {
                    ForEach(Array(vm.tracks.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, index: i) { player.playNow(t, in: vm.tracks) }
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .overlay { if vm.loading { ProgressView().tint(Theme.fg) } }
        .task {
            switch route {
            case .album(let h): await vm.loadAlbum(h)
            case .artist(let h): await vm.loadArtist(h)
            case .playlist(let id): await vm.loadPlaylist(id)
            }
        }
    }

    private func downloadAll() {
        for t in vm.tracks { downloads.download(t, quality: settings.audioQuality) }
    }
}

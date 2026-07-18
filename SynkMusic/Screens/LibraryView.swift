import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var playlists: [Playlist] = []
    @Published var likedTracks: [Track] = []
    @Published var recent: [Track] = []
    @Published var loading = false

    func load() async {
        if !playlists.isEmpty || !likedTracks.isEmpty { return }
        loading = true
        defer { loading = false }
        async let pl = try? await API.shared.playlists()
        async let lk = try? await API.shared.liked()
        async let rc = try? await API.shared.recent()
        playlists = (await pl)?.data ?? []
        likedTracks = (await lk)?.tracks ?? []
        recent = (await rc)?.tracks ?? []
    }
}

struct LibraryView: View {
    @StateObject private var vm = LibraryViewModel()
    @EnvironmentObject private var player: PlayerController

    enum Filter: String, CaseIterable { case playlists = "Playlists", liked = "Liked", recent = "Recent" }
    @State private var filter: Filter = .playlists

    var body: some View {
        VStack(spacing: 0) {
            Text("Your Library")
                .font(SynkFont.sans(23, .heavy))
                .foregroundStyle(Theme.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.rawValue) { f in
                        Button { filter = f } label: {
                            Text(f.rawValue)
                                .font(SynkFont.sans(13, .semibold))
                                .foregroundStyle(filter == f ? Theme.ink : Theme.fg)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(filter == f ? Theme.fg : Theme.surface2)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    switch filter {
                    case .playlists:
                        ForEach(vm.playlists) { pl in
                            NavigationLink(value: Route.playlist(pl.id)) {
                                libraryRow(image: pl.coverURL, title: pl.name.isEmpty ? "Playlist" : pl.name,
                                           subtitle: "\(pl.trackCount) songs", round: false)
                            }
                            .buttonStyle(.plain)
                        }
                    case .liked:
                        ForEach(vm.likedTracks) { t in
                            TrackRow(track: t) { player.playNow(t, in: vm.likedTracks) }
                        }
                    case .recent:
                        ForEach(vm.recent) { t in
                            TrackRow(track: t) { player.playNow(t, in: vm.recent) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.ink)
        .navigationBarHidden(true)
        .navigationDestination(for: Route.self) { DetailView(route: $0) }
        .overlay { if vm.loading { ProgressView().tint(Theme.fg) } }
        .task { await vm.load() }
    }

    private func libraryRow(image: String, title: String, subtitle: String, round: Bool) -> some View {
        HStack(spacing: 12) {
            Artwork(url: image, round: round, corner: 6).frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(SynkFont.sans(15, .medium)).foregroundStyle(Theme.fg).lineLimit(1)
                Text(subtitle).font(SynkFont.sans(13)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            SynkIcon(vector: SynkIcons.chevronRight, size: 16, tint: Theme.faint)
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}

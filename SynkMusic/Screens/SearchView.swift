import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var tracks: [Track] = []
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var loading = false

    private var task: Task<Void, Never>?

    func onQueryChange() {
        task?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { tracks = []; albums = []; artists = []; return }
        task = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            loading = true
            defer { loading = false }
            async let t = try? await API.shared.search(q, type: "tracks", limit: 20)
            async let al = try? await API.shared.search(q, type: "albums", limit: 12)
            async let ar = try? await API.shared.search(q, type: "artists", limit: 12)
            let (tr, alb, art) = await (t, al, ar)
            if Task.isCancelled { return }
            tracks = tr?.results.isEmpty == false ? tr!.results : (tr?.tracks ?? [])
            albums = alb?.albums ?? []
            artists = art?.artists ?? []
        }
    }
}

struct SearchView: View {
    @StateObject private var vm = SearchViewModel()
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !vm.artists.isEmpty {
                        SectionHeader("Artists")
                        horizontal(vm.artists.map {
                            (id: $0.hash, image: $0.image, title: $0.name, subtitle: "Artist",
                             round: true, route: Route.artist($0.hash))
                        })
                    }
                    if !vm.albums.isEmpty {
                        SectionHeader("Albums")
                        horizontal(vm.albums.map {
                            (id: $0.hash, image: $0.image, title: $0.displayTitle, subtitle: $0.artist,
                             round: false, route: Route.album($0.hash))
                        })
                    }
                    if !vm.tracks.isEmpty {
                        SectionHeader("Songs")
                        ForEach(vm.tracks) { t in
                            TrackRow(track: t) { player.playNow(t, in: vm.tracks) }
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.ink)
        .navigationBarHidden(true)
        .navigationDestination(for: Route.self) { DetailView(route: $0) }
        .overlay { if vm.loading && vm.tracks.isEmpty { ProgressView().tint(Theme.fg) } }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            SynkIcon(vector: SynkIcons.search, size: 18, tint: Theme.muted)
            TextField("", text: $vm.query, prompt: Text("Search songs, artists, albums").foregroundColor(Theme.faint))
                .font(SynkFont.sans(15))
                .foregroundStyle(Theme.fg)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: vm.query) { _, _ in vm.onQueryChange() }
            if !vm.query.isEmpty {
                Button { vm.query = ""; vm.onQueryChange() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
    }

    private func horizontal(_ items: [(id: String, image: String, title: String, subtitle: String, round: Bool, route: Route)]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(items, id: \.id) { item in
                    NavigationLink(value: item.route) {
                        VStack(alignment: .leading, spacing: 8) {
                            Artwork(url: item.image, round: item.round).frame(width: 120, height: 120)
                            Text(item.title).font(SynkFont.sans(13, .semibold)).foregroundStyle(Theme.fg).lineLimit(1)
                            Text(item.subtitle).font(SynkFont.sans(11)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        .frame(width: 120)
                        .padding(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(SynkFont.sans(17, .bold))
            .foregroundStyle(Theme.fg)
            .padding(.leading, 16).padding(.top, 20).padding(.bottom, 10)
    }
}

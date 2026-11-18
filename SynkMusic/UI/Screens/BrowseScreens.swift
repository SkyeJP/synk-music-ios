import SwiftUI

// MARK: shared pieces (components/m/ui.tsx)

/// Horizontal shelf that snaps to its cards.
struct Shelf<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) { content() }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
        }
        .scrollTargetBehavior(.viewAligned)
    }
}

struct SectionHead: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).font(sans: 22, 700).tracking(-0.2).foregroundStyle(Theme.fg)
            .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "Top Picks" card: cover with a colour panel from the artwork underneath.
struct PickCard: View {
    let cover: String
    let title: String
    let sub: String
    let reason: String
    let action: () -> Void
    @State private var panel = Color(hex: 0x141414)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Artwork(url: cover, radius: 0).frame(width: 250, height: 250)
                VStack(alignment: .leading, spacing: 1) {
                    if !reason.isEmpty { Text(reason.uppercased()).font(sans: 11, 600).tracking(0.7).foregroundStyle(Theme.fg.opacity(0.6)).lineLimit(1) }
                    Text(title).font(sans: 16, 600).foregroundStyle(Theme.fg).lineLimit(1)
                    if !sub.isEmpty { Text(sub).font(sans: 14).foregroundStyle(Theme.fg.opacity(0.7)).lineLimit(1) }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .frame(width: 250, height: 92, alignment: .topLeading)
                .background(panel)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .artTint(cover, value: 0.17, into: $panel)
    }
}

/// Centred collection header: artwork, title, artist, grey meta, Play and Shuffle.
struct CollectionTop: View {
    var cover = ""
    var title = ""
    var artist = ""
    var onArtist: (() -> Void)?
    var meta = ""
    let tracks: [Track]
    var bare = false
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        VStack(spacing: 0) {
            if !bare {
                let side = min(UIScreen.main.bounds.width * 0.68, 280)
                Artwork(url: cover, radius: 10)
                    .frame(width: side, height: side)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 16)
                Text(title).font(display: 22, 700).multilineTextAlignment(.center).foregroundStyle(Theme.fg).padding(.top, 20)
            }
            if !artist.isEmpty {
                Button { onArtist?() } label: {
                    Text(artist).font(sans: 20).foregroundStyle(Theme.fg.opacity(0.75)).lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(onArtist == nil)
                .padding(.top, 2)
            }
            if !meta.isEmpty {
                Text(meta.uppercased()).font(sans: 12, 500).tracking(0.5).foregroundStyle(Theme.fg.opacity(0.45)).padding(.top, 4)
            }
            if !tracks.isEmpty {
                HStack(spacing: 12) {
                    button(SynkIcons.play, "Play") { Playback.play(tracks[0], in: tracks) }
                    button(SynkIcons.shuffle, "Shuffle") {
                        if !player.shuffle { player.setShuffle(true) }
                        let i = Int.random(in: 0..<tracks.count)
                        Playback.play(tracks[i], in: tracks)
                    }
                }
                .padding(.top, bare ? 4 : 20)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func button(_ icon: SynkVector, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SynkIcon(icon, size: 16)
                Text(label).font(sans: 16, 600).foregroundStyle(Theme.fg)
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(PressStyle())
    }
}

struct Loading: View {
    var body: some View {
        Text("Loading").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.45)).frame(maxWidth: .infinity).padding(.vertical, 96)
    }
}

private struct TrackList: View {
    let tracks: [Track]
    var numbered = false
    var limit = Int.max
    var fromPlaylist: String?
    var onRemoved: (() -> Void)?
    @Environment(\.playTrack) private var play

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(tracks.prefix(limit).enumerated()), id: \.offset) { i, t in
                TrackRow(track: t, index: i, numbered: numbered, fromPlaylist: fromPlaylist, onRemoved: onRemoved) { play(t, tracks) }
            }
        }
        .padding(.leading, 6)
    }
}

// MARK: Home

@MainActor
final class HomeModel: ObservableObject {
    @Published var sections: [HomeSection]?
    private static let cacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("home.json")

    init() {
        // The last Home shows straight away; a fresh copy replaces it when it arrives.
        if let d = try? Data(contentsOf: HomeModel.cacheFile), let s = try? JSONDecoder().decode(Keyed<HomeSection>.self, from: d) {
            let items = s.items("sections")
            if !items.isEmpty { sections = items }
        }
    }

    func load() async {
        guard let d = try? await API.shared.data(API.shared.request("library/home", query: ["limit": "14"])),
              let fresh = try? JSONDecoder().decode(Keyed<HomeSection>.self, from: d) else {
            if sections == nil { sections = [] }
            return
        }
        sections = fresh.items("sections")
        try? d.write(to: HomeModel.cacheFile, options: .atomic)
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()
    @Environment(\.navigate) private var navigate
    @Environment(\.playTrack) private var play

    var body: some View {
        LargeTitlePage(title: "Home") {
            if let sections = model.sections {
                if sections.isEmpty {
                    Text("You're offline. Your downloads are in Library.").font(sans: 15).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 96)
                }
                ForEach(Array(sections.enumerated()), id: \.offset) { si, s in
                    SectionHead(s.title)
                    Shelf {
                        ForEach(Array(s.items.enumerated()), id: \.offset) { _, it in
                            card(it, first: si == 0, queue: s.items.filter { $0.kind == .track }.map { $0.track })
                        }
                    }
                }
            } else {
                Loading()
            }
        }
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder private func card(_ it: HomeItem, first: Bool, queue: [Track]) -> some View {
        switch it.kind {
        case .track:
            let t = it.track
            if first {
                PickCard(cover: t.coverUrl, title: t.displayTitle, sub: t.artist, reason: it.reason.isEmpty ? "Picked for you" : it.reason) { play(t, queue) }
            } else {
                ShelfCard(image: t.coverUrl, title: t.displayTitle, subtitle: t.artist) { play(t, queue) }
            }
        case .album:
            let a = it.album
            if first {
                PickCard(cover: a.coverUrl, title: a.displayTitle, sub: a.artist, reason: it.reason.isEmpty ? "Album" : it.reason) { navigate(.album(a.hash)) }
            } else {
                ShelfCard(image: a.coverUrl, title: a.displayTitle, subtitle: a.artist) { navigate(.album(a.hash)) }
            }
        case .artist:
            let a = it.artist
            if first {
                PickCard(cover: a.coverUrl, title: a.name, sub: "Artist", reason: it.reason) { navigate(.artist(a.hash)) }
            } else {
                ShelfCard(image: a.coverUrl, title: a.name, subtitle: "Artist", round: true) { navigate(.artist(a.hash)) }
            }
        }
    }
}

// MARK: Explore

struct ExploreView: View {
    @State private var tracks: [Track]?

    var body: some View {
        LargeTitlePage(title: "Explore") {
            SectionHead("Trending")
            if let tracks { TrackList(tracks: tracks) } else { Loading() }
        }
        .task { if tracks == nil { tracks = (try? await API.shared.trending()) ?? [] } }
        .refreshable { if let t = try? await API.shared.trending() { await MainActor.run { tracks = t } } }
    }
}

// MARK: Radio

/// Artist stations: endless mixes seeded by the artists in your library.
struct RadioView: View {
    @EnvironmentObject private var lib: LibraryModel
    @State private var busy = ""

    var body: some View {
        LargeTitlePage(title: "Radio") {
            Text("Stations built from the artists you listen to.").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
                .padding(.horizontal, 16).padding(.bottom, 4)
            SectionHead("Artist Stations")
            if lib.loading && lib.artists.isEmpty {
                Loading()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 20) {
                    ForEach(Array(lib.artists.prefix(40).enumerated()), id: \.offset) { _, a in
                        Button { start(a.name) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.08))
                                    Text(String(a.name.prefix(1)).uppercased()).font(display: 44, 700).foregroundStyle(Theme.fg.opacity(0.3))
                                    if !a.image.isEmpty { RemoteImage(url: a.image) }
                                }
                                .aspectRatio(1, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                Text("\(a.name) Radio").font(sans: 14, 500).foregroundStyle(Theme.fg).lineLimit(1).padding(.top, 6)
                                Text(busy == a.name ? "Starting" : "Station").font(sans: 13).foregroundStyle(Theme.fg.opacity(0.5))
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .task { if lib.artists.isEmpty { await lib.load() } }
    }

    private func start(_ name: String) {
        busy = name
        Task {
            let list = (try? await API.shared.artistRadio(name)) ?? []
            if let f = list.first { Playback.play(f, in: list) }
            busy = ""
        }
    }
}

// MARK: Search

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var result: SearchResponse?
    @Published var loading = false
    @Published var recent: [String] = UserDefaults.standard.stringArray(forKey: "synk.recentSearches") ?? []
    private(set) var term = ""
    private var job: Task<Void, Never>?

    func change(_ q: String) {
        job?.cancel()
        let t = q.trimmingCharacters(in: .whitespaces)
        job = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            term = t
            if t.count < 2 { result = nil; loading = false; return }
            loading = true
            var r = await API.shared.search(t)
            if Task.isCancelled { return }
            if r.isEmpty {
                // Offline: search what is downloaded.
                r.tracks = DownloadStore.shared.tracks.filter {
                    $0.displayTitle.localizedCaseInsensitiveContains(t) || $0.artist.localizedCaseInsensitiveContains(t)
                }
            }
            result = r
            loading = false
        }
    }

    func remember(_ s: String) {
        let v = s.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        recent = Array(([v] + recent.filter { $0 != v }).prefix(10))
        UserDefaults.standard.set(recent, forKey: "synk.recentSearches")
    }

    func clearRecent() {
        recent = []
        UserDefaults.standard.removeObject(forKey: "synk.recentSearches")
    }
}

struct SearchView: View {
    @StateObject private var model = SearchModel()
    @Environment(\.navigate) private var navigate
    @Environment(\.playTrack) private var play

    var body: some View {
        if #available(iOS 26.0, *) {
            // The search field lives in the Liquid Glass tab bar.
            page(field: false)
                .searchable(text: $model.query, prompt: "Artists, Songs, Albums")
                .onSubmit(of: .search) { model.remember(model.query) }
        } else {
            page(field: true)
        }
    }

    private func page(field: Bool) -> some View {
        LargeTitlePage(title: "Search") {
            if field {
                HStack(spacing: 8) {
                    SynkIcon(SynkIcons.search, size: 20, tint: Theme.fg.opacity(0.5))
                    TextField("", text: $model.query, prompt: Text("Artists, Songs, Albums").foregroundColor(Theme.fg.opacity(0.45)))
                        .font(SynkFont.sans(18))
                        .foregroundStyle(Theme.fg)
                        .tint(Theme.fg)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { model.remember(model.query) }
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            SynkIcon(SynkIcons.plus, size: 14).rotationEffect(.degrees(45))
                                .frame(width: 24, height: 24).background(Circle().fill(Color.white.opacity(0.25)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.1)))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            results
        }
        .onChange(of: model.query) { _, q in model.change(q) }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder private var results: some View {
        if model.result == nil && !model.loading && !model.recent.isEmpty {
            HStack {
                Text("Recently Searched").font(sans: 20, 700).foregroundStyle(Theme.fg)
                Spacer()
                Button { model.clearRecent() } label: { Text("Clear").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.6)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16)
            ForEach(model.recent, id: \.self) { r in
                Button { model.query = r } label: {
                    HStack(spacing: 12) {
                        SynkIcon(SynkIcons.search, size: 20, tint: Theme.fg.opacity(0.45))
                        Text(r).font(sans: 17).foregroundStyle(Theme.fg)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                    .hairline(32)
                    .padding(.leading, 16)
                }
                .buttonStyle(.plain)
            }
        }
        if model.loading && model.result == nil { Loading() }
        if let r = model.result {
            if let top = r.tracks.first {
                SectionHead("Top Result")
                Button { model.remember(model.term); play(top, r.tracks) } label: {
                    HStack(spacing: 12) {
                        Artwork(url: top.coverUrl, radius: 10).frame(width: 80, height: 80)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(top.displayTitle).font(sans: 19, 600).foregroundStyle(Theme.fg).lineLimit(1)
                            Text("Song, \(top.artist)").font(sans: 14).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
                }
                .buttonStyle(PressStyle())
                .padding(.horizontal, 16)
            }
            if !r.tracks.isEmpty {
                SectionHead("Songs")
                TrackList(tracks: r.tracks, limit: 8)
            }
            if !r.albums.isEmpty {
                SectionHead("Albums")
                Shelf {
                    ForEach(Array(r.albums.enumerated()), id: \.offset) { _, a in
                        ShelfCard(image: a.coverUrl, title: a.displayTitle, subtitle: a.artist) { navigate(.album(a.hash)) }
                    }
                }
            }
            if !r.artists.isEmpty {
                SectionHead("Artists")
                Shelf {
                    ForEach(Array(r.artists.enumerated()), id: \.offset) { _, a in
                        ShelfCard(image: a.coverUrl, title: a.name, subtitle: "", size: 120, round: true) { navigate(.artist(a.hash)) }
                    }
                }
            }
            if r.isEmpty {
                Text("No results for \"\(model.term)\".").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
    }
}

// MARK: Library

@MainActor
final class LibraryModel: ObservableObject {
    static let shared = LibraryModel()
    @Published var playlists: [Playlist] = []
    @Published var songs: [Track] = []
    @Published var albums: [Album] = []
    @Published var artists: [Artist] = []
    @Published var loading = false

    func loadPlaylists() async {
        if let p = try? await API.shared.playlists() { playlists = p }
    }

    func load() async {
        loading = true
        async let pls = try? API.shared.playlists()
        async let liked = try? API.shared.liked()
        let p = await pls ?? playlists
        let l = await liked ?? []
        var fromPlaylists: [Track] = []
        await withTaskGroup(of: [Track].self) { g in
            for pl in p { g.addTask { (try? await API.shared.playlist(pl.id).1) ?? [] } }
            for await ts in g { fromPlaylists += ts }
        }
        var seen = Set<String>()
        let all = (l + fromPlaylists).filter { t in
            seen.insert(t.hash.isEmpty ? t.artist.lowercased() + "|" + t.displayTitle.lowercased() : t.hash).inserted
        }
        playlists = p
        if !all.isEmpty || songs.isEmpty { songs = all }
        albums = LibraryModel.albums(songs).sorted { $0.displayTitle.lowercased() < $1.displayTitle.lowercased() }
        var seenA = Set<String>()
        artists = songs.compactMap { t -> Artist? in
            let ref = t.artists.first
            let name = (ref?.name).flatMap { $0.isEmpty ? nil : $0 } ?? (t.artist.isEmpty ? nil : t.artist)
            guard let name, seenA.insert(name.lowercased()).inserted else { return nil }
            return Artist(artisthash: ref?.artisthash ?? "", name: name, image: ref?.image ?? "")
        }
        .sorted { $0.name.lowercased() < $1.name.lowercased() }
        loading = false
    }

    /// One album per album the songs are on, in the songs' order.
    static func albums(_ songs: [Track]) -> [Album] {
        var seen = Set<String>()
        return songs.compactMap { t in
            guard !t.albumhash.isEmpty, !t.album.isEmpty, seen.insert(t.albumhash).inserted else { return nil }
            return Album(albumhash: t.albumhash, title: t.album, artist: t.artist, image: t.image.isEmpty ? (t.cover ?? "") : t.image)
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var lib: LibraryModel
    @EnvironmentObject private var sheets: Sheets
    @Environment(\.navigate) private var navigate

    var body: some View {
        LargeTitlePage(title: "Library") {
            Button { sheets.newPlaylistFor = [] } label: { SynkIcon(SynkIcons.plus, size: 20) }
                .accessibilityLabel("New playlist")
            Button { navigate(.library(.playlists)) } label: { SynkIcon(SynkIcons.pencil, size: 20) }
                .accessibilityLabel("Edit playlists")
        } content: {
            VStack(spacing: 0) {
                CategoryRow(icon: SynkIcons.queue, label: "Playlists") { navigate(.library(.playlists)) }
                CategoryRow(icon: SynkIcons.microphone, label: "Artists") { navigate(.library(.artists)) }
                CategoryRow(icon: SynkIcons.squareStack, label: "Albums") { navigate(.library(.albums)) }
                CategoryRow(icon: SynkIcons.musicNote, label: "Songs") { navigate(.library(.songs)) }
                CategoryRow(icon: SynkIcons.download, label: "Downloaded") { navigate(.library(.downloaded)) }
                CategoryRow(icon: SynkIcons.chart, label: "Your Stats") { navigate(.analytics) }
            }
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            let recent = Array(LibraryModel.albums(lib.songs.reversed()).prefix(12))
            if !recent.isEmpty {
                SectionHead("Recently Added")
                AlbumGrid(albums: recent)
            }
        }
        .task { if lib.songs.isEmpty { await lib.load() } }
        .refreshable { await lib.load() }
    }
}

private struct AlbumGrid: View {
    let albums: [Album]
    @Environment(\.navigate) private var navigate

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 20) {
            ForEach(Array(albums.enumerated()), id: \.offset) { _, a in
                Button { if !a.hash.isEmpty { navigate(.album(a.hash)) } } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Artwork(url: a.coverUrl, radius: 10).aspectRatio(1, contentMode: .fit)
                        Text(a.displayTitle).font(sans: 14, 500).foregroundStyle(Theme.fg).lineLimit(1).padding(.top, 6)
                        Text(a.artist).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                    }
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 16)
    }
}

struct LibraryPageView: View {
    let page: LibraryPage
    @EnvironmentObject private var lib: LibraryModel
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.navigate) private var navigate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch page {
                case .songs:
                    if lib.loading && lib.songs.isEmpty { Loading() } else {
                        CollectionTop(tracks: lib.songs, bare: true)
                        TrackList(tracks: lib.songs)
                    }
                case .downloaded:
                    let tracks = downloads.tracks
                    if tracks.isEmpty { EmptyNote(text: "Songs you download show up here.") } else {
                        CollectionTop(tracks: tracks, bare: true)
                        TrackList(tracks: tracks)
                    }
                case .playlists:
                    ForEach(lib.playlists) { p in
                        row(cover: p.coverUrl, round: false, title: p.name, sub: Format.plural(p.trackCount, "song", "songs"), size: 56) {
                            navigate(.playlist(p.id))
                        }
                    }
                case .artists:
                    ForEach(Array(lib.artists.enumerated()), id: \.offset) { _, a in
                        row(cover: a.image, round: true, title: a.name, sub: "", size: 48, initial: a.name) {
                            navigate(a.hash.isEmpty ? .artistNamed(a.name) : .artist(a.hash))
                        }
                    }
                case .albums:
                    AlbumGrid(albums: lib.albums)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .navigationTitle(page.rawValue)
        .navigationBarTitleDisplayMode(.large)
        .task { if lib.songs.isEmpty && lib.playlists.isEmpty { await lib.load() } }
        .refreshable { await lib.load() }
    }

    private func row(cover: String, round: Bool, title: String, sub: String, size: CGFloat, initial: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if round { Circle().fill(Color.white.opacity(0.08)) } else { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)) }
                    if !initial.isEmpty { Text(String(initial.prefix(1)).uppercased()).font(sans: 18, 700).foregroundStyle(Theme.fg.opacity(0.4)) }
                    if !cover.isEmpty { RemoteImage(url: cover) }
                }
                .frame(width: size, height: size)
                .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(sans: 17).foregroundStyle(Theme.fg).lineLimit(1)
                        if !sub.isEmpty { Text(sub).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)) }
                    }
                    Spacer()
                    SynkIcon(SynkIcons.chevronRight, size: 18, tint: Theme.fg.opacity(0.35))
                }
                .padding(.vertical, 12)
                .padding(.trailing, 16)
                .hairline(0)
            }
            .padding(.leading, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Album, playlist, artist

private func minutes(_ tracks: [Track]) -> Int { tracks.reduce(0) { $0 + $1.durationSeconds } / 60 }

private struct MoreButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) { SynkIcon(SynkIcons.more, size: 20) }.accessibilityLabel("More")
    }
}

struct AlbumView: View {
    let id: String
    @State private var album: Album?
    @State private var tracks: [Track] = []
    @State private var loaded = false
    @Environment(\.navigate) private var navigate

    var body: some View {
        ScrollView {
            if !loaded { Loading() } else if let a = album {
                VStack(spacing: 0) {
                    CollectionTop(cover: a.coverUrl, title: a.displayTitle, artist: a.artist,
                                  onArtist: artistAction(a),
                                  meta: [a.genres.first ?? "", a.year].filter { !$0.isEmpty }.joined(separator: ", "),
                                  tracks: tracks)
                    TrackList(tracks: tracks, numbered: true)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                    if !tracks.isEmpty {
                        Text("\(Format.plural(tracks.count, "song", "songs")), \(minutes(tracks)) minutes")
                            .font(sans: 14).foregroundStyle(Theme.fg.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 16)
                    }
                }
                .padding(.bottom, 24)
            } else {
                Text("Album not found.").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55)).frame(maxWidth: .infinity).padding(.vertical, 96)
            }
        }
        .background(Theme.ink)
        .navigationTitle(album?.displayTitle ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let a = album { MoreButton { Sheets.shared.album(a, tracks: tracks) } }
            }
        }
        .task {
            if loaded { return }
            async let info = try? API.shared.albumInfo(id)
            async let ts = try? API.shared.albumTracks(id)
            album = await info
            tracks = await ts ?? []
            loaded = true
        }
    }

    private func artistAction(_ a: Album) -> (() -> Void)? {
        let h = a.albumartists.first?.artisthash ?? ""
        if h.isEmpty { return nil }
        return { navigate(.artist(h)) }
    }
}

struct PlaylistView: View {
    let id: String
    @State private var info: Playlist?
    @State private var tracks: [Track] = []
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if !error.isEmpty {
                Text(error).font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55)).frame(maxWidth: .infinity).padding(.vertical, 96)
            } else if let p = info {
                VStack(alignment: .leading, spacing: 0) {
                    CollectionTop(cover: p.coverUrl, title: p.name, artist: p.owner ?? "", meta: meta, tracks: tracks)
                    if !p.description.isEmpty {
                        Text(p.description).font(sans: 14).foregroundStyle(Theme.fg.opacity(0.6)).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                    TrackList(tracks: tracks, fromPlaylist: id, onRemoved: { Task { await load() } })
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                }
                .padding(.bottom, 24)
            } else {
                Loading()
            }
        }
        .background(Theme.ink)
        .navigationTitle(info?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let p = info { MoreButton { openMenu(p) } }
            }
        }
        .task { if info == nil { await load() } }
        .refreshable { await load() }
    }

    private var meta: String {
        let m = minutes(tracks)
        return "\(tracks.count) songs, " + (m >= 60 ? "\(m / 60) hr \(m % 60) min" : "\(m) min")
    }

    private func openMenu(_ p: Playlist) {
        let me = AuthStore.shared.user
        let owner = me != nil && (p.ownerId == me?.id || p.owner == me?.username)
        Sheets.shared.playlist(id: id, name: p.name, cover: p.coverUrl, tracks: tracks, isOwner: owner) { dismiss() }
    }

    private func load() async {
        do {
            let r = try await API.shared.playlist(id)
            info = r.0
            tracks = r.1
        } catch {
            if info == nil { self.error = (error as? APIError)?.message ?? "Could not load this playlist." }
        }
    }
}

struct ArtistView: View {
    let id: String
    @State private var artist: Artist?
    @State private var tracks: [Track] = []
    @State private var albums: [Album] = []
    @State private var loaded = false
    @Environment(\.navigate) private var navigate

    var body: some View {
        ScrollView {
            if !loaded { Loading() } else {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    if !tracks.isEmpty {
                        SectionHead("Top Songs")
                        TrackList(tracks: tracks)
                    }
                    if !albums.isEmpty {
                        SectionHead("Albums")
                        Shelf {
                            ForEach(Array(albums.enumerated()), id: \.offset) { _, a in
                                ShelfCard(image: a.coverUrl, title: a.displayTitle, subtitle: a.year) { navigate(.album(a.hash)) }
                            }
                        }
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if loaded { return }
            async let info = try? API.shared.artistInfo(id)
            async let ts = try? API.shared.artistTracks(id)
            async let als = try? API.shared.artistAlbums(id)
            artist = await info
            tracks = await ts ?? []
            albums = await als ?? []
            loaded = true
        }
    }

    /// Full-width square photo with the name and a white play button on top.
    private var hero: some View {
        let w = UIScreen.main.bounds.width
        return ZStack(alignment: .bottom) {
            Color.white.opacity(0.06)
            if let a = artist, !a.coverUrl.isEmpty { RemoteImage(url: a.coverUrl) }
            HStack(alignment: .bottom) {
                Text(artist?.name ?? "").font(display: 34, 700).foregroundStyle(Theme.fg).lineLimit(2)
                Spacer()
                if !tracks.isEmpty {
                    Button { Playback.play(tracks[0], in: tracks) } label: {
                        SynkIcon(SynkIcons.play, size: 24, tint: .black).frame(width: 48, height: 48).background(Circle().fill(Theme.fg))
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Play")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 16).padding(.top, 80)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
        }
        .frame(width: w, height: w)
        .clipped()
    }
}

/// An artist known only by name: find it, then show its page.
struct ArtistLookupView: View {
    let name: String
    @State private var hash: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let hash {
                ArtistView(id: hash)
            } else if failed {
                Text("Couldn't find \(name).").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.ink)
            } else {
                Loading().frame(maxHeight: .infinity).background(Theme.ink)
            }
        }
        .task {
            let r = await API.shared.search(name)
            let match = r.artists.first { $0.name.lowercased() == name.lowercased() } ?? r.artists.first
            if let match, !match.hash.isEmpty { hash = match.hash } else { failed = true }
        }
    }
}

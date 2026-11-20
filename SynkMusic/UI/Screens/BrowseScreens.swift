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
    @Published var failed = false
    private static let cacheFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("home.json")

    init() {
        // The last Home shows straight away; a fresh copy replaces it when it arrives.
        if let d = try? Data(contentsOf: HomeModel.cacheFile), let s = try? JSONDecoder().decode(Keyed<HomeSection>.self, from: d) {
            let items = s.items("sections")
            if !items.isEmpty { sections = items }
        }
    }

    func load() async {
        failed = false
        for attempt in 0..<2 {
            var req = API.shared.request("library/home", query: ["limit": "14"])
            req.timeoutInterval = 30
            do {
                let d = try await API.shared.data(req)
                let fresh = try JSONDecoder().decode(Keyed<HomeSection>.self, from: d).items("sections")
                if !fresh.isEmpty {
                    sections = fresh
                    try? d.write(to: HomeModel.cacheFile, options: .atomic)
                    return
                }
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError { return }
                DebugLog.shared.add("home: \(error.localizedDescription)")
            }
            if attempt == 0 { try? await Task.sleep(nanoseconds: 2_000_000_000) }
        }
        failed = true
        if sections == nil { sections = [] }
    }
}

struct HomeView: View {
    @StateObject private var model = HomeModel()
    @EnvironmentObject private var net: NetworkMonitor
    @Environment(\.navigate) private var navigate
    @Environment(\.playTrack) private var play

    var body: some View {
        LargeTitlePage(title: "Home") {
            if let sections = model.sections {
                if sections.isEmpty {
                    if !net.online {
                        Text("You're offline. Your downloads are in Library.").font(sans: 15).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.vertical, 96)
                    } else {
                        VStack(spacing: 14) {
                            Text("Couldn't load Home.").font(sans: 15).foregroundStyle(Theme.muted)
                            Button { Task { await model.load() } } label: {
                                Text("Try again").font(sans: 15, 600).foregroundStyle(Theme.fg)
                                    .padding(.horizontal, 20).frame(height: 40)
                                    .background(Capsule().fill(Color.white.opacity(0.12)))
                            }
                            .buttonStyle(PressStyle())
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 96)
                    }
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
        .onChange(of: net.online) { _, on in if on && (model.sections?.isEmpty ?? true) { Task { await model.load() } } }
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

/// One row of search results: an artist, an album or a song.
enum SearchItem: Identifiable {
    case artist(Artist), album(Album), track(Track)

    var id: String {
        switch self {
        case .artist(let a): return "ar:" + a.hash
        case .album(let a): return "al:" + a.hash
        case .track(let t): return "tr:" + t.hash + t.displayTitle
        }
    }
}

enum SearchScope: String, CaseIterable {
    case top = "Top Results", artists = "Artists", albums = "Albums", songs = "Songs"
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var query = ""
    @Published var result: SearchResponse?
    @Published var loading = false
    /// False while typing (suggestions), true once a search is run (full results).
    @Published var submitted = false
    @Published var scope: SearchScope = .top
    @Published var recent: [String] = UserDefaults.standard.stringArray(forKey: "synk.recentSearches") ?? []
    private(set) var term = ""
    private var job: Task<Void, Never>?
    private var settingQuery = false

    func change(_ q: String) {
        if settingQuery { settingQuery = false } else { submitted = false }
        job?.cancel()
        let t = q.trimmingCharacters(in: .whitespaces)
        job = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            if t.count < 2 { term = t; result = nil; loading = false; return }
            loading = true
            var r = await API.shared.search(t)
            if Task.isCancelled { return }
            if r.isEmpty {
                // Offline: search what is downloaded.
                r.tracks = DownloadStore.shared.tracks.filter {
                    $0.displayTitle.localizedCaseInsensitiveContains(t) || $0.artist.localizedCaseInsensitiveContains(t)
                }
            }
            term = t
            result = r
            loading = false
        }
    }

    /// Runs a search for `text`, as if typed and then Search pressed.
    func submit(_ text: String? = nil) {
        if let text, text != query {
            settingQuery = true
            query = text
        }
        submitted = true
        scope = .top
        remember(text ?? query)
    }

    /// Names that start with what was typed, to finish the search with one tap.
    var suggestions: [String] {
        guard let r = result, !term.isEmpty else { return [] }
        let q = term.lowercased()
        let names = r.artists.map(\.name) + r.albums.map(\.displayTitle) + r.tracks.map(\.displayTitle) + r.tracks.map(\.artist)
        var seen = Set<String>()
        var out: [String] = []
        for n in names {
            let l = n.lowercased()
            guard l != q, SearchModel.matches(l, q), seen.insert(l).inserted else { continue }
            out.append(l)
            if out.count == 4 { break }
        }
        return out
    }

    /// Artists, albums and songs in one list: the best matching artist first,
    /// then two songs to every album, then any other artists.
    var topResults: [SearchItem] {
        guard let r = result else { return [] }
        let q = term.lowercased()
        let lead = r.artists.firstIndex { SearchModel.matches($0.name.lowercased(), q) }
        var out: [SearchItem] = []
        if let lead { out.append(.artist(r.artists[lead])) }
        var ti = 0, ai = 0
        while ti < r.tracks.count || ai < r.albums.count {
            for _ in 0..<2 where ti < r.tracks.count { out.append(.track(r.tracks[ti])); ti += 1 }
            if ai < r.albums.count { out.append(.album(r.albums[ai])); ai += 1 }
        }
        for (i, a) in r.artists.enumerated() where i != lead { out.append(.artist(a)) }
        return Array(out.prefix(30))
    }

    func items(_ s: SearchScope) -> [SearchItem] {
        guard let r = result else { return [] }
        switch s {
        case .top: return topResults
        case .artists: return r.artists.map { .artist($0) }
        case .albums: return r.albums.map { .album($0) }
        case .songs: return r.tracks.map { .track($0) }
        }
    }

    /// The whole name, or any word in it, starts with `q`.
    static func matches(_ name: String, _ q: String) -> Bool {
        name.hasPrefix(q) || name.split(separator: " ").contains { $0.hasPrefix(q) }
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
    @FocusState private var focused: Bool
    @Environment(\.navigate) private var navigate
    @Environment(\.playTrack) private var play

    var body: some View {
        if #available(iOS 26.0, *) {
            // The search field lives in the Liquid Glass tab bar.
            page(field: false)
                .searchable(text: $model.query, prompt: "Artists, Songs, Albums")
                .searchFocused($focused)
                .onSubmit(of: .search) { model.submit() }
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
                        .focused($focused)
                        .onSubmit { model.submit() }
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
        let typed = model.query.trimmingCharacters(in: .whitespaces).count >= 2
        if !typed {
            recentSearches
        } else if model.result == nil {
            Loading()
        } else if model.submitted {
            scopes
            itemRows(model.items(model.scope))
            if model.result?.isEmpty == true { noResults }
        } else {
            suggestionRows
            itemRows(Array(model.topResults.prefix(8)))
            if model.result?.isEmpty == true { noResults }
        }
    }

    @ViewBuilder private var recentSearches: some View {
        if !model.recent.isEmpty {
            HStack {
                Text("Recently Searched").font(sans: 20, 700).foregroundStyle(Theme.fg)
                Spacer()
                Button { model.clearRecent() } label: { Text("Clear").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.6)) }
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16)
            ForEach(model.recent, id: \.self) { r in
                termRow(r) { pick(r) }
            }
        }
    }

    private var suggestionRows: some View {
        ForEach(model.suggestions, id: \.self) { s in
            termRow(s, typed: model.term.lowercased()) { pick(s) }
        }
    }

    /// A text-only row with a magnifying glass; the typed part stays bright,
    /// the rest of the suggestion is dimmed.
    private func termRow(_ text: String, typed: String = "", action: @escaping () -> Void) -> some View {
        let head = typed.isEmpty || !text.hasPrefix(typed) ? "" : typed
        let tail = String(text.dropFirst(head.count))
        return Button(action: action) {
            HStack(spacing: 12) {
                SynkIcon(SynkIcons.search, size: 20, tint: Theme.fg.opacity(0.45))
                Text("\(Text(head).foregroundStyle(Theme.fg))\(Text(tail).foregroundStyle(head.isEmpty ? Theme.fg : Theme.fg.opacity(0.6)))")
                    .font(sans: 17).lineLimit(1)
                Spacer()
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .hairline(32)
            .padding(.leading, 16)
        }
        .buttonStyle(.plain)
    }

    private var scopes: some View {
        let shown = SearchScope.allCases.filter { $0 == .top || !model.items($0).isEmpty }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(shown, id: \.self) { s in
                    Chip(text: s.rawValue, active: model.scope == s) { model.scope = s }
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.top, 8).padding(.bottom, 8)
    }

    private func itemRows(_ items: [SearchItem]) -> some View {
        let tracks = model.result?.tracks ?? []
        return LazyVStack(spacing: 0) {
            ForEach(items) { item in
                switch item {
                case .artist(let a):
                    entityRow(image: a.coverUrl, round: true, title: a.name, subtitle: "Artist") { open(.artist(a.hash)) }
                case .album(let a):
                    entityRow(image: a.coverUrl, round: false, title: a.displayTitle,
                              subtitle: a.artist.isEmpty ? "Album" : "Album, \(a.artist)") { open(.album(a.hash)) }
                case .track(let t):
                    TrackRow(track: t, kind: "Song") { model.remember(model.term); focused = false; play(t, tracks) }
                }
            }
        }
        .padding(.leading, 6)
    }

    /// An artist or album: artwork, name, what it is, and a chevron.
    private func entityRow(image: String, round: Bool, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Artwork(url: image, radius: 8, round: round).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(sans: 16).foregroundStyle(Theme.fg).lineLimit(1)
                    Text(subtitle).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                }
                Spacer(minLength: 8)
                SynkIcon(SynkIcons.chevronRight, size: 18, tint: Theme.fg.opacity(0.35))
                    .frame(width: 40, height: 40)
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .contentShape(Rectangle())
            .hairline(70)
        }
        .buttonStyle(.plain)
    }

    private var noResults: some View {
        Text("No results for \"\(model.term)\".").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
            .frame(maxWidth: .infinity).padding(.vertical, 40)
    }

    private func pick(_ text: String) {
        focused = false
        model.submit(text)
    }

    private func open(_ route: Route) {
        model.remember(model.term)
        focused = false
        navigate(route)
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

    var folders: [String] {
        Array(Set(playlists.compactMap { $0.folder })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var pinned: [Playlist] { playlists.filter { $0.pinned } }

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
            if !lib.pinned.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 14) {
                    ForEach(lib.pinned) { p in
                        Button { navigate(.playlist(p.id)) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Artwork(url: p.coverUrl, radius: 8).aspectRatio(1, contentMode: .fit)
                                Text(p.name).font(sans: 13, 500).foregroundStyle(Theme.fg).lineLimit(1)
                            }
                        }
                        .buttonStyle(PressStyle())
                        .contextMenu {
                            Button { Task { try? await API.shared.setPlaylistPinned(p.id, false); await lib.loadPlaylists() } } label: {
                                Label("Unpin Playlist", systemImage: "pin.slash")
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
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
    @State private var byTitle = false

    private var loose: [Playlist] {
        let l = lib.playlists.filter { $0.folder == nil }
        return byTitle ? l.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } : l
    }

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
                    ForEach(lib.folders, id: \.self) { f in
                        let inside = lib.playlists.filter { $0.folder == f }
                        let n = inside.count
                        Button { navigate(.folder(f)) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08))
                                    if let first = inside.first {
                                        Artwork(url: first.coverUrl, radius: 4).frame(width: 26, height: 26)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(6)
                                    } else {
                                        Image(systemName: "folder").font(.system(size: 22)).foregroundStyle(Theme.fg)
                                    }
                                }
                                .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(f).font(sans: 17).foregroundStyle(Theme.fg).lineLimit(1)
                                    Text(Format.plural(n, "Playlist", "Playlists")).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55))
                                }
                                Spacer()
                                SynkIcon(SynkIcons.chevronRight, size: 18, tint: Theme.fg.opacity(0.35))
                            }
                            .padding(.vertical, 8).padding(.trailing, 16)
                            .contentShape(Rectangle())
                            .hairline(68)
                            .padding(.leading, 16)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(loose) { p in
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
        .toolbar {
            if page == .playlists {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Sheets.shared.newPlaylistFor = [] } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Playlist")
                    Menu {
                        Picker("Sort By", selection: $byTitle) {
                            Text("Recently Added").tag(false)
                            Text("Title").tag(true)
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                        .accessibilityLabel("Sort")
                }
            }
        }
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


struct AlbumView: View {
    let id: String
    @State private var album: Album?
    @State private var tracks: [Track] = []
    @State private var loaded = false
    @Environment(\.navigate) private var navigate

    var body: some View {
        Group {
            if !loaded {
                Loading().frame(maxHeight: .infinity).background(Theme.ink)
            } else if let a = album {
                CollectionPage(cover: a.coverUrl, title: a.displayTitle, subtitle: a.artist, onSubtitle: artistAction(a),
                               tracks: tracks, numbered: true,
                               footer: tracks.isEmpty ? "" : Durations.summary(tracks),
                               shareURL: URL(string: "https://synkmusic.co.uk/album/\(a.hash)"),
                               source: PlaySource(name: a.displayTitle, route: .album(a.hash))) {
                    AlbumMenuItems(album: a, tracks: tracks)
                }
            } else {
                Text("Album not found.").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.ink)
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
    @State private var confirmDelete = false
    @State private var sort = PlaylistSort.playlist
    @State private var editing = false
    @State private var collaborating = false
    @State private var collaborator = ""
    @State private var note: String?
    @State private var moving = false
    @State private var movedTo: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.navigate) private var navigate

    var body: some View {
        Group {
            if !error.isEmpty {
                Text(error).font(sans: 15).foregroundStyle(Theme.fg.opacity(0.55))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.ink)
            } else if let p = info {
                CollectionPage(cover: p.coverUrl, title: p.name, subtitle: p.owner ?? "", description: p.description,
                               tracks: sort.apply(tracks), fromPlaylist: id, onRemoved: { Task { await load() } },
                               footer: Durations.summary(tracks), shareURL: URL(string: "https://synkmusic.co.uk/playlist/\(id)"),
                               editable: isOwner(p) ? id : nil, onAdded: { Task { await load() } },
                               source: PlaySource(name: p.name, route: .playlist(id), playlistId: id, owned: isOwner(p))) {
                    PlaylistMenuItems(id: id, tracks: tracks, isOwner: isOwner(p), pinned: p.pinned, folder: p.folder, sort: $sort,
                                      onPin: { change { try await API.shared.setPlaylistPinned(id, !p.pinned) } },
                                      onMove: { moving = true },
                                      onEdit: { editing = true }, onCollaborate: { collaborating = true }, onDelete: { confirmDelete = true })
                }
                .refreshable { await load() }
            } else {
                Loading().frame(maxHeight: .infinity).background(Theme.ink)
            }
        }
        .task { if info == nil { await load() } }
        .sheet(isPresented: $editing) {
            if let p = info {
                EditPlaylistSheet(id: id, name: p.name, description: p.description, isPublic: p.isPublic) { Task { await load() } }
            }
        }
        .alert("Start Collaboration", isPresented: $collaborating) {
            TextField("Username", text: $collaborator).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Cancel", role: .cancel) { collaborator = "" }
            Button("Add") {
                let name = collaborator.trimmingCharacters(in: .whitespaces)
                collaborator = ""
                guard !name.isEmpty else { return }
                Task {
                    do { try await API.shared.addCollaborator(id, username: name); note = "\(name) can now add songs to this playlist." }
                    catch { note = (error as? APIError)?.message ?? "Couldn't add \(name)." }
                }
            }
        } message: {
            Text("They will be able to add songs to this playlist.")
        }
        .sheet(isPresented: $moving) {
            if let p = info {
                MoveToFolderSheet(name: p.name, current: p.folder) { f in
                    moving = false
                    change { try await API.shared.setPlaylistFolder(id, f) }
                    if let f { withAnimation { movedTo = f } }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let f = movedTo {
                Button { movedTo = nil; navigate(.folder(f)) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder").font(.system(size: 16))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Moved to").font(sans: 11).foregroundStyle(Theme.fg.opacity(0.6))
                            HStack(spacing: 2) {
                                Text(f).font(sans: 14, 600)
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                            }
                        }
                    }
                    .foregroundStyle(Theme.fg)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glass(Color(hex: 0x1E1E20), Capsule(), opacity: 0.6)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task {
                    try? await Task.sleep(nanoseconds: 3_500_000_000)
                    withAnimation { movedTo = nil }
                }
            }
        }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog("Delete this playlist?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) {
                Task {
                    if (try? await API.shared.deletePlaylist(id)) != nil {
                        await LibraryModel.shared.load()
                        dismiss()
                    }
                }
            }
        }
    }


    private func change(_ op: @escaping () async throws -> Void) {
        Task {
            do { try await op() } catch { note = (error as? APIError)?.message ?? "Couldn't update the playlist." }
            await load()
            await LibraryModel.shared.loadPlaylists()
        }
    }

    private func isOwner(_ p: Playlist) -> Bool {
        let me = AuthStore.shared.user
        return me != nil && (p.ownerId == me?.id || p.owner == me?.username)
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

/// The playlists in one folder.
struct FolderView: View {
    let name: String
    @EnvironmentObject private var lib: LibraryModel
    @Environment(\.navigate) private var navigate

    @State private var starting = false

    var body: some View {
        ScrollView {
            HStack(spacing: 12) {
                folderButton("play.fill", "Play", shuffle: false)
                folderButton("shuffle", "Shuffle", shuffle: true)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 16)
            LazyVStack(spacing: 0) {
                ForEach(lib.playlists.filter { $0.folder == name }) { p in
                    Button { navigate(.playlist(p.id)) } label: {
                        HStack(spacing: 12) {
                            Artwork(url: p.coverUrl, radius: 8).frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(p.name).font(sans: 17).foregroundStyle(Theme.fg).lineLimit(1)
                                Text(Format.plural(p.trackCount, "song", "songs")).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55))
                            }
                            Spacer()
                            SynkIcon(SynkIcons.chevronRight, size: 18, tint: Theme.fg.opacity(0.35))
                        }
                        .padding(.vertical, 8).padding(.trailing, 16)
                        .contentShape(Rectangle())
                        .hairline(68)
                        .padding(.leading, 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await lib.loadPlaylists() }
    }

    private func folderButton(_ icon: String, _ label: String, shuffle: Bool) -> some View {
        Button {
            guard !starting else { return }
            starting = true
            Task {
                var all: [Track] = []
                for p in lib.playlists.filter({ $0.folder == name }) {
                    if let r = try? await API.shared.playlist(p.id) { all += r.1 }
                }
                if shuffle { all.shuffle() }
                if let f = all.first { Playback.play(f, in: all) }
                starting = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .bold))
                Text(label).font(sans: 17, 600)
            }
            .foregroundStyle(Theme.fg)
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(PressStyle())
    }
}

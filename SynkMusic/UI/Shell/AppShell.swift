import SwiftUI

enum LibraryPage: String, Hashable, CaseIterable {
    case playlists = "Playlists", artists = "Artists", albums = "Albums", songs = "Songs", downloaded = "Downloaded"
}

enum Route: Hashable {
    case album(String), playlist(String), artist(String), artistNamed(String), library(LibraryPage)
    case profile, analytics, settings, equalizer, tuning, downloads, diagnostics
}

/// Home, Explore, Radio, Library and Search, as on the m. site.
enum ShellTab: Hashable, CaseIterable {
    case home, explore, radio, library, search

    var label: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .radio: return "Radio"
        case .library: return "Library"
        case .search: return "Search"
        }
    }

    var icon: SynkVector {
        switch self {
        case .home: return SynkIcons.tabHome
        case .explore: return SynkIcons.tabExplore
        case .radio: return SynkIcons.tabRadio
        case .library: return SynkIcons.tabLibrary
        case .search: return SynkIcons.tabSearch
        }
    }
}

private struct NavigateKey: EnvironmentKey { static let defaultValue: (Route) -> Void = { _ in } }

extension EnvironmentValues {
    var navigate: (Route) -> Void { get { self[NavigateKey.self] } set { self[NavigateKey.self] = newValue } }
}

/// The system tab bar (Liquid Glass on iOS 26 and later) with the mini player
/// in its bottom accessory, and the now playing screen over everything.
struct AppShell: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient
    @EnvironmentObject private var sheets: Sheets
    @State private var tab: ShellTab = .home
    @State private var paths: [ShellTab: [Route]] = [:]
    @State private var playerOpen = false
    @State private var newPlaylistName = ""
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom

    var body: some View {
        let state = Playback.state()
        tabs(hasTrack: state.current != nil)
            .environment(\.nowPlaying, NowPlayingMark(hash: state.current?.hash, playing: state.isPlaying))
            .environment(\.playTrack, { t, list in Playback.play(t, in: list) })
            .fullScreenCover(isPresented: $playerOpen) {
                FullPlayer(onClose: { playerOpen = false })
                    .navigationTransition(.zoom(sourceID: "nowplaying", in: zoom))
                    .modifier(SheetHost(active: true))
                    .environment(\.nowPlaying, NowPlayingMark(hash: state.current?.hash, playing: state.isPlaying))
            }
            .modifier(SheetHost(active: !playerOpen))
            .alert("New Playlist", isPresented: Binding(get: { sheets.newPlaylistFor != nil }, set: { if !$0 { sheets.newPlaylistFor = nil } })) {
                TextField("Playlist name", text: $newPlaylistName)
                Button("Cancel", role: .cancel) { newPlaylistName = "" }
                Button("Create") {
                    let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                    let tracks = sheets.newPlaylistFor ?? []
                    newPlaylistName = ""
                    if !name.isEmpty { sheets.createPlaylist(name, adding: tracks) }
                }
            }
            .onChange(of: state.current == nil) { _, none in if none { playerOpen = false } }
            .onAppear {
                LikesStore.shared.refresh()
                Task { await LibraryModel.shared.loadPlaylists() }
                cdc.connect()
                bindNavigate(tab)
            }
            .onChange(of: tab) { _, t in bindNavigate(t) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background && !player.isPlaying { cdc.suspend() }
                if phase == .active { cdc.resume() }
            }
    }

    /// Menus open pages in the tab that is showing.
    private func bindNavigate(_ t: ShellTab) {
        sheets.navigate = { r in
            playerOpen = false
            paths[t, default: []].append(r)
        }
    }

    @ViewBuilder
    private func tabs(hasTrack: Bool) -> some View {
        let view = TabView(selection: $tab) {
            ForEach(ShellTab.allCases, id: \.self) { t in
                Tab(value: t, role: t == .search ? .search : nil) {
                    stack(t, hasTrack: hasTrack)
                } label: {
                    Label { Text(t.label) } icon: { Image(uiImage: t.icon.image(24)) }
                }
            }
        }
        .tint(Theme.fg)
        if #available(iOS 26.0, *) {
            if hasTrack {
                view
                    .tabBarMinimizeBehavior(.onScrollDown)
                    .tabViewBottomAccessory {
                        MiniPlayerAccessory { playerOpen = true }
                            .matchedTransitionSource(id: "nowplaying", in: zoom)
                    }
            } else {
                view.tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            view
        }
    }

    private func stack(_ t: ShellTab, hasTrack: Bool) -> some View {
        NavigationStack(path: Binding(get: { paths[t] ?? [] }, set: { paths[t] = $0 })) {
            root(t)
                .navigationDestination(for: Route.self) { destination($0) }
        }
        .environment(\.navigate, { r in paths[t, default: []].append(r) })
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Before iOS 26 the mini player floats above the tab bar as a glass pill.
            if !AppShell.hasAccessory, hasTrack {
                MiniPlayerPill { playerOpen = true }
                    .matchedTransitionSource(id: "nowplaying", in: zoom)
            }
        }
    }

    private static var hasAccessory: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    @ViewBuilder private func root(_ t: ShellTab) -> some View {
        switch t {
        case .home: HomeView()
        case .explore: ExploreView()
        case .radio: RadioView()
        case .library: LibraryView()
        case .search: SearchView()
        }
    }

    @ViewBuilder private func destination(_ r: Route) -> some View {
        switch r {
        case .album(let id): AlbumView(id: id)
        case .playlist(let id): PlaylistView(id: id)
        case .artist(let id): ArtistView(id: id)
        case .artistNamed(let name): ArtistLookupView(name: name)
        case .library(let p): LibraryPageView(page: p)
        case .profile: ProfileView()
        case .analytics: AnalyticsView()
        case .settings: SettingsView()
        case .equalizer: EqualizerView()
        case .tuning: DeviceTuningView()
        case .downloads: DownloadsView()
        case .diagnostics: DiagnosticsView()
        }
    }
}

/// Presents the shared action sheet from whichever layer is on top.
struct SheetHost: ViewModifier {
    let active: Bool
    @ObservedObject private var sheets = Sheets.shared

    func body(content: Content) -> some View {
        content.sheet(item: Binding(get: { active ? sheets.current : nil }, set: { if active { sheets.current = $0 } })) { m in
            ActionSheetView(model: m)
        }
    }
}

// MARK: mini player

private struct MiniContent: View {
    let compact: Bool
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient

    var body: some View {
        let s = Playback.state()
        if let t = s.current {
            HStack(spacing: compact ? 10 : 12) {
                Artwork(url: t.coverUrl, radius: compact ? 6 : 8).frame(width: compact ? 30 : 40, height: compact ? 30 : 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.displayTitle).font(sans: 14, 600).foregroundStyle(Theme.fg).lineLimit(1)
                    Text(cdc.isRemote ? "Playing on \(cdc.activeDevice?.name ?? "another device")" : t.artist)
                        .font(sans: 12).foregroundStyle(Theme.fg.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { Playback.toggle() } label: {
                    SynkIcon(s.isPlaying ? SynkIcons.pause : SynkIcons.play, size: 24).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(s.isPlaying ? "Pause" : "Play")
                Button { Playback.next() } label: {
                    SynkIcon(SynkIcons.skipNext, size: 24).frame(width: 36, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
        }
    }
}

/// iOS 26 and later: the content of the tab bar's glass accessory.
private struct MiniPlayerAccessory: View {
    let onOpen: () -> Void
    var body: some View {
        MiniContent(compact: true)
            .padding(.leading, 10).padding(.trailing, 6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .accessibilityAddTraits(.isButton)
    }
}

/// Before iOS 26: a 56pt glass pill tinted by the artwork, with a progress line.
private struct MiniPlayerPill: View {
    let onOpen: () -> Void
    @EnvironmentObject private var player: PlayerController
    @State private var tint = Color(hex: 0x141414)

    var body: some View {
        let cover = Playback.state().current?.coverUrl ?? ""
        MiniContent(compact: false)
            .padding(.leading, 8).padding(.trailing, 12)
            .frame(height: 56)
            .overlay(alignment: .bottom) { MiniProgress().padding(.horizontal, 24) }
            .contentShape(Capsule())
            .onTapGesture(perform: onOpen)
            .glass(tint, Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .artTint(cover, value: 0.17, into: $tint)
    }
}

private struct MiniProgress: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let pd = Playback.positionMs()
            let f: CGFloat = pd.1 > 0 ? min(1, max(0, CGFloat(pd.0) / CGFloat(pd.1))) : 0
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white.opacity(0.8)).frame(width: g.size.width * f)
                }
            }
            .frame(height: 2)
        }
    }
}

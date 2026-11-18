import SwiftUI

/// The "..." and long-press menus, in the style of Apple Music: a row of
/// buttons at the top, then grouped actions, destructive ones last in red.
/// These are the system menus, so they get Liquid Glass on iOS 26 and later.

private func shareURL(_ path: String) -> URL { URL(string: "https://synkmusic.co.uk" + path)! }

/// Add to Playlist: a new playlist, then each of yours.
struct AddToPlaylistMenu: View {
    let tracks: [Track]
    @ObservedObject private var lib = LibraryModel.shared

    var body: some View {
        Menu {
            Button { Sheets.shared.newPlaylistFor = tracks } label: { Label("New Playlist", systemImage: "plus") }
            if !lib.playlists.isEmpty {
                Divider()
                ForEach(lib.playlists) { pl in
                    Button(pl.name.isEmpty ? "Playlist" : pl.name) {
                        let hashes = tracks.map { $0.hash.isEmpty ? ($0.isrc ?? "") : $0.hash }.filter { !$0.isEmpty }
                        Task { try? await API.shared.addToPlaylist(pl.id, hashes: hashes); await lib.loadPlaylists() }
                    }
                }
            }
        } label: {
            Label("Add to Playlist", systemImage: "text.badge.plus")
        }
    }
}

struct TrackMenuItems: View {
    let track: Track
    var fromPlaylist: String?
    var onRemoved: (() -> Void)?
    @ObservedObject private var likes = LikesStore.shared
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        let liked = likes.isLiked(track)
        let downloaded = downloads.isDownloaded(track)
        ControlGroup {
            Button { likes.toggle(track) } label: {
                Label(liked ? "Unfavourite" : "Favourite", systemImage: liked ? "star.fill" : "star")
            }
            ShareLink(item: shareURL("/track/\(track.hash)")) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Section {
            Button { downloads.toggle(track) } label: {
                Label(downloaded ? "Remove Download" : "Download", systemImage: downloaded ? "trash" : "arrow.down.circle")
            }
            AddToPlaylistMenu(tracks: [track])
        }
        Section {
            Button { PlayerController.shared.addNext(track) } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { PlayerController.shared.addToQueue(track) } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
        }
        if !track.artist.isEmpty {
            Section {
                Button { startStation(track.artist) } label: { Label("Create Station", systemImage: "dot.radiowaves.left.and.right") }
            }
        }
        if !track.albumhash.isEmpty || !track.artist.isEmpty {
            Section {
                Menu {
                    if !track.albumhash.isEmpty {
                        Button { Sheets.shared.navigate(.album(track.albumhash)) } label: {
                            Label { Text("Album"); Text(track.album) } icon: { Image(systemName: "square.stack") }
                        }
                    }
                    if !track.artist.isEmpty {
                        Button {
                            let h = track.artists.first?.artisthash ?? ""
                            Sheets.shared.navigate(h.isEmpty ? .artistNamed(track.artist) : .artist(h))
                        } label: {
                            Label { Text("Artist"); Text(track.artist) } icon: { Image(systemName: "music.mic") }
                        }
                    }
                } label: {
                    Label("Go to", systemImage: "arrow.up.right")
                }
            }
        }
        if let pid = fromPlaylist {
            Section {
                Button(role: .destructive) {
                    Task { if (try? await API.shared.removeFromPlaylist(pid, hash: track.hash)) != nil { onRemoved?() } }
                } label: { Label("Remove from This Playlist", systemImage: "trash") }
            }
        }
    }

    private func startStation(_ artist: String) {
        Task {
            let list = (try? await API.shared.artistRadio(artist)) ?? []
            if let f = list.first { Playback.play(f, in: list) }
        }
    }
}

struct AlbumMenuItems: View {
    let album: Album
    let tracks: [Track]
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        let all = !tracks.isEmpty && tracks.allSatisfy { downloads.isDownloaded($0) }
        let some = tracks.contains { downloads.isDownloaded($0) }
        ControlGroup {
            if !all {
                Button { tracks.forEach { downloads.download($0) } } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
            Button { Task { try? await API.shared.likeItem(type: "album", hash: album.hash) } } label: { Label("Favourite", systemImage: "star") }
            ShareLink(item: shareURL("/album/\(album.hash)")) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Section { AddToPlaylistMenu(tracks: tracks) }
        Section {
            Button { tracks.reversed().forEach { PlayerController.shared.addNext($0) } } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { tracks.forEach { PlayerController.shared.addToQueue($0) } } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
        }
        if let h = album.albumartists.first?.artisthash, !h.isEmpty {
            Section {
                Button { Sheets.shared.navigate(.artist(h)) } label: {
                    Label { Text("Go to Artist"); Text(album.artist) } icon: { Image(systemName: "music.mic") }
                }
            }
        }
        if some {
            Section {
                Button { tracks.forEach { if downloads.isDownloaded($0) { downloads.remove($0) } } } label: {
                    Label("Remove Download", systemImage: "xmark.circle")
                }
            }
        }
    }
}

enum PlaylistSort: String, CaseIterable {
    case playlist = "Playlist Order", title = "Title", artist = "Artist", album = "Album", duration = "Duration"

    func apply(_ tracks: [Track]) -> [Track] {
        switch self {
        case .playlist: return tracks
        case .title: return tracks.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .artist: return tracks.sorted { $0.artist.localizedCaseInsensitiveCompare($1.artist) == .orderedAscending }
        case .album: return tracks.sorted { $0.album.localizedCaseInsensitiveCompare($1.album) == .orderedAscending }
        case .duration: return tracks.sorted { $0.durationSeconds < $1.durationSeconds }
        }
    }
}

struct PlaylistMenuItems: View {
    let id: String
    let tracks: [Track]
    let isOwner: Bool
    var pinned = false
    var folder: String?
    @Binding var sort: PlaylistSort
    let onPin: () -> Void
    let onMove: () -> Void
    let onEdit: () -> Void
    let onCollaborate: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var downloads = DownloadStore.shared

    var body: some View {
        let all = !tracks.isEmpty && tracks.allSatisfy { downloads.isDownloaded($0) }
        let some = tracks.contains { downloads.isDownloaded($0) }
        ControlGroup {
            if !all {
                Button { tracks.forEach { downloads.download($0) } } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
            ShareLink(item: shareURL("/playlist/\(id)")) { Label("Share", systemImage: "square.and.arrow.up") }
        }
        Section {
            if isOwner {
                Button(action: onPin) { Label(pinned ? "Unpin Playlist" : "Pin Playlist", systemImage: pinned ? "pin.slash" : "pin") }
            }
            AddToPlaylistMenu(tracks: tracks)
        }
        Section {
            if isOwner {
                Button(action: onEdit) { Label("Edit", systemImage: "pencil") }
                Button(action: onCollaborate) { Label("Start Collaboration", systemImage: "person.badge.plus") }
            }
            Menu {
                Picker("Sort By", selection: $sort) {
                    ForEach(PlaylistSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Label("Sort By", systemImage: "arrow.up.arrow.down")
            }
            if isOwner {
                Button(action: onMove) { Label("Move to Folder", systemImage: "folder") }
            }
        }
        Section {
            Button { tracks.reversed().forEach { PlayerController.shared.addNext($0) } } label: { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button { tracks.forEach { PlayerController.shared.addToQueue($0) } } label: { Label("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") }
        }
        if some || isOwner {
            Section {
                if some {
                    Button { tracks.forEach { if downloads.isDownloaded($0) { downloads.remove($0) } } } label: {
                        Label("Remove Download", systemImage: "xmark.circle")
                    }
                }
                if isOwner {
                    Button(role: .destructive, action: onDelete) { Label("Delete from Library", systemImage: "trash") }
                }
            }
        }
    }
}

/// The round "..." button that opens a menu.
struct MoreMenu<Items: View>: View {
    var size: CGFloat = 22
    var tint: Color = Theme.fg
    @ViewBuilder var items: () -> Items

    var body: some View {
        Menu { items() } label: {
            SynkIcon(SynkIcons.more, size: size, tint: tint).frame(width: 40, height: 40).contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More")
    }
}

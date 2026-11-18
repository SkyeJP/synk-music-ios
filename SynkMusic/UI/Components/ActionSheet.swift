import SwiftUI
import UIKit

struct SheetAction: Identifiable {
    let id = UUID()
    let label: String
    var danger = false
    var submenu: [SheetAction]?
    var run: (() -> Void)?
}

struct ActionSheetModel: Identifiable {
    let id = UUID()
    let title: String
    var subtitle = ""
    var cover = ""
    var round = false
    let items: [SheetAction]
}

/// The one action sheet and the new-playlist prompt, shown by the shell.
@MainActor
final class Sheets: ObservableObject {
    static let shared = Sheets()
    @Published var current: ActionSheetModel?
    @Published var newPlaylistFor: [Track]?
    var navigate: (Route) -> Void = { _ in }

    func show(_ m: ActionSheetModel) { current = m }

    // MARK: menus (components/menu/ContextMenu.tsx)

    func track(_ t: Track, fromPlaylist: String? = nil, onRemoved: (() -> Void)? = nil) {
        let downloads = DownloadStore.shared
        var items: [SheetAction] = [
            SheetAction(label: "Play next", run: { PlayerController.shared.addNext(t) }),
            SheetAction(label: "Add to queue", run: { PlayerController.shared.addToQueue(t) }),
            SheetAction(label: "Add to playlist", submenu: playlistSubmenu([t])),
        ]
        if !t.albumhash.isEmpty { items.append(SheetAction(label: "Go to album", run: { [weak self] in self?.navigate(.album(t.albumhash)) })) }
        if let h = t.artists.first?.artisthash, !h.isEmpty {
            items.append(SheetAction(label: "Go to artist", run: { [weak self] in self?.navigate(.artist(h)) }))
        } else if !t.artist.isEmpty {
            items.append(SheetAction(label: "Go to artist", run: { [weak self] in self?.navigate(.artistNamed(t.artist)) }))
        }
        let liked = LikesStore.shared.isLiked(t)
        items.append(SheetAction(label: liked ? "Unlike" : "Like", run: { LikesStore.shared.toggle(t) }))
        items.append(SheetAction(label: downloads.isDownloaded(t) ? "Remove download" : "Download", run: { downloads.toggle(t) }))
        items.append(SheetAction(label: "Share", run: { Share.link("/track/\(t.hash)") }))
        if let pid = fromPlaylist {
            items.append(SheetAction(label: "Remove from this playlist", danger: true, run: {
                Task { if (try? await API.shared.removeFromPlaylist(pid, hash: t.hash)) != nil { onRemoved?() } }
            }))
        }
        show(ActionSheetModel(title: t.displayTitle, subtitle: t.artist, cover: t.coverUrl, items: items))
    }

    func album(_ a: Album, tracks: [Track]) {
        var items: [SheetAction] = [
            SheetAction(label: "Play", run: { if let f = tracks.first { Playback.play(f, in: tracks) } }),
            SheetAction(label: "Play next", run: { tracks.reversed().forEach { PlayerController.shared.addNext($0) } }),
            SheetAction(label: "Add to queue", run: { tracks.forEach { PlayerController.shared.addToQueue($0) } }),
            SheetAction(label: "Add to library", run: { Task { try? await API.shared.likeItem(type: "album", hash: a.hash) } }),
            SheetAction(label: "Add to playlist", submenu: playlistSubmenu(tracks)),
            SheetAction(label: "Download", run: { tracks.forEach { DownloadStore.shared.download($0) } }),
        ]
        if let h = a.albumartists.first?.artisthash, !h.isEmpty {
            items.append(SheetAction(label: "Go to artist", run: { [weak self] in self?.navigate(.artist(h)) }))
        }
        items.append(SheetAction(label: "Share", run: { Share.link("/album/\(a.hash)") }))
        show(ActionSheetModel(title: a.displayTitle, subtitle: a.artist, cover: a.coverUrl, items: items))
    }

    func playlist(id: String, name: String, cover: String, tracks: [Track], isOwner: Bool, onDeleted: @escaping () -> Void) {
        var items: [SheetAction] = [
            SheetAction(label: "Share", run: { Share.link("/playlist/\(id)") }),
            SheetAction(label: "Download", run: { tracks.forEach { DownloadStore.shared.download($0) } }),
        ]
        if isOwner {
            items.append(SheetAction(label: "Delete playlist", danger: true, run: {
                Task {
                    if (try? await API.shared.deletePlaylist(id)) != nil {
                        await LibraryModel.shared.load()
                        onDeleted()
                    }
                }
            }))
        }
        show(ActionSheetModel(title: name, subtitle: "Playlist", cover: cover, items: items))
    }

    func account(_ user: User?, logout: @escaping () -> Void) {
        show(ActionSheetModel(title: user?.username ?? "Account", subtitle: user?.email ?? "", cover: user?.avatarUrl ?? "", round: true, items: [
            SheetAction(label: "Your Profile", run: { [weak self] in self?.navigate(.profile) }),
            SheetAction(label: "Your Stats", run: { [weak self] in self?.navigate(.analytics) }),
            SheetAction(label: "Settings", run: { [weak self] in self?.navigate(.settings) }),
            SheetAction(label: "Sign out", danger: true, run: logout),
        ]))
    }

    private func playlistSubmenu(_ tracks: [Track]) -> [SheetAction] {
        let lists = LibraryModel.shared.playlists
        if lists.isEmpty { Task { await LibraryModel.shared.loadPlaylists() } }
        return [SheetAction(label: "New playlist", run: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.newPlaylistFor = tracks }
        })] + lists.map { pl in
            SheetAction(label: pl.name, run: {
                let hashes = tracks.map { $0.hash.isEmpty ? ($0.isrc ?? "") : $0.hash }.filter { !$0.isEmpty }
                Task { try? await API.shared.addToPlaylist(pl.id, hashes: hashes); await LibraryModel.shared.loadPlaylists() }
            })
        }
    }

    func createPlaylist(_ name: String, adding tracks: [Track]) {
        Task {
            guard let id = try? await API.shared.createPlaylist(name) else { return }
            let hashes = tracks.map { $0.hash }.filter { !$0.isEmpty }
            if !hashes.isEmpty { try? await API.shared.addToPlaylist(id, hashes: hashes) }
            await LibraryModel.shared.loadPlaylists()
            if tracks.isEmpty, !id.isEmpty { navigate(.playlist(id)) }
        }
    }
}

enum Share {
    @MainActor static func link(_ path: String) {
        guard let url = URL(string: "https://synkmusic.co.uk" + path) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
            while let p = top.presentedViewController { top = p }
            top.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
        }
    }
}

/// Glass card: cover, title and subtitle, then rows; submenus slide in; Cancel below.
struct ActionSheetView: View {
    let model: ActionSheetModel
    @Environment(\.dismiss) private var dismiss
    @State private var sub: SheetAction?

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if let sub {
                        Button { withAnimation(.easeOut(duration: 0.2)) { self.sub = nil } } label: {
                            HStack(spacing: 4) {
                                SynkIcon(SynkIcons.arrowLeft, size: 18)
                                Text(sub.label).font(sans: 15, 600).foregroundStyle(Theme.fg)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    } else {
                        Artwork(url: model.cover, radius: 8, round: model.round).frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.title).font(sans: 15, 600).foregroundStyle(Theme.fg).lineLimit(1)
                            if !model.subtitle.isEmpty { Text(model.subtitle).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1) }
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .hairline(0)
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sub?.submenu ?? model.items) { it in
                            Button {
                                if let s = it.submenu, !s.isEmpty {
                                    withAnimation(.easeOut(duration: 0.2)) { sub = it }
                                } else {
                                    it.run?()
                                    dismiss()
                                }
                            } label: {
                                HStack {
                                    Text(it.label).font(sans: 17).foregroundStyle(it.danger ? Color(hex: 0xFF6B6B) : Theme.fg).lineLimit(1)
                                    Spacer()
                                    if let s = it.submenu { Text("\(s.count)").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.4)) }
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .contentShape(Rectangle())
                                .hairline(0)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .glass(Color(hex: 0x1E1E20), RoundedRectangle(cornerRadius: 22, style: .continuous), opacity: 0.7)
            Button { dismiss() } label: {
                Text("Cancel").font(sans: 17, 600).foregroundStyle(Theme.fg)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .glass(Color(hex: 0x1E1E20), RoundedRectangle(cornerRadius: 18, style: .continuous), opacity: 0.7, interactive: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .presentationDetents([.medium, .large])
        .presentationBackground(.clear)
        .presentationDragIndicator(.hidden)
    }
}

/// Round account button: the avatar, or the initial on bone.
struct AvatarButton: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        Button { Sheets.shared.account(session.user) { session.logout() } } label: {
            ZStack {
                Circle().fill(Theme.bone)
                Text(String((session.user?.username ?? "?").prefix(1)).uppercased()).font(display: 15, 700).foregroundStyle(Color.black)
                if let a = session.user?.avatarUrl, !a.isEmpty { RemoteImage(url: a).clipShape(Circle()) }
            }
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Account")
    }
}

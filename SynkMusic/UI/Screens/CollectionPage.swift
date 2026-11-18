import SwiftUI

/// Album and playlist page in the Apple Music style: the artwork across the top
/// fading into a page tinted with its colour, the centred title, Shuffle, Play
/// and Download, the description with MORE, a search field for the songs, and
/// the title moving into the bar once the header has scrolled away.
struct CollectionPage<MenuItems: View>: View {
    let cover: String
    let title: String
    var subtitle = ""
    var onSubtitle: (() -> Void)?
    var description = ""
    let tracks: [Track]
    var numbered = false
    var fromPlaylist: String?
    var onRemoved: (() -> Void)?
    var footer = ""
    var shareURL: URL?
    @ViewBuilder var menu: () -> MenuItems

    @EnvironmentObject private var player: PlayerController
    @Environment(\.playTrack) private var play
    @State private var tint = Color(hex: 0x141414)
    @State private var scrolled = false
    @State private var filter = ""
    @State private var showAll = false

    private var shown: [Track] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return tracks }
        return tracks.filter { $0.displayTitle.localizedCaseInsensitiveContains(q) || $0.artist.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        let width = UIScreen.main.bounds.width
        ScrollView {
            VStack(spacing: 0) {
                Artwork(url: cover, radius: 0)
                    .frame(width: width, height: width)
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [.clear, tint], startPoint: .top, endPoint: .bottom).frame(height: width * 0.45)
                    }
                    .clipped()
                VStack(spacing: 2) {
                    Text(title).font(sans: 20, 700).foregroundStyle(Theme.fg).multilineTextAlignment(.center).lineLimit(2)
                    if !subtitle.isEmpty {
                        Button { onSubtitle?() } label: {
                            Text(subtitle).font(sans: 18).foregroundStyle(Theme.fg.opacity(0.85)).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .disabled(onSubtitle == nil)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, -width * 0.12)
                HStack(spacing: 16) {
                    Button {
                        guard !tracks.isEmpty else { return }
                        if !player.shuffle { player.setShuffle(true) }
                        let i = Int.random(in: 0..<tracks.count)
                        play(tracks[i], tracks)
                    } label: {
                        Image(systemName: "shuffle").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.fg).glassCircle(48)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Shuffle")
                    Button { if let f = tracks.first { play(f, tracks) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 16, weight: .bold))
                            Text("Play").font(sans: 18, 600)
                        }
                        .foregroundStyle(Color.black)
                        .frame(width: 180, height: 48)
                        .background(Capsule().fill(Theme.fg))
                    }
                    .buttonStyle(PressStyle())
                    CollectionDownloadButton(tracks: tracks)
                }
                .padding(.top, 16)
                if !description.isEmpty {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(description).font(sans: 15).foregroundStyle(Theme.fg.opacity(0.65))
                            .lineLimit(showAll ? nil : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !showAll {
                            Button { withAnimation(.easeOut(duration: 0.2)) { showAll = true } } label: {
                                Text("MORE").font(sans: 14, 700).foregroundStyle(Theme.fg)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
                Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 20).padding(.top, 16)
                LazyVStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, index: i, numbered: numbered, fromPlaylist: fromPlaylist, onRemoved: onRemoved) { play(t, tracks) }
                    }
                }
                .padding(.leading, 10)
                if !footer.isEmpty && filter.isEmpty {
                    Text(footer).font(sans: 14).foregroundStyle(Theme.fg.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.top, 16)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(tint.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) { g in g.contentOffset.y + g.contentInsets.top > width * 1.05 } action: { _, now in
            if now != scrolled { withAnimation(.easeOut(duration: 0.18)) { scrolled = now } }
        }
        .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(title).font(sans: 16, 600).foregroundStyle(Theme.fg).lineLimit(1)
                    if !subtitle.isEmpty { Text(subtitle).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.7)).lineLimit(1) }
                }
                .opacity(scrolled ? 1 : 0)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let shareURL {
                    ShareLink(item: shareURL) { Image(systemName: "square.and.arrow.up") }
                }
                MoreMenu { menu() }
            }
        }
        .tint(Theme.fg)
        .artTint(cover, value: 0.3, into: $tint)
    }
}

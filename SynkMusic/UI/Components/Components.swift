import SwiftUI
import UIKit

// MARK: environment

struct NowPlayingMark: Equatable {
    var hash: String?
    var playing = false
}

private struct NowPlayingKey: EnvironmentKey { static let defaultValue = NowPlayingMark() }
private struct BottomInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct PlayKey: EnvironmentKey { static let defaultValue: (Track, [Track]) -> Void = { _, _ in } }

extension EnvironmentValues {
    var nowPlaying: NowPlayingMark { get { self[NowPlayingKey.self] } set { self[NowPlayingKey.self] = newValue } }
    /// Space the floating tab bar and mini player cover at the bottom.
    var bottomInset: CGFloat { get { self[BottomInsetKey.self] } set { self[BottomInsetKey.self] = newValue } }
    var playTrack: (Track, [Track]) -> Void { get { self[PlayKey.self] } set { self[PlayKey.self] = newValue } }
}

// MARK: glass

extension View {
    /// Glass tinted by `tint`. Real Liquid Glass on iOS 26 and later; before
    /// that, frosted material with a top highlight and hairline edge (the web's .glass).
    @ViewBuilder
    func glass<S: InsettableShape>(_ tint: Color, _ shape: S, opacity: Double = 0.62, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint.opacity(opacity * 0.6)).interactive() : Glass.regular.tint(tint.opacity(opacity * 0.6)), in: shape)
        } else {
            self.background(
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint.opacity(opacity))
                    shape.fill(LinearGradient(stops: [
                        .init(color: .white.opacity(0.13), location: 0),
                        .init(color: .white.opacity(0.04), location: 0.42),
                        .init(color: .white.opacity(0.02), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                }
                .environment(\.colorScheme, .dark)
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.45), radius: 17, y: 10)
        }
    }

    /// A round glass button background (back, more, play buttons over content).
    func glassCircle(_ size: CGFloat) -> some View {
        frame(width: size, height: size).glass(Color(hex: 0x1E1E20), Circle(), opacity: 0.5, interactive: true)
    }

    /// A hairline along the bottom, starting `inset` from the leading edge.
    func hairline(_ inset: CGFloat) -> some View {
        overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, inset)
        }
    }
}

// MARK: titles

/// A page with a native large title (Host Grotesk, set in SynkMusicApp) that
/// collapses into the glass navigation bar, and the account button on the right.
struct LargeTitlePage<Content: View, Actions: View>: View {
    let title: String
    var showAvatar = true
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.ink)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                actions()
                if showAvatar { AvatarButton() }
            }
        }
    }
}

extension LargeTitlePage where Actions == EmptyView {
    init(title: String, showAvatar: Bool = true, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.showAvatar = showAvatar
        self.actions = { EmptyView() }
        self.content = content
    }
}

struct SectionTitle<Trailing: View>: View {
    let text: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(text).font(display: 22, 700).tracking(-0.4).foregroundStyle(Theme.fg)
            Spacer()
            trailing()
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.top, 22)
        .padding(.bottom, 10)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.text = text; trailing = { EmptyView() } }
}

// MARK: cards and buttons

/// Artwork with title and subtitle below, for shelves and grids.
struct ShelfCard: View {
    let image: String
    let title: String
    let subtitle: String
    var size: CGFloat? = 150
    var round = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: round ? .center : .leading, spacing: 0) {
                Artwork(url: image, radius: 8, round: round)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(width: size, height: size)
                Spacer().frame(height: 7)
                Text(title).font(sans: 13, 500).foregroundStyle(Theme.fg).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(sans: 13).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(width: size, alignment: round ? .center : .leading)
            .frame(maxWidth: size == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Tall Top Picks card: artwork above a panel in the artwork's colour.
struct TopPickCard: View {
    let image: String
    let kicker: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var panel = Color(hex: 0x2A2A2A)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Artwork(url: image, radius: 0).frame(width: 230, height: 230)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kicker.uppercased()).font(sans: 11, 600).tracking(0.4).foregroundStyle(Theme.fg.opacity(0.7)).lineLimit(1)
                    Text(title).font(sans: 16, 700).foregroundStyle(Theme.fg).lineLimit(1)
                    Text(subtitle).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.75)).lineLimit(1)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 230, height: 86, alignment: .topLeading)
            }
            .background(panel)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .artTint(image, value: 0.42, into: $panel)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct RoundButton: View {
    let icon: SynkVector
    var size: CGFloat = 36
    var tint: Color = Theme.fg
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SynkIcon(icon, size: size * 0.5, tint: tint)
                .glassCircle(size)
        }
        .buttonStyle(PressStyle())
    }
}

/// Wide rounded button in light grey glass, for Play and Shuffle.
struct GlassButton: View {
    let icon: SynkVector
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SynkIcon(icon, size: 18)
                Text(label).font(sans: 16, 600).foregroundStyle(Theme.fg)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.15)))
        }
        .buttonStyle(PressStyle())
    }
}

/// Album, playlist and artist header, centred.
struct CollectionHeader: View {
    let image: String
    let title: String
    let subtitle: String
    let meta: String
    var round = false
    var onSubtitle: (() -> Void)?
    let onPlay: () -> Void
    var onShuffle: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { g in
                Artwork(url: image, radius: 12, round: round)
                    .frame(width: g.size.width * 0.7, height: g.size.width * 0.7)
                    .shadow(color: .black.opacity(0.6), radius: 28, y: 12)
                    .frame(maxWidth: .infinity)
            }
            .aspectRatio(1 / 0.7, contentMode: .fit)
            Spacer().frame(height: 20)
            Text(title).font(display: 22, 700).tracking(-0.4).multilineTextAlignment(.center).foregroundStyle(Theme.fg)
            if !subtitle.isEmpty {
                Text(subtitle).font(sans: 18).foregroundStyle(Theme.fg).lineLimit(1).padding(.top, 2)
                    .onTapGesture { onSubtitle?() }
            }
            if !meta.isEmpty {
                Text(meta).font(sans: 12, 500).foregroundStyle(Theme.faint).padding(.top, 4)
            }
            Spacer().frame(height: 16)
            HStack(spacing: 12) {
                GlassButton(icon: SynkIcons.play, label: "Play", action: onPlay)
                if let onShuffle { GlassButton(icon: SynkIcons.shuffle, label: "Shuffle", action: onShuffle) }
            }
            Spacer().frame(height: 18)
        }
        .padding(.horizontal, 20)
    }
}

/// One row in a category list: small white icon, label, chevron, hairline.
struct CategoryRow: View {
    let icon: SynkVector
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                SynkIcon(icon, size: 20)
                Text(label).font(sans: 18).foregroundStyle(Theme.fg)
                Spacer()
                SynkIcon(SynkIcons.chevronRight, size: 16, tint: Theme.faint)
            }
            .padding(.trailing, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
            .hairline(36)
            .padding(.leading, 20)
        }
        .buttonStyle(.plain)
    }
}

struct Chip: View {
    let text: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).font(sans: 13, 500)
                .foregroundStyle(active ? Color.black : Theme.fg)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(active ? Theme.fg : Theme.surface2))
        }
        .buttonStyle(.plain)
    }
}

struct LikeButton: View {
    let track: Track
    var size: CGFloat = 20
    var tint: Color = Theme.muted
    @EnvironmentObject private var likes: LikesStore

    var body: some View {
        let on = likes.isLiked(track)
        Button { likes.toggle(track) } label: {
            SynkIcon(on ? SynkIcons.heartFilled : SynkIcons.heart, size: size, tint: on ? Theme.fg : tint)
                .frame(width: size + 16, height: size + 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PlayOverlay: View {
    let playing: Bool
    let size: CGFloat
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            SynkIcon(playing ? SynkIcons.pause : SynkIcons.play, size: size * 0.4)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

/// One song in a list. A tap plays it. Album lists are numbered (no artwork);
/// the playing song shows a play/pause mark.
struct TrackRow: View {
    let track: Track
    var index = 0
    var numbered = false
    var showLike = false
    var fromPlaylist: String?
    var onRemoved: (() -> Void)?
    let action: () -> Void
    @Environment(\.nowPlaying) private var now

    var body: some View {
        let current = now.hash != nil && now.hash == track.hash
        HStack(spacing: 0) {
            if numbered {
                ZStack(alignment: .leading) {
                    if current {
                        SynkIcon(now.playing ? SynkIcons.pause : SynkIcons.play, size: 14)
                    } else {
                        Text("\(track.trackNumber > 0 ? track.trackNumber : index + 1)").font(sans: 14).foregroundStyle(Theme.faint)
                    }
                }
                .frame(width: 30, alignment: .leading)
            } else {
                ZStack {
                    Artwork(url: track.coverUrl, radius: 8).frame(width: 48, height: 48)
                    if current { PlayOverlay(playing: now.playing, size: 48) }
                }
                Spacer().frame(width: 12)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(track.displayTitle).font(sans: 16, current ? 600 : 400).foregroundStyle(Theme.fg).lineLimit(1)
                    if track.explicit {
                        Text("E").font(sans: 9, 700).foregroundStyle(.black).padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 2).fill(Theme.fg.opacity(0.55)))
                    }
                }
                if !numbered {
                    Text(track.artist).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if showLike && !numbered { LikeButton(track: track) }
            Button { Sheets.shared.track(track, fromPlaylist: fromPlaylist, onRemoved: onRemoved) } label: {
                SynkIcon(SynkIcons.more, size: 22, tint: Theme.fg.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, numbered ? 6 : 7)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { if current { Playback.toggle() } else { action() } }
        .hairline(numbered ? 40 : 70)
    }
}

struct Spinner: View {
    var body: some View {
        ProgressView().tint(Theme.fg).frame(maxWidth: .infinity, minHeight: 200)
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).font(sans: 14).foregroundStyle(Theme.muted).padding(20).frame(maxWidth: .infinity, alignment: .leading)
    }
}


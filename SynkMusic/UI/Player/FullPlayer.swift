import SwiftUI

/// Now playing (components/m/NowPlaying.tsx): blurred drifting artwork behind,
/// the cover (smaller while paused) or a small header plus lyrics, devices or
/// the queue inline, then progress, transport, volume and the mode buttons.
struct FullPlayer: View {
    enum Mode { case player, lyrics, queue, devices }

    let onClose: () -> Void
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient
    @Environment(\.navigate) private var navigate
    @State private var mode = Mode.player
    @State private var showLt = false
    @State private var drag: CGFloat = 0

    var body: some View {
        let s = Playback.state()
        ZStack {
            Color.black.ignoresSafeArea()
            if let t = s.current {
                PlayerBackdrop(url: t.coverUrl).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack {
                        Button(action: onClose) { SynkIcon(SynkIcons.close, size: 28, tint: Theme.fg.opacity(0.85)).frame(width: 40, height: 40) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close player")
                            .padding(.leading, -8)
                        Spacer()
                    }
                    .frame(height: 40)
                    .padding(.bottom, 12)

                    if mode == .player {
                        GeometryReader { g in
                            let side = min(g.size.width, g.size.height, 360)
                            Artwork(url: t.coverUrl, radius: 14)
                                .frame(width: side, height: side)
                                .shadow(color: .black.opacity(0.55), radius: 30, y: 24)
                                .scaleEffect(s.isPlaying ? 1 : 0.85)
                                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: s.isPlaying)
                                .frame(width: g.size.width, height: g.size.height)
                        }
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.displayTitle).font(sans: 21, 600).foregroundStyle(Theme.fg).lineLimit(1)
                                Button { openArtist(t) } label: {
                                    Text(t.artist).font(sans: 19).foregroundStyle(Theme.fg.opacity(0.65)).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                            LikeButton(track: t, size: 20, tint: Theme.fg).glassCircle(40)
                            Button { Sheets.shared.track(t) } label: { SynkIcon(SynkIcons.more, size: 22).glassCircle(40) }
                                .buttonStyle(.plain)
                                .accessibilityLabel("More")
                        }
                        .padding(.top, 24)
                    } else {
                        HStack(spacing: 12) {
                            Artwork(url: t.coverUrl, radius: 8).frame(width: 56, height: 56)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.displayTitle).font(sans: 16, 600).foregroundStyle(Theme.fg).lineLimit(1)
                                Text(t.artist).font(sans: 14).foregroundStyle(Theme.fg.opacity(0.65)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            LikeButton(track: t, size: 20, tint: Theme.fg).glassCircle(40)
                        }
                        .padding(.top, 24)
                        Group {
                            switch mode {
                            case .lyrics: LyricsView(track: t, onSeek: { Playback.seek($0) }).padding(.horizontal, -24)
                            case .queue: QueuePanel()
                            case .devices: DevicesPanel(showLt: $showLt)
                            case .player: EmptyView()
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.top, 12)
                    }

                    PlayerProgress(quality: Playback.isRemote ? "" : s.quality).padding(.top, 16)

                    HStack {
                        transport(s.shuffle ? SynkIcons.shuffleActive : SynkIcons.shuffle, 24, s.shuffle ? 1 : 0.55, s.shuffle ? "Shuffle on" : "Shuffle off") { Playback.toggleShuffle() }
                        Spacer()
                        transport(SynkIcons.skipPrevious, 40, 1, "Previous") { Playback.prev() }
                        Spacer()
                        transport(s.isPlaying ? SynkIcons.pause : SynkIcons.play, 56, 1, s.isPlaying ? "Pause" : "Play") { Playback.toggle() }
                        Spacer()
                        transport(SynkIcons.skipNext, 40, 1, "Next") { Playback.next() }
                        Spacer()
                        transport(s.repeatMode == .one ? SynkIcons.repeatOne : SynkIcons.repeatAll, 24, s.repeatMode != .off ? 1 : 0.55, "Repeat \(s.repeatMode.name)") { Playback.cycleRepeat() }
                    }
                    .padding(.top, 8)

                    if mode == .player {
                        HStack(spacing: 12) {
                            SynkIcon(SynkIcons.volume, size: 16, tint: Theme.fg.opacity(0.6))
                            SeekBar(value: Double(player.volume), total: 1) { Playback.setVolume(Float($0)) }.frame(height: 24)
                            SynkIcon(SynkIcons.volume, size: 20, tint: Theme.fg.opacity(0.6))
                        }
                        .padding(.top, 20)
                    }

                    HStack {
                        Spacer()
                        modeButton(.lyrics, SynkIcons.lyrics, "Lyrics")
                        Spacer()
                        modeButton(.devices, Playback.isRemote ? SynkIcons.tv : SynkIcons.devices, "Devices")
                        Spacer()
                        modeButton(.queue, SynkIcons.queue, "Queue")
                        Spacer()
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
            }
        }
        .offset(y: max(0, drag))
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { v in if v.translation.height > 0 && abs(v.translation.width) < v.translation.height { drag = v.translation.height * 0.6 } }
                .onEnded { v in
                    if v.translation.height > 140 { onClose() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { drag = 0 }
                }
        )
        .sheet(isPresented: $showLt) {
            ListenTogetherSheet { showLt = false }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func openArtist(_ t: Track) {
        let h = t.artists.first?.artisthash ?? ""
        if !h.isEmpty { Sheets.shared.navigate(.artist(h)) } else if !t.artist.isEmpty { Sheets.shared.navigate(.artistNamed(t.artist)) }
    }

    private func transport(_ icon: SynkVector, _ size: CGFloat, _ alpha: Double, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SynkIcon(icon, size: size, tint: Theme.fg.opacity(alpha)).frame(width: max(44, size), height: max(44, size)).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func modeButton(_ m: Mode, _ icon: SynkVector, _ label: String) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.22)) { mode = mode == m ? .player : m } } label: {
            SynkIcon(icon, size: 24, tint: mode == m ? Theme.fg : Theme.fg.opacity(0.7))
                .frame(width: 44, height: 44)
                .background(Circle().fill(mode == m ? Color.white.opacity(0.2) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(mode == m ? .isSelected : [])
    }
}

/// "Playing Next", in play order (shuffle respected).
private struct QueuePanel: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient

    var body: some View {
        let s = Playback.state()
        let upNext: [Int] = Playback.isRemote
            ? Array(s.queue.indices.filter { $0 > s.index })
            : player.upNext()
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Playing Next").font(sans: 17, 600).foregroundStyle(Theme.fg).padding(.bottom, 8)
                ForEach(Array(upNext.prefix(100).enumerated()), id: \.offset) { _, qi in
                    let q = s.queue[qi]
                    Button { Playback.playIndex(qi) } label: {
                        HStack(spacing: 12) {
                            Artwork(url: q.coverUrl, radius: 6).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(q.displayTitle).font(sans: 15).foregroundStyle(Theme.fg).lineLimit(1)
                                Text(q.artist).font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .hairline(0)
                    }
                    .buttonStyle(.plain)
                }
                if upNext.isEmpty {
                    Text("Nothing queued.").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.5)).padding(.vertical, 24)
                }
            }
        }
    }
}

/// "Play on": this phone and your other SYNK devices, then Listen Together.
private struct DevicesPanel: View {
    @Binding var showLt: Bool
    @EnvironmentObject private var cdc: CdcClient
    @EnvironmentObject private var lt: LtClient

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Play on").font(sans: 17, 600).foregroundStyle(Theme.fg).padding(.bottom, 8)
                let list = cdc.devices.filter { $0.online || $0.deviceId == cdc.selfId }
                let mine = list.contains { $0.deviceId == cdc.selfId } ? list : [CdcDevice(deviceId: cdc.selfId, name: "This phone", type: "mobile")] + list
                ForEach(mine) { d in
                    let playing = d.deviceId == cdc.activeId || (cdc.activeId == nil && d.deviceId == cdc.selfId)
                    Button { if d.deviceId != cdc.activeId { cdc.transfer(to: d.deviceId) } } label: {
                        HStack {
                            Text(d.deviceId == cdc.selfId ? "This phone" : d.name).font(sans: 16).foregroundStyle(Theme.fg)
                            Spacer()
                            if playing { Text("Playing").font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)) }
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                        .hairline(0)
                    }
                    .buttonStyle(.plain)
                }
                Button { showLt = true } label: {
                    HStack {
                        Text("Listen Together").font(sans: 16).foregroundStyle(Theme.fg)
                        Spacer()
                        if lt.state.active { Text(lt.state.role == "host" ? "Hosting" : "Listening").font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55)) }
                    }
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { cdc.connect() }
    }
}

/// Seek bar with elapsed, quality and remaining time; redraws on its own.
struct PlayerProgress: View {
    let quality: String
    @EnvironmentObject private var clock: PlayerClock

    var body: some View {
        TimelineView(.periodic(from: .now, by: Playback.isRemote ? 0.5 : 60)) { _ in
            let pd = Playback.positionMs()
            let pos = pd.0
            let dur = pd.1
            VStack(spacing: 0) {
                SeekBar(value: Double(pos), total: Double(max(1, dur))) { Playback.seek(Int($0)) }
                    .frame(height: 24)
                HStack {
                    Text(Format.time(pos / 1000)).font(sans: 12).foregroundStyle(Theme.fg.opacity(0.6)).monospacedDigit()
                    Spacer()
                    if !quality.isEmpty { Text(quality).font(sans: 11, 600).foregroundStyle(Theme.fg.opacity(0.6)) }
                    Spacer()
                    Text("-" + Format.time(max(0, dur - pos) / 1000)).font(sans: 12).foregroundStyle(Theme.fg.opacity(0.6)).monospacedDigit()
                }
            }
        }
    }
}

/// Thin line that thickens and shows a knob while dragged; tap or drag to set.
struct SeekBar: View {
    let value: Double
    let total: Double
    let onSet: (Double) -> Void
    @State private var dragFrac: CGFloat?

    var body: some View {
        GeometryReader { g in
            let frac = dragFrac ?? CGFloat(total > 0 ? min(1, max(0, value / total)) : 0)
            let thick: CGFloat = dragFrac != nil ? 9 : 5
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2)).frame(height: thick)
                Capsule().fill(Theme.fg.opacity(0.85)).frame(width: g.size.width * frac, height: thick)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in dragFrac = min(1, max(0, v.location.x / max(1, g.size.width))) }
                    .onEnded { v in
                        let f = min(1, max(0, v.location.x / max(1, g.size.width)))
                        onSet(Double(f) * total)
                        dragFrac = nil
                    }
            )
        }
        .animation(.easeOut(duration: 0.12), value: dragFrac != nil)
    }
}

/// The artwork scaled up, heavily blurred, darkened and drifting slowly.
struct PlayerBackdrop: View {
    let url: String
    @State private var drift = false

    var body: some View {
        GeometryReader { g in
            Artwork(url: url, radius: 0)
                .frame(width: g.size.width, height: g.size.height)
                .scaleEffect(1.8)
                .offset(x: drift ? 40 : -40, y: drift ? 30 : -30)
                .blur(radius: 60)
                .overlay(Color.black.opacity(0.42))
                .clipped()
        }
        .onAppear {
            withAnimation(.linear(duration: 20).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

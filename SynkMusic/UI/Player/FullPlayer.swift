import SwiftUI

import AVKit

/// Now playing, laid out like Apple Music: the artwork across the top fading
/// into its colour, the title with favourite and "...", then progress with the
/// Lossless badge, transport, volume and the lyrics, AirPlay and queue buttons.
/// Lyrics and the queue swap the artwork for a small header; in lyrics the
/// controls fade away after a few seconds and come back on a tap.
struct FullPlayer: View {
    enum Mode { case player, lyrics, queue, devices }

    let onClose: () -> Void
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient
    @State private var mode = Mode.player
    @State private var showLt = false
    @State private var drag: CGFloat = 0
    @State private var tint = Color(hex: 0x2A1414)
    @State private var controlsHidden = false
    @State private var touched = Date()

    var body: some View {
        let s = Playback.state()
        ZStack {
            tint.ignoresSafeArea()
            if let t = s.current {
                if mode == .player {
                    GeometryReader { g in
                        let w = g.size.width
                        Artwork(url: t.coverUrl, radius: 0)
                            .frame(width: w, height: w * 1.12)
                            .clipped()
                            .overlay(alignment: .bottom) {
                                LinearGradient(colors: [tint.opacity(0), tint], startPoint: .top, endPoint: .bottom).frame(height: w * 0.5)
                            }
                    }
                    .ignoresSafeArea()
                    .transition(.opacity)
                } else {
                    PlayerBackdrop(url: t.coverUrl).ignoresSafeArea().transition(.opacity)
                }
                VStack(spacing: 0) {
                    Capsule().fill(Theme.fg.opacity(0.35)).frame(width: 36, height: 5).padding(.top, 6)
                        .onTapGesture(perform: onClose)
                        .accessibilityLabel("Close player")
                        .accessibilityAddTraits(.isButton)

                    if mode == .player {
                        Spacer(minLength: 0)
                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 1) {
                                Marquee(text: t.displayTitle, font: SynkFont.sans(21, 600))
                                Button { openArtist(t) } label: {
                                    Text(t.artist).font(sans: 19).foregroundStyle(Theme.fg.opacity(0.65)).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                            Spacer(minLength: 0)
                            headerButtons(t)
                        }
                    } else {
                        HStack(spacing: 12) {
                            Artwork(url: t.coverUrl, radius: 8).frame(width: 56, height: 56)
                                .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { mode = .player } }
                            VStack(alignment: .leading, spacing: 1) {
                                Marquee(text: t.displayTitle, font: SynkFont.sans(16, 600))
                                Text(t.artist).font(sans: 14).foregroundStyle(Theme.fg.opacity(0.65)).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            headerButtons(t)
                        }
                        .padding(.top, 20)
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

                    if !(mode == .lyrics && controlsHidden) {
                        VStack(spacing: 0) {
                            PlayerProgress(quality: Playback.isRemote ? "" : s.quality).padding(.top, 18)
                            HStack {
                                Spacer()
                                transport(SynkIcons.skipPrevious, 40, "Previous") { Playback.prev() }
                                Spacer()
                                transport(s.isPlaying ? SynkIcons.pause : SynkIcons.play, 56, s.isPlaying ? "Pause" : "Play") { Playback.toggle() }
                                Spacer()
                                transport(SynkIcons.skipNext, 40, "Next") { Playback.next() }
                                Spacer()
                            }
                            .padding(.top, 14)
                            HStack(spacing: 12) {
                                Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(Theme.fg.opacity(0.6))
                                SeekBar(value: Double(s.volume), total: 1) { Playback.setVolume(Float($0)) }.frame(height: 24)
                                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(Theme.fg.opacity(0.6))
                            }
                            .padding(.top, 22)
                            HStack {
                                Spacer()
                                modeButton(.lyrics, "quote.bubble", "Lyrics")
                                Spacer()
                                modeButton(.devices, Playback.isRemote ? "tv" : "airplay.audio", "Devices")
                                Spacer()
                                modeButton(.queue, "list.bullet", "Queue")
                                    .overlay(alignment: .topTrailing) {
                                        if s.shuffle && mode != .queue {
                                            Image(systemName: "shuffle").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.fg).offset(x: -2, y: 6)
                                        }
                                    }
                                Spacer()
                            }
                            .padding(.top, 14)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .artTint(s.current?.coverUrl ?? "", value: 0.32, into: $tint)
        .offset(y: max(0, drag))
        .simultaneousGesture(TapGesture().onEnded { wake() })
        .gesture(
            DragGesture(minimumDistance: 24)
                .onChanged { v in if v.translation.height > 0 && abs(v.translation.width) < v.translation.height { drag = v.translation.height * 0.6 } }
                .onEnded { v in
                    if v.translation.height > 140 { onClose() }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { drag = 0 }
                }
        )
        .task(id: "\(touched.timeIntervalSince1970)-\(mode == .lyrics)-\(s.isPlaying)") {
            guard mode == .lyrics, s.isPlaying else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation(.easeInOut(duration: 0.35)) { controlsHidden = true } }
        }
        .sheet(isPresented: $showLt) {
            ListenTogetherSheet { showLt = false }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private func wake() {
        touched = Date()
        if controlsHidden { withAnimation(.easeInOut(duration: 0.3)) { controlsHidden = false } }
    }

    @ViewBuilder private func headerButtons(_ t: Track) -> some View {
        LikeButton(track: t, size: 20, tint: Theme.fg).frame(width: 36, height: 36)
        Menu { TrackMenuItems(track: t) } label: {
            SynkIcon(SynkIcons.more, size: 22).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More")
    }

    private func openArtist(_ t: Track) {
        let h = t.artists.first?.artisthash ?? ""
        if !h.isEmpty { Sheets.shared.navigate(.artist(h)) } else if !t.artist.isEmpty { Sheets.shared.navigate(.artistNamed(t.artist)) }
    }

    private func transport(_ icon: SynkVector, _ size: CGFloat, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SynkIcon(icon, size: size, tint: Theme.fg).frame(width: max(44, size), height: max(44, size)).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }

    private func modeButton(_ m: Mode, _ symbol: String, _ label: String) -> some View {
        let on = mode == m
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) { mode = on ? .player : m; controlsHidden = false }
            touched = Date()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(on ? tint : Theme.fg.opacity(0.75))
                .frame(width: 40, height: 40)
                .background(Circle().fill(on ? Theme.fg.opacity(0.8) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One line that scrolls sideways when it does not fit, pausing at the start.
struct Marquee: View {
    let text: String
    let font: Font
    @State private var full: CGFloat = 0
    @State private var box: CGFloat = 0
    @State private var go = false

    var body: some View {
        let over = full - box
        Text(text).font(font).foregroundStyle(Theme.fg).lineLimit(1).fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { full = $0 }
            .offset(x: over > 0 && go ? -(over + 24) : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { box = $0 }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: over > 0 ? 0.9 : 1), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .task(id: "\(text)-\(over > 0)") {
                go = false
                guard over > 0 else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.linear(duration: Double(over + 24) / 30)) { go = true }
                    try? await Task.sleep(nanoseconds: UInt64((Double(over + 24) / 30 + 2) * 1_000_000_000))
                    withAnimation(.easeOut(duration: 0.3)) { go = false }
                }
            }
            .accessibilityLabel(text)
    }
}

/// Shuffle, repeat and autoplay as pills, then Continue Playing in play order.
/// Without shuffle the songs can be dragged into a new order.
private struct QueuePanel: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var cdc: CdcClient
    @ObservedObject private var settings = SettingsStore.shared

    var body: some View {
        let s = Playback.state()
        let upNext: [Int] = Playback.isRemote
            ? Array(s.queue.indices.filter { $0 > s.index })
            : player.upNext()
        let canMove = !Playback.isRemote && !s.shuffle
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                pill(s.shuffle ? "shuffle" : "shuffle", on: s.shuffle, "Shuffle") { Playback.toggleShuffle() }
                pill(s.repeatMode == .one ? "repeat.1" : "repeat", on: s.repeatMode != .off, "Repeat") { Playback.cycleRepeat() }
                pill("infinity", on: settings.autoplay, "Autoplay") { settings.autoplay.toggle() }
            }
            .padding(.bottom, 16)
            Text("Continue Playing").font(sans: 17, 600).foregroundStyle(Theme.fg)
            if settings.autoplay {
                Text("Similar music plays when this ends").font(sans: 13).foregroundStyle(Theme.fg.opacity(0.55))
            }
            List {
                ForEach(Array(upNext.prefix(100)), id: \.self) { qi in
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
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(Theme.fg.opacity(0.12))
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .deleteDisabled(true)
                    .moveDisabled(!canMove)
                }
                .onMove { from, to in
                    guard canMove, let f = from.first else { return }
                    let src = upNext[f]
                    let dst = to > f ? upNext[min(to - 1, upNext.count - 1)] : upNext[min(to, upNext.count - 1)]
                    player.moveInQueue(from: src, to: dst)
                }
                if upNext.isEmpty {
                    Text("Nothing queued.").font(sans: 15).foregroundStyle(Theme.fg.opacity(0.5))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(canMove ? .active : .inactive))
            .tint(Theme.fg)
            .padding(.top, 6)
        }
    }

    private func pill(_ symbol: String, on: Bool, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Color.black.opacity(0.75) : Theme.fg.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Capsule().fill(on ? Theme.fg.opacity(0.85) : Color.white.opacity(0.14)))
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The system AirPlay and Bluetooth picker.
private struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = .white
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// "Play on": this phone and your other SYNK devices, then Listen Together.
private struct DevicesPanel: View {
    @Binding var showLt: Bool
    @EnvironmentObject private var cdc: CdcClient
    @EnvironmentObject private var lt: LtClient

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("AirPlay & Bluetooth").font(sans: 16).foregroundStyle(Theme.fg)
                    Spacer()
                    RoutePicker().frame(width: 36, height: 36)
                }
                .padding(.vertical, 8)
                .hairline(0)
                .padding(.bottom, 16)
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
                    if !quality.isEmpty { QualityBadge(quality: quality) }
                    Spacer()
                    Text("-" + Format.time(max(0, dur - pos) / 1000)).font(sans: 12).foregroundStyle(Theme.fg.opacity(0.6)).monospacedDigit()
                }
            }
        }
    }
}

/// "Lossless" in a small capsule for ALAC and FLAC; tap it for the exact format.
struct QualityBadge: View {
    let quality: String
    @State private var detail = false

    var body: some View {
        let lossless = ["ALAC", "FLAC", "Lossless"].contains { quality.localizedCaseInsensitiveContains($0) }
        Button { detail.toggle() } label: {
            HStack(spacing: 3) {
                if lossless { Image(systemName: "waveform").font(.system(size: 8, weight: .bold)) }
                Text(lossless && !detail ? "Lossless" : quality).font(sans: 10, 600)
            }
            .foregroundStyle(Theme.fg.opacity(0.7))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
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

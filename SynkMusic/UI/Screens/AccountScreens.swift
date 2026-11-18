import SwiftUI
import UIKit

// MARK: You

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.navigate) private var navigate
    @Environment(\.playTrack) private var play
    @State private var profile: ProfileResponse?
    @State private var loading = true

    var body: some View {
        ScrollView {
            if let p = profile {
                content(p)
            } else if loading {
                Spinner().padding(.top, 200)
            } else {
                Text("Profile unavailable").font(sans: 15).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 200)
            }
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.user?.username) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let u = session.user else { loading = false; return }
        loading = true
        if let p = try? await API.shared.profile(u.username) {
            profile = p
        } else if profile == nil {
            var pu = ProfileUser()
            pu.id = u.id; pu.username = u.username; pu.avatarUrl = u.avatarUrl; pu.bannerUrl = u.bannerUrl; pu.bio = u.bio
            profile = ProfileResponse(user: pu)
        }
        loading = false
    }

    @ViewBuilder private func content(_ p: ProfileResponse) -> some View {
        let role = p.user.roles.first
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Theme.surface2
                if let b = p.user.bannerUrl, !b.isEmpty { RemoteImage(url: b) }
                LinearGradient(colors: [.clear, Theme.ink], startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 220)
            .clipped()
            VStack(alignment: .leading, spacing: 0) {
                Artwork(url: p.user.avatarUrl ?? "", round: true).frame(width: 96, height: 96)
                Spacer().frame(height: 10)
                HStack(spacing: 8) {
                    Text(p.user.username).font(sans: 28, 700).foregroundStyle(Theme.fg)
                    if let role {
                        Text(role.uppercased()).font(sans: 9, 700)
                            .foregroundStyle(role == "owner" ? Color(hex: 0xFFE066) : Theme.fg)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(role == "owner" ? Color(hex: 0xFFE066, alpha: 0.2) : Theme.surface2))
                    }
                }
                Text("\(p.user.followerCount) followers, \(p.user.followingCount) following").font(sans: 12).foregroundStyle(Theme.muted)
                if let bio = p.user.bio, !bio.isEmpty {
                    Text(bio).font(sans: 14).foregroundStyle(Theme.muted).padding(.top, 10)
                }
                if let s = p.stats {
                    Spacer().frame(height: 16)
                    HStack(spacing: 8) { stat("Streams", s.totalListens); stat("Minutes", s.totalMinutesListened) }
                    Spacer().frame(height: 8)
                    HStack(spacing: 8) { stat("Tracks", s.uniqueTracks); stat("Playlists", s.playlistCount) }
                }
                if !p.mutualArtists.isEmpty {
                    Text("You both listen to").font(sans: 12).foregroundStyle(Theme.muted).padding(.top, 16).padding(.bottom, 6)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(p.mutualArtists, id: \.self) { n in
                                Text(n).font(sans: 13).foregroundStyle(Theme.fg).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Capsule().fill(Theme.surface2))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, -48)
            if !p.topArtists.isEmpty {
                heading("Top artists").padding(.top, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(p.topArtists, id: \.self) { a in
                            VStack(alignment: .leading, spacing: 6) {
                                Artwork(url: a.image, round: true).frame(width: 98, height: 98)
                                Text(a.name).font(sans: 13).foregroundStyle(Theme.fg).lineLimit(1)
                            }
                            .frame(width: 110, alignment: .leading)
                            .padding(6)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
            if !p.onRepeat.isEmpty {
                heading("On repeat").padding(.top, 16)
                ForEach(Array(p.onRepeat.prefix(6).enumerated()), id: \.offset) { _, t in
                    TrackRow(track: t) { play(t, p.onRepeat) }.padding(.horizontal, 16)
                }
            }
            if !p.likedSongs.isEmpty {
                heading("Recently liked").padding(.top, 16)
                ForEach(Array(p.likedSongs.prefix(6).enumerated()), id: \.offset) { _, t in
                    TrackRow(track: t) { play(t, p.likedSongs) }.padding(.horizontal, 16)
                }
            }
            if let first = p.firstSong {
                heading("Where it started").padding(.top, 16)
                HStack(spacing: 12) {
                    Artwork(url: first.coverUrl, radius: 6).frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("FIRST SONG PLAYED").font(sans: 10, 700).tracking(1).foregroundStyle(Theme.muted)
                        Text(first.displayTitle).font(sans: 16, 700).foregroundStyle(Theme.fg).lineLimit(1)
                        Text(first.artist).font(sans: 13).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                .padding(.horizontal, 16)
            }
            VStack(spacing: 10) {
                outline("Settings") { navigate(.settings) }
                outline("Sign out") { session.logout() }
            }
            .padding(20)
        }
    }

    private func heading(_ t: String) -> some View {
        Text(t).font(sans: 18, 700).foregroundStyle(Theme.fg).padding(.horizontal, 20).padding(.bottom, 8)
    }

    private func stat(_ label: String, _ v: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(v)").font(sans: 18, 700).foregroundStyle(Theme.fg)
            Text(label).font(sans: 12).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
    }

    private func outline(_ t: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(sans: 15, 500).foregroundStyle(Theme.fg).frame(maxWidth: .infinity).frame(height: 44)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: Stats

struct AnalyticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var period = "week"
    @State private var stats = DetailedStats()
    @State private var artists: [TopArtistItem] = []
    @State private var achievements: [Achievement] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("week", "7 days"), ("month", "30 days"), ("year", "Year"), ("all", "All time")], id: \.0) { k, label in
                            Chip(text: label, active: period == k) { period = k }
                        }
                    }
                }
                Spacer().frame(height: 20)
                HStack(spacing: 10) { tile("Streams", Format.compact(stats.totalStreams)); tile("Time", Format.durationLong(stats.totalDurationMs / 1000)) }
                Spacer().frame(height: 10)
                HStack(spacing: 10) { tile("Tracks", Format.compact(stats.uniqueTracks)); tile("Artists", Format.compact(stats.uniqueArtists)) }
                if !stats.daily.isEmpty {
                    header("Daily streams")
                    Bars(values: stats.daily.map { $0.streams }).frame(height: 120)
                    header("Listening time")
                    Area(values: stats.daily.map { $0.minutes }).frame(height: 100)
                }
                if stats.hourly.count == 24 && stats.hourly.contains(where: { $0 > 0 }) {
                    header("When you listen")
                    Bars(values: stats.hourly).frame(height: 80)
                }
                if !artists.isEmpty {
                    header("Top artists")
                    ForEach(artists, id: \.self) { a in
                        HStack(spacing: 12) {
                            Artwork(url: a.image, round: true).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(sans: 15, 500).foregroundStyle(Theme.fg)
                                Text(a.helpText).font(sans: 12).foregroundStyle(Theme.faint)
                            }
                            Spacer()
                            Text("\(a.playcount) plays").font(sans: 12).foregroundStyle(Theme.faint)
                        }
                        .padding(.vertical, 6)
                    }
                }
                if !achievements.isEmpty {
                    header("Achievements")
                    ForEach(achievements, id: \.self) { a in achievement(a) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.ink)
        .navigationTitle("Your Stats")
        .navigationBarTitleDisplayMode(.large)
        .task(id: period) {
            let p = period
            async let s = try? API.shared.detailedStats(p)
            async let t = try? API.shared.topArtists(p)
            stats = await s ?? DetailedStats()
            artists = await t ?? []
        }
        .task { achievements = (try? await API.shared.achievements()) ?? [] }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(sans: 20, 700).foregroundStyle(Theme.fg).padding(.top, 20).padding(.bottom, 10)
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(sans: 22, 700).foregroundStyle(Theme.fg)
            Text(label).font(sans: 13).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface2))
    }

    private func achievement(_ a: Achievement) -> some View {
        let earned = a.tierIndex >= 0
        let pct: Double = {
            if earned, let next = a.nextThreshold { return min(1, max(0, Double(a.progress - a.threshold) / Double(max(1, next - a.threshold)))) }
            if earned { return 1 }
            return min(1, max(0, Double(a.progress) / Double(max(1, a.threshold))))
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(a.name).font(sans: 14, 600).foregroundStyle(Theme.fg)
                Spacer()
                if earned { Text(a.tier).font(sans: 11, 700).foregroundStyle(Theme.muted) }
            }
            Text(a.description).font(sans: 12).foregroundStyle(Theme.faint)
            ProgressView(value: pct).tint(Theme.fg).padding(.top, 8)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(earned ? Theme.surface2 : Theme.surface1))
        .padding(.vertical, 6)
    }
}

private struct Bars: View {
    let values: [Int]
    var body: some View {
        Canvas { ctx, size in
            let n = values.count
            guard n > 0 else { return }
            let mx = CGFloat(max(1, values.max() ?? 1))
            let gap: CGFloat = 3
            let w = (size.width - gap * CGFloat(n - 1)) / CGFloat(n)
            for (i, v) in values.enumerated() {
                let h = CGFloat(v) / mx * size.height
                ctx.fill(Path(CGRect(x: CGFloat(i) * (w + gap), y: size.height - h, width: w, height: h)), with: .color(.white.opacity(0.55)))
            }
        }
    }
}

private struct Area: View {
    let values: [Int]
    var body: some View {
        Canvas { ctx, size in
            let n = values.count
            guard n > 1 else { return }
            let mx = CGFloat(max(1, values.max() ?? 1))
            let step = size.width / CGFloat(n - 1)
            var line = Path(), fill = Path()
            fill.move(to: CGPoint(x: 0, y: size.height))
            for (i, v) in values.enumerated() {
                let p = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(v) / mx * size.height)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                fill.addLine(to: p)
            }
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(.white.opacity(0.1)))
            ctx.stroke(line, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
        }
    }
}

// MARK: Settings

struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.bottom, 32)
        }
        .background(Theme.ink)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct SettingsLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(sans: 11, 700).tracking(1.2).foregroundStyle(Theme.faint)
            .padding(.leading, 20).padding(.top, 20).padding(.bottom, 8)
    }
}

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface2))
            .padding(.horizontal, 16).padding(.vertical, 6)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.navigate) private var navigate

    var body: some View {
        SettingsPage(title: "Settings") {
            SettingsLabel(text: "Playback & Audio")
            SettingsCard {
                Text("Audio quality").font(sans: 15, 500).foregroundStyle(Theme.fg)
                Text("Higher qualities can be slow on first play").font(sans: 12).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(SettingsStore.qualities, id: \.0) { v, label in
                            let on = settings.audioQuality == v
                            Button { settings.audioQuality = v } label: {
                                Text(label).font(sans: 12, 600).foregroundStyle(on ? Theme.ink : Theme.muted)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Capsule().fill(on ? Theme.fg : Theme.surface3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 12)
            }
            toggle("Autoplay", "Keep playing similar music when your queue ends", $settings.autoplay)
            toggle("Gapless playback", "Preload the next track for seamless transitions", $settings.gapless)
            nav("Device tuning", "Correct your headphones with a measurement or a listening test") { navigate(.tuning) }
            nav("Equaliser", "Shape playback with a 10-band graphic EQ") { navigate(.equalizer) }
            SettingsLabel(text: "Downloads")
            nav("Downloaded songs", "Manage music saved for offline listening") { navigate(.downloads) }
            SettingsLabel(text: "App")
            nav("Diagnostics", "Recent playback and download problems, to copy and send") { navigate(.diagnostics) }
            SettingsCard {
                Text("Version").font(sans: 15, 500).foregroundStyle(Theme.fg)
                Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                    .font(sans: 12).foregroundStyle(Theme.muted)
            }
        }
    }

    private func toggle(_ label: String, _ hint: String, _ value: Binding<Bool>) -> some View {
        SettingsCard {
            Toggle(isOn: value) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(sans: 15, 500).foregroundStyle(Theme.fg)
                    Text(hint).font(sans: 12).foregroundStyle(Theme.muted)
                }
            }
            .tint(Theme.fg)
        }
    }

    private func nav(_ label: String, _ hint: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label).font(sans: 15, 500).foregroundStyle(Theme.fg)
                        Text(hint).font(sans: 12).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    SynkIcon(SynkIcons.chevronRight, size: 18, tint: Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct EqualizerView: View {
    @EnvironmentObject private var settings: SettingsStore
    private static let labels = ["32", "64", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
    private static let presets: [(String, [Double])] = [
        ("Flat", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        ("Bass Boost", [7, 6, 5, 3, 1, 0, 0, 0, 0, 0]),
        ("Treble Boost", [0, 0, 0, 0, 0, 1, 3, 5, 6, 7]),
        ("Vocal", [-2, -1, 0, 2, 4, 5, 4, 2, 0, -1]),
        ("Rock", [5, 4, 2, 0, -1, 0, 2, 4, 5, 5]),
        ("Pop", [-1, 0, 2, 4, 5, 4, 2, 0, -1, -2]),
        ("Jazz", [4, 3, 1, 2, -1, -1, 0, 1, 3, 4]),
        ("Classical", [4, 3, 2, 0, 0, 0, -1, -1, 2, 3]),
        ("Electronic", [6, 5, 1, 0, -2, 1, 0, 2, 5, 6]),
        ("Acoustic", [4, 3, 2, 1, 2, 1, 2, 3, 3, 2]),
    ]

    var body: some View {
        SettingsPage(title: "Equaliser") {
            SettingsCard {
                Toggle(isOn: $settings.eqEnabled) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Enable equaliser").font(sans: 15, 500).foregroundStyle(Theme.fg)
                        Text("Shape playback with a 10-band graphic EQ").font(sans: 12).foregroundStyle(Theme.muted)
                    }
                }
                .tint(Theme.fg)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EqualizerView.presets, id: \.0) { name, gains in
                        let on = settings.eqBands == gains
                        Button { settings.eqBands = gains } label: {
                            Text(name).font(sans: 13, 600).foregroundStyle(on ? Theme.ink : Theme.muted)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(Capsule().fill(on ? Theme.fg : Theme.surface3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            HStack(spacing: 0) {
                ForEach(0..<10, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text("\(Int(settings.eqBands[i]))").font(sans: 10).foregroundStyle(Theme.muted)
                        VerticalSlider(value: Binding(
                            get: { settings.eqBands[i] },
                            set: { v in var b = settings.eqBands; b[i] = v.rounded(); settings.eqBands = b }
                        ))
                        .frame(width: 28, height: 160)
                        Text(EqualizerView.labels[i]).font(sans: 10).foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 16)
        }
    }
}

/// -12 to +12 dB, dragged vertically.
struct VerticalSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            let f = CGFloat((value + 12) / 24)
            ZStack(alignment: .bottom) {
                Capsule().fill(Theme.surface3).frame(width: 4)
                Capsule().fill(Theme.fg).frame(width: 4, height: h * f)
                Circle().fill(Theme.fg).frame(width: 18, height: 18).offset(y: -(h - 18) * f)
            }
            .frame(width: g.size.width, height: h)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let ff = 1 - min(1, max(0, v.location.y / h))
                value = Double(ff) * 24 - 12
            })
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var downloads: DownloadStore
    @Environment(\.playTrack) private var play

    var body: some View {
        SettingsPage(title: "Downloads") {
            let tracks = downloads.tracks
            if tracks.isEmpty {
                Text("No downloads yet").font(sans: 14).foregroundStyle(Theme.faint).frame(maxWidth: .infinity).padding(.top, 120)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(tracks.enumerated()), id: \.offset) { i, t in
                        TrackRow(track: t, index: i, showLike: false) { play(t, tracks) }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}

// MARK: Device tuning

struct DeviceTuningView: View {
    private enum Page { case main, find, intro, test, done }
    @EnvironmentObject private var manager: DeviceTuningManager
    @Environment(\.dismiss) private var dismiss
    @State private var page = Page.main
    @State private var index = 0
    @State private var offsets = [Double](repeating: 0, count: TuningMath.testBands.count)
    @State private var query = ""
    @State private var results: [AutoEqResult] = []
    @State private var status = ""
    @State private var beeps = BeepPlayer()

    var body: some View {
        let profile = manager.current
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                switch page {
                case .main: mainPage(profile)
                case .find: findPage()
                case .intro: introPage()
                case .test: testPage()
                case .done: donePage()
                }
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.ink)
        .navigationTitle(page == .find ? "Find your model" : page == .main ? "Device tuning" : "Listening test")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(page != .main)
        .toolbar {
            if page != .main {
                ToolbarItem(placement: .topBarLeading) {
                    Button { back() } label: { SynkIcon(SynkIcons.arrowLeft, size: 20) }.accessibilityLabel("Back")
                }
            }
        }
        .onAppear { manager.refresh() }
        .onDisappear { beeps.stop() }
        .onChange(of: index) { _, _ in setBeep() }
        .onChange(of: page) { _, _ in setBeep() }
    }

    private func back() {
        if page == .main { dismiss() } else { beeps.stop(); page = .main }
    }

    private func setBeep() {
        guard page == .test else { return }
        let hz = TuningMath.testBands[index]
        beeps.set(freq: hz, gainDb: TuningMath.expectedOffset(hz) + offsets[index])
    }

    private func startTest(_ to: Page) {
        index = 0
        offsets = offsets.map { _ in 0 }
        PlayerController.shared.pause()
        beeps.set(freq: 0, gainDb: 0)
        beeps.start()
        page = to
    }

    @ViewBuilder private func mainPage(_ profile: DeviceTuning?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PLAYING THROUGH").font(sans: 11, 700).tracking(2).foregroundStyle(Theme.faint)
            Text(manager.output).font(sans: 18, 700).foregroundStyle(Theme.fg)
            let what = profile?.source == "test" ? "your listening test" : "the \(profile?.label ?? "") measurement"
            Text(profile == nil ? "Not tuned yet." : !(profile!.enabled) ? "Tuning is off. Saved from \(what)." : "Tuned from \(what).")
                .font(sans: 14).foregroundStyle(Theme.muted)
            if let profile { TuningCurve(filters: profile.filters).frame(height: 120).padding(.top, 14) }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface2))
        Spacer().frame(height: 16)
        pill("Take the listening test", primary: true) { startTest(.intro) }
        Spacer().frame(height: 10)
        pill("Find your model", primary: false) { query = manager.output; page = .find; search() }
        if let profile {
            Spacer().frame(height: 10)
            HStack(spacing: 10) {
                pill(profile.enabled ? "Turn off" : "Turn on", primary: false) { manager.setEnabled(!profile.enabled) }
                pill("Remove", primary: false) { manager.removeCurrent() }
            }
        }
        Text("SYNK applies a tuning automatically whenever these headphones are connected. Measured models come from the AutoEQ project. For headphones that haven't been measured, the listening test builds a correction from your answers. Tunings follow your account, so the same headphones are tuned on every SYNK app.")
            .font(sans: 12).foregroundStyle(Theme.faint).lineSpacing(4).padding(.top, 16)
    }

    @ViewBuilder private func findPage() -> some View {
        TextField("", text: $query).font(sans: 16).foregroundStyle(Theme.fg).tint(Theme.fg)
            .padding(14).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface3))
            .onChange(of: query) { _, _ in search() }
        if !status.isEmpty { Text(status).font(sans: 13).foregroundStyle(Theme.muted).padding(.top, 10) }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(results) { r in
                    Button { choose(r) } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(sans: 15, 600).foregroundStyle(Theme.fg)
                            Text("\(r.form), measured by \(r.source)").font(sans: 13).foregroundStyle(Theme.faint)
                        }
                        .padding(.vertical, 10).padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
        Text("Measurements from the AutoEQ project.").font(sans: 11).foregroundStyle(Theme.faint).padding(.vertical, 12)
    }

    @State private var searchJob: Task<Void, Never>?

    private func search() {
        searchJob?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.count < 2 { results = []; status = ""; return }
        searchJob = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            status = "Searching"
            do {
                let r = try await API.shared.tuningSearch(q)
                if Task.isCancelled { return }
                results = r
                status = r.isEmpty ? "No measured model matches that name. The listening test works for any headphones." : ""
            } catch {
                status = "Couldn't reach the measurement list. Try again in a moment."
            }
        }
    }

    private func choose(_ r: AutoEqResult) {
        status = "Loading measurement"
        Task {
            if let r2 = try? await API.shared.tuningProfile(r.id) {
                let (pre, filters) = r2
                manager.save(DeviceTuning(source: "autoeq", label: "\(r.name) (\(r.source))", autoEqId: r.id, preamp: pre, filters: filters))
                status = ""
                page = .main
            } else {
                status = "That measurement couldn't be loaded. Try another entry."
            }
        }
    }

    @ViewBuilder private func introPage() -> some View {
        Text("Use the headphones you want to tune: \(manager.output).").font(sans: 15, 600).foregroundStyle(Theme.bone)
        Text("You'll hear a reference beep, then a test beep, on repeat. Make the second beep as loud as the first using Quieter and Louder. There are \(TuningMath.testBands.count) beeps, from deep bass to treble.")
            .font(sans: 15).foregroundStyle(Theme.muted).lineSpacing(5).padding(.top, 12)
        Text("Playing now: the reference beep. Set your volume so it's quiet but clear, then keep it there for the whole test.")
            .font(sans: 15).foregroundStyle(Theme.muted).lineSpacing(5).padding(.top, 12)
        Spacer()
        pill("Start", primary: true) { page = .test }.padding(.bottom, 24)
    }

    @ViewBuilder private func testPage() -> some View {
        let hz = TuningMath.testBands[index]
        let level = offsets[index]
        Text("BEEP \(index + 1) OF \(TuningMath.testBands.count)").font(sans: 11, 700).tracking(2).foregroundStyle(Theme.faint)
        Text("Make the second beep as loud as the first").font(display: 24, 800).foregroundStyle(Theme.fg).padding(.top, 6)
        Spacer()
        Text(level == 0 ? "Level 0" : "Level \(level > 0 ? "+" : "")\(Int(level))").font(sans: 18, 700).foregroundStyle(Theme.bone)
            .frame(maxWidth: .infinity)
        Spacer().frame(height: 14)
        HStack(spacing: 10) {
            pill("Quieter", primary: false) { adjust(-1, hz) }
            pill("Louder", primary: false) { adjust(1, hz) }
        }
        Spacer()
        HStack(spacing: 10) {
            pill("Back", primary: false) { if index > 0 { index -= 1 } }.opacity(index > 0 ? 1 : 0.4)
            pill("Sounds the same", primary: true) {
                if index + 1 < TuningMath.testBands.count { index += 1 } else { beeps.stop(); page = .done }
            }
            .layoutPriority(1)
        }
        .padding(.bottom, 24)
    }

    private func adjust(_ d: Double, _ hz: Double) {
        offsets[index] = min(TuningMath.maxUserOffset(hz), max(-18, offsets[index] + d))
        setBeep()
    }

    @ViewBuilder private func donePage() -> some View {
        let result = TuningMath.fromListeningTest(offsets)
        Text("This is the correction SYNK will apply to \(manager.output). Below the line is turned down, above the line is turned up.")
            .font(sans: 15).foregroundStyle(Theme.muted).lineSpacing(5)
        TuningCurve(filters: result.filters).frame(height: 120).padding(.top, 16)
        Spacer()
        pill("Save tuning", primary: true) { manager.save(result); page = .main }
        Spacer().frame(height: 10)
        pill("Start again", primary: false) { startTest(.test) }.padding(.bottom, 24)
    }

    private func pill(_ text: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text).font(sans: 15, 700).foregroundStyle(primary ? Color.black : Theme.fg)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Capsule().fill(primary ? Theme.fg : Color.clear))
                .overlay(Capsule().strokeBorder(Color.white.opacity(primary ? 0 : 0.25)))
        }
        .buttonStyle(PressStyle())
    }
}

struct TuningCurve: View {
    let filters: [TuneFilter]
    var body: some View {
        Canvas { ctx, size in
            let mid = size.height / 2
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: mid)); $0.addLine(to: CGPoint(x: size.width, y: mid)) }, with: .color(.white.opacity(0.15)), lineWidth: 1)
            let lo = log10(20.0), hi = log10(20000.0)
            var path = Path()
            for i in 0...120 {
                let hz = pow(10, lo + (hi - lo) * Double(i) / 120)
                var db = 0.0
                for t in filters {
                    let w = log2(hz / t.fc)
                    switch t.type {
                    case "PK": db += t.gain * exp(-w * w * t.q * t.q * 0.9)
                    case "LSC": db += t.gain / (1 + exp(w * 4))
                    default: db += t.gain / (1 + exp(-w * 4))
                    }
                }
                let p = CGPoint(x: CGFloat(i) / 120 * size.width, y: mid - CGFloat(min(12, max(-12, db)) / 12) * (mid - 6))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(Theme.bone), lineWidth: 2.5)
        }
    }
}

struct DiagnosticsView: View {
    @ObservedObject private var log = DebugLog.shared

    var body: some View {
        SettingsPage(title: "Diagnostics") {
            HStack(spacing: 10) {
                Button { UIPasteboard.general.string = log.lines.joined(separator: "\n") } label: {
                    Text("Copy").font(sans: 15, 600).foregroundStyle(Color.black).frame(maxWidth: .infinity).frame(height: 44)
                        .background(Capsule().fill(Theme.fg))
                }
                Button { log.clear() } label: {
                    Text("Clear").font(sans: 15, 600).foregroundStyle(Theme.fg).frame(maxWidth: .infinity).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25)))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.bottom, 12)
            if log.lines.isEmpty {
                Text("Nothing logged since the app started.").font(sans: 14).foregroundStyle(Theme.muted).padding(.horizontal, 16)
            }
            ForEach(Array(log.lines.reversed().enumerated()), id: \.offset) { _, l in
                Text(l).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 3)
                    .textSelection(.enabled)
            }
        }
    }
}

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import UIKit

enum RepeatMode: Int {
    case off, all, one
    var name: String { ["off", "all", "one"][rawValue] }
    init(name: String) { self = name == "one" ? .one : name == "all" ? .all : .off }
}

/// What the player is doing, for the views, Connect and Listen Together.
struct PlayerSnapshot: Equatable {
    var current: Track? = nil
    var queue: [Track] = []
    var index = -1
    var isPlaying = false
    var positionMs = 0
    var durationMs = 0
    var loading = false
    var shuffle = false
    var repeatMode: RepeatMode = .off
    var volume: Float = 1
    var quality = ""
}

/// Position, published on its own so only the views that show it redraw.
@MainActor
final class PlayerClock: ObservableObject {
    static let shared = PlayerClock()
    @Published var positionMs = 0
    @Published var durationMs = 0
}

private final class SynkItem: AVPlayerItem {
    var trackHash = ""
    var title = ""
    var statusObservation: NSKeyValueObservation?
}

@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    @Published private(set) var queue: [Track] = []
    @Published private(set) var index = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var loading = false
    @Published private(set) var shuffle = false
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var volume: Float = 1
    @Published private(set) var quality = ""

    var current: Track? { queue.indices.contains(index) ? queue[index] : nil }

    private let player = AVQueuePlayer()
    private let clock = PlayerClock.shared
    private let tracker = ListenTracker()
    private lazy var prefetcher = Prefetcher()
    /// Play order as queue indices; shuffled when shuffle is on.
    private var order: [Int] = []
    private var loadToken = 0
    private var preloadToken = 0
    private var preloadedIndex: Int?
    private var retried: String?
    /// Songs whose ALAC was not ready in time this session; they stream as MP3.
    private var mp3Only: Set<String> = []
    private var wantsPlay = false
    private var observers: [NSObjectProtocol] = []
    private var kvo: [NSKeyValueObservation] = []
    private var timeObserver: Any?
    private var artworkFor = ""
    private var artwork: MPMediaItemArtwork?

    private init() {
        player.actionAtItemEnd = .advance
        player.automaticallyWaitsToMinimizeStalling = true
        configureSession()
        setupRemote()
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        kvo.append(player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.syncPlaying() }
        })
        kvo.append(player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.itemChanged() }
        })
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            let opts = (n.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) }
            Task { @MainActor in
                guard let self else { return }
                if type == .began { self.wantsPlay = false; self.syncPlaying() }
                if type == .ended, opts?.contains(.shouldResume) == true { self.play() }
            }
        })
        observers.append(nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] n in
            let reason = (n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            if reason == .oldDeviceUnavailable { Task { @MainActor in self?.pause() } }
        })
        observers.append(nc.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] n in
            let item = n.object as? SynkItem
            let err = (n.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription ?? "unknown error"
            Task { @MainActor in
                DebugLog.shared.add("stopped mid-song \(item?.title ?? ""): \(err)")
                self?.itemFailed(item)
            }
        })
        observers.append(nc.addObserver(forName: .AVPlayerItemPlaybackStalled, object: nil, queue: .main) { n in
            let title = (n.object as? SynkItem)?.title ?? ""
            Task { @MainActor in DebugLog.shared.add("stalled \(title)") }
        })
    }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
    }

    // MARK: state

    func snapshot() -> PlayerSnapshot {
        PlayerSnapshot(current: current, queue: queue, index: index, isPlaying: isPlaying,
                       positionMs: clock.positionMs, durationMs: clock.durationMs, loading: loading,
                       shuffle: shuffle, repeatMode: repeatMode, volume: volume, quality: quality)
    }

    var positionMs: Int {
        let t = player.currentTime().seconds
        return t.isFinite ? max(0, Int(t * 1000)) : clock.positionMs
    }

    private func tick() {
        let p = positionMs
        if clock.positionMs != p { clock.positionMs = p }
        if let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 {
            let ms = Int(d * 1000)
            if clock.durationMs != ms { clock.durationMs = ms; updateNowPlaying() }
        }
    }

    private func syncPlaying() {
        let playing = player.timeControlStatus == .playing || (wantsPlay && player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        let buffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if loading != (buffering && wantsPlay) && player.currentItem != nil { loading = buffering && wantsPlay }
        if playing != isPlaying {
            isPlaying = playing
            tracker.onPlayingChanged(playing)
            updateNowPlaying()
        }
    }

    // MARK: queue

    func playNow(_ track: Track, in list: [Track]? = nil) {
        let l = (list?.isEmpty == false) ? list! : [track]
        let i = l.firstIndex { $0.hash == track.hash } ?? 0
        playQueue(l, start: i)
    }

    func playQueue(_ tracks: [Track], start: Int, positionMs: Int = 0, autoplay: Bool = true) {
        guard !tracks.isEmpty else { return }
        let s = min(max(0, start), tracks.count - 1)
        queue = tracks
        rebuildOrder(keeping: s)
        load(s, positionMs: positionMs, autoplay: autoplay)
    }

    private func rebuildOrder(keeping i: Int) {
        let all = Array(queue.indices)
        if shuffle, queue.indices.contains(i) {
            order = [i] + all.filter { $0 != i }.shuffled()
        } else {
            order = all
        }
    }

    private func nextIndex(from i: Int, wrap: Bool) -> Int? {
        guard let p = order.firstIndex(of: i) else { return nil }
        if p + 1 < order.count { return order[p + 1] }
        return wrap && !order.isEmpty ? order[0] : nil
    }

    private func prevIndex(from i: Int) -> Int? {
        guard let p = order.firstIndex(of: i) else { return nil }
        if p > 0 { return order[p - 1] }
        return repeatMode == .all && !order.isEmpty ? order[order.count - 1] : nil
    }

    /// Queue indices still to play after the current song, in play order.
    func upNext() -> [Int] {
        guard let p = order.firstIndex(of: index) else { return [] }
        return Array(order[(p + 1)...])
    }

    /// The next song the player moves to by itself.
    private var upcomingIndex: Int? {
        repeatMode == .one ? index : nextIndex(from: index, wrap: repeatMode == .all)
    }

    // MARK: loading

    private func load(_ i: Int, positionMs: Int = 0, autoplay: Bool = true) {
        guard queue.indices.contains(i) else { return }
        loadToken += 1
        let token = loadToken
        let t = queue[i]
        index = i
        retried = retried == t.hash ? retried : nil
        loading = true
        quality = ""
        clock.positionMs = positionMs
        clock.durationMs = t.durationMillis
        wantsPlay = autoplay
        player.pause()
        player.removeAllItems()
        preloadedIndex = nil
        trackChanged()
        updateNowPlaying()
        Task {
            let item = await makeItem(t)
            guard token == loadToken else { return }
            guard let item else {
                loading = false
                skipAfterFailure(t)
                return
            }
            player.insert(item, after: nil)
            if positionMs > 0 { _ = await player.seek(to: CMTime(value: CMTimeValue(positionMs), timescale: 1000)) }
            guard token == loadToken else { return }
            if wantsPlay { player.play() }
            loading = false
            readQuality(item)
            preloadNext()
            prefetcher.update(window: prefetchWindow())
        }
    }

    private func makeItem(_ t: Track) async -> SynkItem? {
        guard let url = await resolve(t) else { return nil }
        let asset = AVURLAsset(url: url)
        // A song's first ALAC play waits for the server to convert all of it. Rather
        // than leave the player silent, use the MP3 for this play; the server keeps
        // converting, so the next play is lossless.
        if url.query?.contains("quality=alac") == true {
            let ready = await withTaskGroup(of: Bool.self) { g -> Bool in
                g.addTask { (try? await asset.loadTracks(withMediaType: .audio).first) != nil }
                g.addTask {
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    return false
                }
                let first = await g.next() ?? false
                g.cancelAll()
                return first
            }
            if !ready {
                asset.cancelLoading()
                mp3Only.insert(t.hash)
                DebugLog.shared.add("\(t.displayTitle): ALAC not ready, playing MP3 this time", issue: false)
                return await makeItem(t)
            }
        }
        let item = SynkItem(asset: asset)
        item.trackHash = t.hash
        item.title = t.displayTitle
        item.preferredForwardBufferDuration = 30
        do {
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                item.audioMix = EQTap.audioMix(for: a)
            }
        } catch {
            DebugLog.log("load \(t.displayTitle) (\(url.isFileURL ? "file" : "stream")): \(error.localizedDescription)")
        }
        // A stream that fails to open never reaches "failed to play to end".
        item.statusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard it.status == .failed else { return }
            let msg = it.error?.localizedDescription ?? "unknown error"
            Task { @MainActor in
                DebugLog.shared.add("item failed \(t.displayTitle): \(msg)")
                self?.itemFailed(it as? SynkItem)
            }
        }
        return item
    }

    /// A downloaded file, a prefetched file, or a fresh stream URL.
    private func resolve(_ t: Track) async -> URL? {
        if let local = DownloadStore.shared.localURL(t) {
            DebugLog.log("play \(t.displayTitle) from download (\(local.pathExtension))", issue: false)
            return local
        }
        let q = SettingsStore.shared.requestQuality
        if let cached = AudioCache.file(t.hash, quality: q) {
            DebugLog.log("play \(t.displayTitle) from cache (\(cached.pathExtension))", issue: false)
            return cached
        }
        // AVPlayer plays FLAC from a file but cannot open it over HTTP ("resource
        // unavailable"). For lossless or default the server converts FLAC to ALAC,
        // which streams; if it cannot, it sends a 320 MP3 instead.
        let streamQ = (q == nil || q == "flac") ? (mp3Only.contains(t.hash) ? "320" : "alac") : q!
        var tries = [streamQ]
        for fallback in ["320", "128"] where !tries.contains(fallback) { tries.append(fallback) }
        for quality in tries {
            do {
                if let u = try await API.shared.streamURL(t, quality: quality) {
                    DebugLog.log("play \(t.displayTitle) streaming \(quality)", issue: false)
                    return u
                }
            } catch {
                DebugLog.log("stream/token \(t.displayTitle) quality \(quality): \(error.localizedDescription)")
            }
        }
        return nil
    }

    private func preloadNext() {
        preloadToken += 1
        let token = preloadToken
        for item in player.items().dropFirst() { player.remove(item) }
        preloadedIndex = nil
        guard let n = upcomingIndex, queue.indices.contains(n) else { return }
        let t = queue[n]
        Task {
            guard let item = await makeItem(t), token == preloadToken, let cur = player.currentItem else { return }
            if player.canInsert(item, after: cur) {
                player.insert(item, after: cur)
                preloadedIndex = n
            }
        }
    }

    private func itemChanged() {
        guard let item = player.currentItem as? SynkItem else {
            // The queue ran out: nothing more to play.
            if player.items().isEmpty, !loading, current != nil, preloadedIndex == nil, wantsPlay {
                tracker.flush()
                wantsPlay = false
                syncPlaying()
                clock.positionMs = 0
                player.pause()
            }
            return
        }
        if let n = preloadedIndex, queue.indices.contains(n), queue[n].hash == item.trackHash {
            tracker.flush()
            index = n
            preloadedIndex = nil
            clock.positionMs = 0
            clock.durationMs = queue[n].durationMillis
            quality = ""
            readQuality(item)
            trackChanged()
            updateNowPlaying()
            preloadNext()
            prefetcher.update(window: prefetchWindow())
        }
    }

    private func itemFailed(_ item: SynkItem?) {
        guard let item, let t = current, item.trackHash == t.hash else { return }
        if let url = (item.asset as? AVURLAsset)?.url, !url.isFileURL {
            Task.detached { await PlayerController.probe(url, t.displayTitle) }
            if url.query?.contains("quality=alac") == true, !mp3Only.contains(t.hash) {
                mp3Only.insert(t.hash)
                DebugLog.shared.add("\(t.displayTitle): ALAC failed, trying MP3", issue: false)
                load(index, positionMs: positionMs, autoplay: true)
                return
            }
        }
        if retried != t.hash {
            retried = t.hash
            AudioCache.remove(t.hash)
            load(index, positionMs: positionMs, autoplay: true)
        } else {
            skipAfterFailure(t)
        }
    }

    /// Asks the server again for the first bytes and logs its answer, so a failed
    /// stream shows the status and error message, not just "resource unavailable".
    nonisolated static func probe(_ url: URL, _ title: String) async {
        var req = URLRequest(url: url)
        req.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20
        guard let (d, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse else {
            DebugLog.log("probe \(title): no answer")
            return
        }
        let type = http.value(forHTTPHeaderField: "Content-Type") ?? "?"
        let quality = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "quality" }?.value ?? "default"
        let body = type.contains("json") ? " " + String(decoding: d.prefix(200), as: UTF8.self) : ""
        DebugLog.log("probe \(title) (\(quality)): HTTP \(http.statusCode) \(type)\(body)")
    }

    private func skipAfterFailure(_ t: Track) {
        DebugLog.shared.add("skipping \(t.displayTitle) after a second failure")
        if let n = nextIndex(from: index, wrap: false) {
            retried = nil
            load(n)
        } else {
            wantsPlay = false
            syncPlaying()
        }
    }

    private func trackChanged() {
        extendForAutoplay()
        tracker.onTrackChanged(current)
        if isPlaying { tracker.onPlayingChanged(true) }
    }

    /// The playing song, then the next ones, so each is cached in full quality.
    private func prefetchWindow() -> [Track] {
        var out: [Track] = current.map { [$0] } ?? []
        var i = index
        var seen: Set<String> = Set(out.map { $0.hash })
        while out.count < Prefetcher.ahead + 1, let n = nextIndex(from: i, wrap: repeatMode == .all), n != index {
            let t = queue[n]
            if !seen.contains(t.hash) { out.append(t); seen.insert(t.hash) }
            i = n
        }
        return out
    }

    private func readQuality(_ item: AVPlayerItem) {
        let hash = (item as? SynkItem)?.trackHash
        Task {
            guard let a = try? await item.asset.loadTracks(withMediaType: .audio).first,
                  let desc = try? await a.load(.formatDescriptions).first,
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return }
            let rate = (try? await a.load(.estimatedDataRate)) ?? 0
            guard hash == current?.hash else { return }
            quality = PlayerController.describe(asbd, bitsPerSecond: rate)
        }
    }

    static func describe(_ d: AudioStreamBasicDescription, bitsPerSecond: Float) -> String {
        let codec: String
        switch d.mFormatID {
        case kAudioFormatFLAC: codec = "FLAC"
        case kAudioFormatAppleLossless: codec = "ALAC"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: codec = "AAC"
        case kAudioFormatOpus: codec = "OPUS"
        default: return ""
        }
        if codec == "FLAC" || codec == "ALAC" {
            var bits = Int(d.mBitsPerChannel)
            if bits == 0 {
                let f = Int(d.mFormatFlags)
                if f == Int(kAppleLosslessFormatFlag_16BitSourceData) { bits = 16 }
                else if f == Int(kAppleLosslessFormatFlag_20BitSourceData) { bits = 20 }
                else if f == Int(kAppleLosslessFormatFlag_24BitSourceData) { bits = 24 }
                else if f == Int(kAppleLosslessFormatFlag_32BitSourceData) { bits = 32 }
            }
            if bits > 0 && d.mSampleRate > 0 {
                let khz = d.mSampleRate / 1000
                let k = khz.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(khz)) : String(format: "%.1f", khz)
                return "\(codec) \(bits)/\(k)"
            }
            return codec
        }
        let kbps = Int(bitsPerSecond / 1000)
        return kbps > 0 ? "\(codec) \(kbps)" : codec
    }

    // MARK: transport

    func toggle() { isPlaying || (wantsPlay && loading) ? pause() : play() }

    func play() {
        guard current != nil else { return }
        if player.currentItem == nil {
            load(index, positionMs: 0, autoplay: true)
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        wantsPlay = true
        player.play()
        syncPlaying()
    }

    func pause() {
        wantsPlay = false
        player.pause()
        syncPlaying()
    }

    func next() {
        guard let n = nextIndex(from: index, wrap: repeatMode == .all) else { return }
        tracker.flush()
        load(n)
    }

    func prev() {
        if positionMs > 3000 { seek(ms: 0); return }
        guard let p = prevIndex(from: index) else { seek(ms: 0); return }
        tracker.flush()
        load(p)
    }

    func playIndex(_ i: Int) {
        guard queue.indices.contains(i) else { return }
        tracker.flush()
        load(i)
    }

    func seek(ms: Int) {
        let target = max(0, ms)
        clock.positionMs = target
        if player.currentItem == nil {
            if current != nil { load(index, positionMs: target, autoplay: wantsPlay) }
            return
        }
        player.seek(to: CMTime(value: CMTimeValue(target), timescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.updateNowPlaying() }
        }
    }

    func stop() {
        loadToken += 1
        preloadToken += 1
        tracker.flush()
        wantsPlay = false
        player.pause()
        player.removeAllItems()
        queue = []
        order = []
        index = -1
        isPlaying = false
        loading = false
        quality = ""
        clock.positionMs = 0
        clock.durationMs = 0
        prefetcher.update(window: [])
        updateNowPlaying()
    }

    func toggleShuffle() { setShuffle(!shuffle) }

    func setShuffle(_ on: Bool) {
        guard on != shuffle else { return }
        shuffle = on
        rebuildOrder(keeping: index)
        queueChanged()
    }

    func cycleRepeat() { setRepeat(RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off) }

    func setRepeat(_ m: RepeatMode) {
        guard m != repeatMode else { return }
        repeatMode = m
        queueChanged()
    }

    func setVolume(_ v: Float) {
        volume = min(1, max(0, v))
        player.volume = volume
    }

    func addNext(_ t: Track) {
        if queue.isEmpty { playQueue([t], start: 0); return }
        let at = min(index + 1, queue.count)
        queue.insert(t, at: at)
        order = order.map { $0 >= at ? $0 + 1 : $0 }
        if let p = order.firstIndex(of: index) { order.insert(at, at: p + 1) } else { order.append(at) }
        queueChanged()
    }

    func addToQueue(_ t: Track) {
        if queue.isEmpty { playQueue([t], start: 0); return }
        queue.append(t)
        order.append(queue.count - 1)
        queueChanged()
    }

    func removeFromQueue(_ i: Int) {
        guard queue.indices.contains(i), i != index else { return }
        queue.remove(at: i)
        order = order.filter { $0 != i }.map { $0 > i ? $0 - 1 : $0 }
        if i < index { index -= 1 }
        queueChanged()
    }

    func moveInQueue(from: Int, to: Int) {
        guard queue.indices.contains(from), queue.indices.contains(to), from != to else { return }
        let curHash = current?.hash
        let t = queue.remove(at: from)
        queue.insert(t, at: to)
        func remap(_ k: Int) -> Int {
            if k == from { return to }
            if from < to, k > from, k <= to { return k - 1 }
            if from > to, k >= to, k < from { return k + 1 }
            return k
        }
        order = order.map(remap)
        index = remap(index)
        if current?.hash != curHash, let h = curHash, let i = queue.firstIndex(where: { $0.hash == h }) { index = i }
        queueChanged()
    }

    func clearUpcoming() {
        guard queue.indices.contains(index), index < queue.count - 1 else { return }
        queue = Array(queue[0...index])
        order = order.filter { $0 <= index }
        queueChanged()
    }

    /// Autoplay (the infinity button): on the last song, add similar songs so
    /// the music keeps going once the queue runs out.
    private var extending = false
    private func extendForAutoplay() {
        guard SettingsStore.shared.autoplay, repeatMode == .off, !extending,
              nextIndex(from: index, wrap: false) == nil, let seed = current, !seed.artist.isEmpty else { return }
        extending = true
        Task { @MainActor in
            defer { extending = false }
            let have = Set(queue.map(\.hash))
            let more = ((try? await API.shared.artistRadio(seed.artist)) ?? []).filter { !have.contains($0.hash) }
            more.prefix(25).forEach { addToQueue($0) }
        }
    }

    private func queueChanged() {
        if player.currentItem != nil { preloadNext() }
        prefetcher.update(window: prefetchWindow())
    }

    // MARK: lock screen

    private func setupRemote() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.play() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.prev() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let ms = Int(e.positionTime * 1000)
            Task { @MainActor in self?.seek(ms: ms) }
            return .success
        }
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let t = current else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: t.displayTitle,
            MPMediaItemPropertyArtist: t.artist,
            MPMediaItemPropertyAlbumTitle: t.album,
            MPMediaItemPropertyPlaybackDuration: Double(clock.durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(positionMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if artworkFor == t.coverUrl, let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
        let cover = t.coverUrl
        if artworkFor != cover, let url = URL(string: cover) {
            artworkFor = cover
            artwork = nil
            Task {
                guard let img = await ImageCache.shared.image(url), cover == self.current?.coverUrl else { return }
                let art = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                self.artwork = art
                var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                i[MPMediaItemPropertyArtwork] = art
                MPNowPlayingInfoCenter.default().nowPlayingInfo = i
            }
        }
    }
}

/// Records listens so the server can update recents and analytics and scrobble,
/// the same calls as Android's ListenTracker (source "ios").
@MainActor
final class ListenTracker {
    private var current: Track?
    private var startedAt: Date?
    private var accumMs = 0

    func onTrackChanged(_ t: Track?) {
        flush()
        current = t
        accumMs = 0
        startedAt = nil
        guard let t, !t.artist.isEmpty, !t.displayTitle.isEmpty else { return }
        Task.detached { await API.shared.recordRecent(t) }
    }

    func onPlayingChanged(_ playing: Bool) {
        if playing {
            if current != nil && startedAt == nil { startedAt = Date() }
        } else {
            if let s = startedAt { accumMs += Int(Date().timeIntervalSince(s) * 1000); startedAt = nil }
            if let t = current, !t.artist.isEmpty { Task.detached { await API.shared.clearNowPlaying(t) } }
        }
    }

    func flush() {
        guard let t = current else { return }
        let elapsed = accumMs + (startedAt.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0)
        current = nil
        startedAt = nil
        accumMs = 0
        guard elapsed >= 3000, !t.artist.isEmpty, !t.displayTitle.isEmpty else { return }
        Task.detached {
            await API.shared.logTrack(t.hash, seconds: elapsed / 1000)
            if let isrc = t.isrc, !isrc.isEmpty { await API.shared.logAnalytics(t, isrc: isrc, listenedMs: elapsed) }
        }
    }
}

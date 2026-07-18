import Foundation
import AVFoundation
import MediaPlayer
import Combine

enum RepeatMode: Int { case off, all, one }

@MainActor
final class PlayerController: ObservableObject {
    static let shared = PlayerController()

    // Published playback state consumed by the mini/full players.
    @Published private(set) var current: Track?
    @Published private(set) var queue: [Track] = []
    @Published private(set) var index: Int = -1
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var loading = false
    @Published var shuffle = false
    @Published var repeatMode: RepeatMode = .off

    private let player = AVPlayer()
    private var originalQueue: [Track] = []
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private let tracker = ListenTracker()

    private init() {
        configureSession()
        setupRemoteCommands()
        addPeriodicObserver()
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.handleItemEnded() } }
    }

    // MARK: session

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    // MARK: queue control

    func playNow(_ track: Track, in list: [Track]? = nil) {
        let source = (list?.isEmpty == false) ? list! : [track]
        let start = source.firstIndex(where: { $0.hash == track.hash }) ?? 0
        playQueue(source, startIndex: start)
    }

    func playQueue(_ tracks: [Track], startIndex: Int) {
        guard !tracks.isEmpty else { return }
        originalQueue = tracks
        queue = shuffle ? shuffled(tracks, keeping: startIndex) : tracks
        let idx = shuffle ? 0 : startIndex
        index = idx
        current = queue[idx]
        loading = true
        Task { await load(index: idx, autoplay: true) }
    }

    // Resolve the stream URL up-front (like the fixed Android playQueue) so the
    // AVPlayerItem always has a real source before we call play().
    private func load(index idx: Int, autoplay: Bool) async {
        guard queue.indices.contains(idx) else { return }
        let track = queue[idx]
        index = idx
        current = track
        loading = true

        guard let url = await resolveStreamURL(track) else { loading = false; return }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        duration = Double(track.durationSeconds)
        loading = false
        if autoplay { player.play(); isPlaying = true }
        updateNowPlaying()
        tracker.onTrackChanged(track)
    }

    private func resolveStreamURL(_ track: Track) async -> URL? {
        // Prefer a local downloaded copy.
        if let local = DownloadStore.shared.localURL(track) { return local }
        let quality = SettingsStore.shared.audioQuality
        let body = StreamTokenRequest(id: track.hash, artist: track.artist, title: track.displayTitle,
                                      isrc: track.isrc, quality: quality == "default" ? nil : quality,
                                      durationMs: track.durationMs > 0 ? track.durationMs : nil)
        guard let token = try? await API.shared.streamToken(body) else { return nil }
        return URL(string: token.url, relativeTo: API.shared.base)?.absoluteURL
    }

    // MARK: transport

    func toggle() {
        if isPlaying { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
        tracker.onPlayingChanged(isPlaying, track: current)
        updateNowPlaying()
    }

    func next() {
        guard !queue.isEmpty else { return }
        if repeatMode == .one { seek(to: 0); player.play(); return }
        let n = index + 1
        if n < queue.count { Task { await load(index: n, autoplay: true) } }
        else if repeatMode == .all { Task { await load(index: 0, autoplay: true) } }
    }

    func previous() {
        guard !queue.isEmpty else { return }
        if position > 3 { seek(to: 0); return }
        let p = index - 1
        if p >= 0 { Task { await load(index: p, autoplay: true) } }
        else { seek(to: 0) }
    }

    func playIndex(_ idx: Int) {
        guard queue.indices.contains(idx) else { return }
        Task { await load(index: idx, autoplay: true) }
    }

    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time)
        position = seconds
        updateNowPlaying()
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        current = nil
        queue = []
        index = -1
    }

    func toggleShuffle() {
        shuffle.toggle()
        guard let cur = current else { return }
        if shuffle {
            queue = shuffled(originalQueue, keeping: originalQueue.firstIndex(where: { $0.hash == cur.hash }) ?? 0)
        } else {
            queue = originalQueue
        }
        index = queue.firstIndex(where: { $0.hash == cur.hash }) ?? 0
    }

    func cycleRepeat() {
        repeatMode = RepeatMode(rawValue: (repeatMode.rawValue + 1) % 3) ?? .off
    }

    private func shuffled(_ tracks: [Track], keeping idx: Int) -> [Track] {
        guard tracks.indices.contains(idx) else { return tracks.shuffled() }
        let head = tracks[idx]
        var rest = tracks
        rest.remove(at: idx)
        return [head] + rest.shuffled()
    }

    private func handleItemEnded() {
        tracker.flush(track: current)
        next()
    }

    // MARK: now playing + remote

    private func addPeriodicObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.position = time.seconds.isFinite ? time.seconds : 0
            if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                self.duration = d
            }
        }
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.play(); self?.isPlaying = true; self?.updateNowPlaying() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.player.pause(); self?.isPlaying = false; self?.updateNowPlaying() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.toggle() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.previous() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Fetch artwork asynchronously.
        if let url = URL(string: track.coverURL) {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = UIImage(data: data) {
                    let art = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    var updated = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                    updated[MPMediaItemPropertyArtwork] = art
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = updated
                }
            }
        }
    }
}

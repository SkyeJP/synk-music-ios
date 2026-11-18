import Foundation

/// Controls go to this phone's player, or to the active Connect device when
/// another device is playing (Android's PlayerViewModel).
@MainActor
enum Playback {
    static var player: PlayerController { .shared }
    static var cdc: CdcClient { .shared }

    private static var remote: RemotePlaybackState? {
        guard cdc.isRemote, let r = cdc.remoteState, r.currentTrack != nil else { return nil }
        return r
    }

    /// What to show: the remote device's state while it is playing, else ours.
    static func state() -> PlayerSnapshot {
        if let r = remote, let cur = r.currentTrack {
            return PlayerSnapshot(current: cur, queue: r.queue.isEmpty ? [cur] : r.queue, index: r.index,
                                  isPlaying: r.isPlaying, positionMs: r.position(), durationMs: r.durationMs,
                                  loading: false, shuffle: r.shuffle, repeatMode: RepeatMode(name: r.repeatMode),
                                  volume: r.volume, quality: "")
        }
        return player.snapshot()
    }

    static var isRemote: Bool { remote != nil || cdc.isRemote }

    static func positionMs() -> (Int, Int) {
        if let r = remote { return (r.position(), r.durationMs) }
        return (PlayerClock.shared.positionMs, PlayerClock.shared.durationMs)
    }

    static func play(_ t: Track, in list: [Track]) {
        if cdc.isRemote {
            let q = list.isEmpty ? [t] : list
            cdc.send("playQueue", ["tracks": q, "startIndex": q.firstIndex { $0.hash == t.hash } ?? 0])
        } else {
            player.playNow(t, in: list)
        }
    }

    static func toggle() {
        if cdc.isRemote {
            switch cdc.remoteState?.isPlaying {
            case .some(true): cdc.send("pause")
            case .some(false): cdc.send("play")
            case .none: cdc.send("toggle")
            }
        } else {
            player.toggle()
        }
    }

    static func next() { cdc.isRemote ? cdc.send("next") : player.next() }
    static func prev() { cdc.isRemote ? cdc.send("prev") : player.prev() }
    static func seek(_ ms: Int) { cdc.isRemote ? cdc.seekRemote(ms) : player.seek(ms: ms) }
    static func playIndex(_ i: Int) { cdc.isRemote ? cdc.send("playIndex", ["index": i]) : player.playIndex(i) }
    static func toggleShuffle() { cdc.isRemote ? cdc.send("toggleShuffle") : player.toggleShuffle() }
    static func cycleRepeat() { cdc.isRemote ? cdc.send("cycleRepeat") : player.cycleRepeat() }
    static func setVolume(_ v: Float) { player.setVolume(v) }
}

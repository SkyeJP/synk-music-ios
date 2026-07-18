import Foundation

// Records plays for recents / analytics / Last.fm scrobbling. Mirrors the
// Android ListenTracker: on track change -> flush + POST recent; on play/pause
// accumulate listened time; flush logs to analytics when >= 3s listened.
@MainActor
final class ListenTracker {
    private var currentTrack: Track?
    private var accumulatedMs: Int = 0
    private var lastResumeAt: Date?
    private var loggedFor: String?

    func onTrackChanged(_ track: Track) {
        flush(track: currentTrack)
        currentTrack = track
        accumulatedMs = 0
        lastResumeAt = Date()
        loggedFor = nil

        let body = RecentBody(id: track.hash, isrc: track.isrc, name: track.displayTitle,
                              artist: track.artist, album: track.album,
                              cover: track.coverURL, durationMs: track.durationMs)
        Task { try? await API.shared.recordRecent(body) }
    }

    func onPlayingChanged(_ playing: Bool, track: Track?) {
        if playing {
            lastResumeAt = Date()
        } else {
            accumulate()
            if let track = track {
                Task { try? await API.shared.clearNowPlaying(NowPlayingClearBody(name: track.displayTitle, artist: track.artist)) }
            }
        }
    }

    func flush(track: Track?) {
        accumulate()
        guard let track = track, accumulatedMs >= 3000, loggedFor != track.hash else { return }
        loggedFor = track.hash

        let now = Int(Date().timeIntervalSince1970)
        let log = TrackLogBody(trackhash: track.hash, duration: accumulatedMs / 1000, timestamp: now)
        let analytics = AnalyticsBody(trackIsrc: track.isrc ?? "", trackName: track.displayTitle,
                                      artist: track.artist, album: track.album,
                                      listenedMs: accumulatedMs, totalDurationMs: track.durationMs)
        Task {
            try? await API.shared.logTrack(log)
            try? await API.shared.logAnalytics(analytics)
        }
    }

    private func accumulate() {
        guard let start = lastResumeAt else { return }
        accumulatedMs += Int(Date().timeIntervalSince(start) * 1000)
        lastResumeAt = nil
    }
}

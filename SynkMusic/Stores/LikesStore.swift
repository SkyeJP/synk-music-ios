import Foundation
import SwiftUI

// Optimistic like toggle reconciled with the server, keyed by isrc || hash —
// mirrors the Android LikesStore.
@MainActor
final class LikesStore: ObservableObject {
    static let shared = LikesStore()

    @Published private(set) var liked: Set<String> = []

    func key(_ t: Track) -> String { (t.isrc?.isEmpty == false ? t.isrc! : t.hash).lowercased() }

    func isLiked(_ t: Track) -> Bool { liked.contains(key(t)) }

    func refresh() {
        Task {
            guard let resp = try? await API.shared.liked() else { return }
            liked = Set(resp.tracks.map { key($0) })
        }
    }

    func toggle(_ t: Track) {
        let k = key(t)
        let wasLiked = liked.contains(k)
        if wasLiked { liked.remove(k) } else { liked.insert(k) }
        Task {
            let body = LikeBody(isrc: t.isrc, name: t.displayTitle, artist: t.artist,
                                album: t.album, cover: t.coverURL, durationMs: t.durationMs)
            do {
                let result = try await API.shared.toggleLiked(body)
                if result.liked { liked.insert(k) } else { liked.remove(k) }
            } catch {
                // Revert on failure.
                if wasLiked { liked.insert(k) } else { liked.remove(k) }
            }
        }
    }
}

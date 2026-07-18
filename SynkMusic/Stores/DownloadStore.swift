import Foundation
import SwiftUI
import CryptoKit

struct DownloadEntry: Codable, Hashable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var coverUrl: String
    var durationMs: Int
    var path: String
}

// Downloads tracks for offline playback: fetches the stream URL, saves the file
// to app storage, keeps a JSON manifest. Mirrors the Android DownloadStore.
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()

    @Published private(set) var entries: [String: DownloadEntry] = [:]
    @Published private(set) var downloading: Set<String> = []

    private let dir: URL
    private let manifest: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        manifest = dir.appendingPathComponent("manifest.json")
        load()
    }

    func key(_ t: Track) -> String {
        let raw = (t.artist + "\u{1}" + t.displayTitle).lowercased()
        let digest = Insecure.MD5.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func isDownloaded(_ t: Track) -> Bool {
        guard let e = entries[key(t)] else { return false }
        return FileManager.default.fileExists(atPath: e.path)
    }

    func localURL(_ t: Track) -> URL? {
        guard let e = entries[key(t)], FileManager.default.fileExists(atPath: e.path) else { return nil }
        return URL(fileURLWithPath: e.path)
    }

    var downloadedTracks: [Track] {
        entries.values.map {
            var t = Track()
            t.id = $0.id; t.title = $0.title; t.artist = $0.artist
            t.album = $0.album; t.image = $0.coverUrl; t.durationMs = $0.durationMs
            return t
        }
    }

    func toggle(_ t: Track, quality: String) {
        if isDownloaded(t) { remove(t) } else { download(t, quality: quality) }
    }

    func download(_ t: Track, quality: String) {
        let k = key(t)
        if isDownloaded(t) || downloading.contains(k) { return }
        downloading.insert(k)
        Task {
            let ok = await doDownload(t, key: k, quality: quality)
            downloading.remove(k)
            if ok { load() }
        }
    }

    func remove(_ t: Track) {
        let k = key(t)
        if let e = entries[k] { try? FileManager.default.removeItem(atPath: e.path) }
        entries.removeValue(forKey: k)
        writeManifest()
    }

    private func doDownload(_ t: Track, key: String, quality: String) async -> Bool {
        do {
            let body = StreamTokenRequest(id: t.hash, artist: t.artist, title: t.displayTitle,
                                          isrc: t.isrc, quality: quality == "default" ? nil : quality,
                                          durationMs: t.durationMs > 0 ? t.durationMs : nil)
            let token = try await API.shared.streamToken(body)
            guard let url = URL(string: token.url, relativeTo: API.shared.base) else { return false }
            let (data, _) = try await URLSession.shared.data(from: url)
            let dest = dir.appendingPathComponent("\(key).mp3")
            try data.write(to: dest)
            var next = entries
            next[key] = DownloadEntry(id: t.hash, title: t.displayTitle, artist: t.artist,
                                      album: t.album, coverUrl: t.coverURL,
                                      durationMs: t.durationMs, path: dest.path)
            entries = next
            writeManifest()
            return true
        } catch {
            return false
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifest),
              let list = try? JSONDecoder().decode([DownloadEntry].self, from: data) else { return }
        entries = Dictionary(uniqueKeysWithValues: list.compactMap { e -> (String, DownloadEntry)? in
            // Re-key from stored track data so keys stay consistent.
            var t = Track(); t.title = e.title; t.artist = e.artist
            return (key(t), e)
        })
    }

    private func writeManifest() {
        guard let data = try? JSONEncoder().encode(Array(entries.values)) else { return }
        try? data.write(to: manifest)
    }
}

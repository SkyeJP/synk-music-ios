import Foundation
import CryptoKit

/// Liked songs keyed by ISRC (or hash), updated optimistically like Android's LikesStore.
@MainActor
final class LikesStore: ObservableObject {
    static let shared = LikesStore()
    @Published private(set) var liked: Set<String> = []

    func key(_ t: Track) -> String {
        if let i = t.isrc?.trimmingCharacters(in: .whitespaces), !i.isEmpty { return i }
        return t.hash.isEmpty ? "\(t.artist)::\(t.displayTitle)".lowercased() : t.hash
    }

    func isLiked(_ t: Track) -> Bool { liked.contains(key(t)) }

    func refresh() {
        Task {
            guard let tracks = try? await API.shared.liked() else { return }
            liked = Set(tracks.map { key($0) })
        }
    }

    func toggle(_ t: Track) {
        let k = key(t)
        let was = liked.contains(k)
        if was { liked.remove(k) } else { liked.insert(k) }
        let hash = t.hash.isEmpty ? (t.isrc ?? "") : t.hash
        Task {
            var ok = false
            if !hash.isEmpty { ok = (try? await API.shared.setLiked(hash, !was)) != nil }
            if !ok { if was { liked.insert(k) } else { liked.remove(k) } }
        }
    }
}

struct DownloadEntry: Codable, Hashable {
    var key: String
    var file: String
    var id: String
    var title: String
    var artist: String
    var album = ""
    var coverUrl = ""
    var durationMs = 0
}

/// Songs saved for offline play in Application Support/downloads, with a JSON manifest.
@MainActor
final class DownloadStore: ObservableObject {
    static let shared = DownloadStore()
    @Published private(set) var entries: [String: DownloadEntry] = [:] {
        didSet { byId = Dictionary(entries.values.map { ($0.id, $0.key) }, uniquingKeysWith: { a, _ in a }) }
    }
    private var byId: [String: String] = [:]
    @Published private(set) var downloading: Set<String> = []
    /// 0 to 1 for songs being fetched right now; queued songs are in `downloading` only.
    @Published private(set) var progress: [String: Double] = [:]
    private var running: [String: Task<Void, Never>] = [:]

    nonisolated static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        var u = d
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
        return d
    }()
    private var manifest: URL { DownloadStore.dir.appendingPathComponent("manifest.json") }

    private init() { load() }

    nonisolated static func key(_ t: Track) -> String {
        let base = (t.artist + "\u{1}" + t.displayTitle).lowercased()
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func key(_ t: Track) -> String { DownloadStore.key(t) }

    func isDownloaded(_ t: Track) -> Bool { localURL(t) != nil }

    func localURL(_ t: Track) -> URL? {
        guard let e = entries[key(t)] ?? byId[t.hash].flatMap({ entries[$0] }) else { return nil }
        let u = DownloadStore.dir.appendingPathComponent(e.file)
        return FileManager.default.fileExists(atPath: u.path) ? u : nil
    }

    var tracks: [Track] {
        entries.values.sorted { $0.title.lowercased() < $1.title.lowercased() }.map {
            Track(id: $0.id, trackhash: $0.id, title: $0.title, artist: $0.artist, album: $0.album,
                  image: $0.coverUrl, duration: $0.durationMs / 1000, durationMs: $0.durationMs)
        }
    }

    func toggle(_ t: Track) { isDownloaded(t) ? remove(t) : download(t) }

    private var pending: [Track] = []
    private var active = 0

    /// Downloads queue and run two at a time; a whole playlist at once overwhelms the server.
    func download(_ t: Track) {
        let k = key(t)
        if isDownloaded(t) || downloading.contains(k) { return }
        downloading.insert(k)
        pending.append(t)
        pump()
    }

    private func pump() {
        while active < 2, !pending.isEmpty {
            let t = pending.removeFirst()
            let k = key(t)
            active += 1
            progress[k] = 0
            running[k] = Task {
                await run(t)
                running[k] = nil
                progress[k] = nil
                active -= 1
                pump()
            }
        }
    }

    /// Stops queued and running downloads of these songs.
    func cancel(_ tracks: [Track]) {
        let keys = Set(tracks.map { key($0) })
        pending.removeAll { keys.contains(key($0)) }
        for k in keys {
            running[k]?.cancel()
            downloading.remove(k)
            progress[k] = nil
        }
    }

    /// How far a set of songs is: 0 to 1 counting downloaded songs and partial ones.
    func fraction(_ tracks: [Track]) -> Double {
        guard !tracks.isEmpty else { return 0 }
        let done = tracks.reduce(0.0) { sum, t in
            let k = key(t)
            if localURL(t) != nil { return sum + 1 }
            return sum + (progress[k] ?? 0)
        }
        return done / Double(tracks.count)
    }

    private func setProgress(_ k: String, _ v: Double) {
        if downloading.contains(k) { progress[k] = v }
    }

    private func run(_ t: Track) async {
        let k = key(t)
        let quality = SettingsStore.shared.requestQuality
        var entry: DownloadEntry?
        for attempt in 0..<2 where entry == nil && !Task.isCancelled {
            if attempt > 0 { try? await Task.sleep(nanoseconds: 3_000_000_000) }
            do {
                entry = try await DownloadStore.fetch(t, key: k, quality: quality, report: attempt > 0) { [weak self] v in
                    Task { @MainActor in self?.setProgress(k, v) }
                }
            } catch {
                if attempt > 0 && !Task.isCancelled { DebugLog.shared.add("download \(t.displayTitle): \(error.localizedDescription)") }
            }
        }
        downloading.remove(k)
        if let entry {
            DebugLog.shared.add("downloaded \(t.displayTitle)", issue: false)
            entries[k] = entry
            save()
            ImageCache.warm([entry.coverUrl, Covers.large(entry.coverUrl)])
        }
    }

    func remove(_ t: Track) {
        let k = key(t)
        if let e = entries[k] { try? FileManager.default.removeItem(at: DownloadStore.dir.appendingPathComponent(e.file)) }
        entries.removeValue(forKey: k)
        save()
    }

    nonisolated private static func fetch(_ t: Track, key: String, quality: String?, report: Bool,
                                          onProgress: @escaping @Sendable (Double) -> Void) async throws -> DownloadEntry? {
        var url = try? await API.shared.streamURL(t, quality: quality)
        if url == nil, quality != nil { url = try await API.shared.streamURL(t, quality: nil) }
        guard let url else {
            if report { DebugLog.log("download \(t.displayTitle): no stream url") }
            return nil
        }
        var req = URLRequest(url: url)
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        let (tmp, resp) = try await URLSession.shared.download(for: req, delegate: ProgressDelegate(onProgress))
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = (try? String(contentsOf: tmp, encoding: .utf8)).map { " " + String($0.prefix(200)) } ?? ""
            try? FileManager.default.removeItem(at: tmp)
            if report { DebugLog.log("download \(t.displayTitle) (\(quality ?? "default")): HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)\(text)") }
            return nil
        }
        let ext = AudioFile.ext(contentType: http.value(forHTTPHeaderField: "Content-Type"), url: url)
        let name = "\(key).\(ext)"
        let dest = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        let size = (try? dest.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size == 0 { try? FileManager.default.removeItem(at: dest); return nil }
        return DownloadEntry(key: key, file: name, id: t.hash, title: t.displayTitle, artist: t.artist,
                             album: t.album, coverUrl: t.coverUrl, durationMs: t.durationMillis)
    }

    private func load() {
        guard let d = try? Data(contentsOf: manifest), let list = try? JSONDecoder().decode([DownloadEntry].self, from: d) else { return }
        var m: [String: DownloadEntry] = [:]
        for e in list where FileManager.default.fileExists(atPath: DownloadStore.dir.appendingPathComponent(e.file).path) { m[e.key] = e }
        entries = m
    }

    private func save() {
        if let d = try? JSONEncoder().encode(Array(entries.values)) { try? d.write(to: manifest, options: .atomic) }
    }
}

/// Reports a download task's progress as it goes.
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?

    init(_ onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        let report = onProgress
        observation = task.progress.observe(\.fractionCompleted, options: [.new]) { p, _ in report(p.fractionCompleted) }
    }
}

enum AudioFile {
    static func ext(contentType: String?, url: URL) -> String {
        let t = (contentType ?? "").lowercased()
        if t.contains("flac") { return "flac" }
        if t.contains("mp4") || t.contains("aac") || t.contains("m4a") { return "m4a" }
        if t.contains("ogg") || t.contains("opus") { return "ogg" }
        if t.contains("wav") { return "wav" }
        if t.contains("mpeg") || t.contains("mp3") { return "mp3" }
        let e = url.pathExtension.lowercased()
        return ["flac", "m4a", "mp3", "wav", "aac", "mp4"].contains(e) ? e : "mp3"
    }
}

import Foundation
import CryptoKit

/// Whole songs cached on disk (Caches/audio), least recently used first out past 1 GB.
enum AudioCache {
    static let maxBytes: Int64 = 1024 * 1024 * 1024

    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("audio", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    static func stem(_ hash: String, quality: String?) -> String {
        let h = SHA256.hash(data: Data(hash.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "\(h)_\(quality ?? "default")"
    }

    static func file(_ hash: String, quality: String?) -> URL? {
        let s = stem(hash, quality: quality) + "."
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
              let name = names.first(where: { $0.hasPrefix(s) && !$0.hasSuffix(".part") }) else { return nil }
        let u = dir.appendingPathComponent(name)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: u.path)
        return u
    }

    static func remove(_ hash: String) {
        let h = stem(hash, quality: nil).components(separatedBy: "_")[0]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for n in names where n.hasPrefix(h) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
    }

    static func trim() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys) else { return }
        var items = files.compactMap { u -> (URL, Int64, Date)? in
            guard let v = try? u.resourceValues(forKeys: Set(keys)) else { return nil }
            return (u, Int64(v.fileSize ?? 0), v.contentModificationDate ?? .distantPast)
        }
        var total = items.reduce(0) { $0 + $1.1 }
        items.sort { $0.2 < $1.2 }
        for (u, size, _) in items where total > maxBytes {
            try? FileManager.default.removeItem(at: u)
            total -= size
        }
    }
}

/// Keeps the next few songs in the queue fully cached, one at a time in play
/// order, so skipping starts from disk. Songs that leave the window are cancelled.
@MainActor
final class Prefetcher {
    static let ahead = 4
    private var jobs: [String: Task<Void, Never>] = [:]
    private var queue: [Track] = []
    private var running: String?

    func update(window: [Track]) {
        ImageCache.warm(window.flatMap { [$0.coverUrl, Covers.large($0.coverUrl)] })
        let quality = SettingsStore.shared.requestQuality
        let want = window.filter { !DownloadStore.shared.isDownloaded($0) && AudioCache.file($0.hash, quality: quality) == nil }
        let wanted = Set(want.map { $0.hash })
        for (h, job) in jobs where !wanted.contains(h) { job.cancel(); jobs.removeValue(forKey: h) }
        if let r = running, !wanted.contains(r) { running = nil }
        queue = want
        pump()
    }

    private func pump() {
        guard running == nil, let t = queue.first(where: { jobs[$0.hash] == nil }) else { return }
        let hash = t.hash
        running = hash
        let quality = SettingsStore.shared.requestQuality
        jobs[hash] = Task { [weak self] in
            await Prefetcher.fetch(t, quality: quality)
            guard let self else { return }
            self.jobs.removeValue(forKey: hash)
            self.queue.removeAll { $0.hash == hash }
            if self.running == hash { self.running = nil }
            self.pump()
        }
    }

    nonisolated private static func fetch(_ t: Track, quality: String?) async {
        guard !Task.isCancelled,
              let url = (try? await API.shared.streamURL(t, quality: quality)) ?? nil,
              !Task.isCancelled else { return }
        var req = URLRequest(url: url)
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        let res: (URL, URLResponse)
        do { res = try await URLSession.shared.download(for: req) } catch {
            if !Task.isCancelled { DebugLog.log("cache \(t.displayTitle): \(error.localizedDescription)") }
            return
        }
        guard let http = res.1 as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (res.1 as? HTTPURLResponse)?.statusCode ?? 0
            let text = (try? String(contentsOf: res.0, encoding: .utf8)).map { " " + String($0.prefix(200)) } ?? ""
            try? FileManager.default.removeItem(at: res.0)
            if !Task.isCancelled { DebugLog.log("cache \(t.displayTitle): HTTP \(code)\(text)") }
            return
        }
        let tmp = res.0
        if Task.isCancelled { try? FileManager.default.removeItem(at: tmp); return }
        let ext = AudioFile.ext(contentType: http.value(forHTTPHeaderField: "Content-Type"), url: url)
        let dest = AudioCache.dir.appendingPathComponent(AudioCache.stem(t.hash, quality: quality) + "." + ext)
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.moveItem(at: tmp, to: dest)
        AudioCache.trim()
    }
}

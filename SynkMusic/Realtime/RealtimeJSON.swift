import Foundation

typealias JSON = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? {
        switch self[k] {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        default: return nil
        }
    }
    func bool(_ k: String) -> Bool? {
        switch self[k] {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String: return s == "true" ? true : s == "false" ? false : nil
        default: return nil
        }
    }
    func double(_ k: String) -> Double? {
        switch self[k] {
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }
    func int(_ k: String) -> Int? { double(k).flatMap { $0.isFinite ? Int($0) : nil } }
}

enum RealtimeJSON {
    static func parse(_ text: String) -> JSON? {
        guard let d = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? JSON
    }

    static func string(_ obj: Any) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: obj) else { return "{}" }
        return String(data: d, encoding: .utf8) ?? "{}"
    }

    /// A track as the web and desktop clients expect it.
    static func track(_ t: Track) -> JSON {
        var o: JSON = [:]
        if let d = try? JSONEncoder().encode(t), let base = (try? JSONSerialization.jsonObject(with: d)) as? JSON { o = base }
        o["id"] = t.id.isEmpty ? t.hash : t.id
        o["trackhash"] = t.hash
        o["title"] = t.displayTitle
        o["name"] = t.displayTitle
        if !t.coverUrl.isEmpty { o["coverUrl"] = t.coverUrl }
        if t.durationMillis > 0 { o["durationMs"] = t.durationMillis }
        return o
    }

    /// A track from another client, tolerating the shapes they send.
    static func parseTrack(_ any: Any?) -> Track? {
        guard let obj = any as? JSON else { return nil }
        var o = obj
        if let a = obj["artist"] as? JSON { o["artist"] = a.str("name") ?? "" }
        if let a = obj["album"] as? JSON { o["album"] = a.str("title") ?? a.str("name") ?? "" }
        for k in ["image", "cover"] where obj[k] != nil && !(obj[k] is String) { o.removeValue(forKey: k) }
        guard let d = try? JSONSerialization.data(withJSONObject: o), var t = try? JSONDecoder().decode(Track.self, from: d) else { return nil }
        if t.image.isEmpty && (t.cover ?? "").isEmpty, let alt = o.str("coverUrl") ?? o.str("artwork") ?? o.str("thumb") { t.image = alt }
        if t.hash.isEmpty && t.displayTitle.isEmpty { return nil }
        return t
    }

    static func tracks(_ any: Any?) -> [Track] { (any as? [Any])?.compactMap { parseTrack($0) } ?? [] }

    /// Seconds first: the web only publishes seconds, and the server merges states,
    /// so a ms field can be left over from an older publish by another client.
    static func positionMs(_ o: JSON, _ msKey: String, _ secondsKey: String) -> Int {
        if let s = o.double(secondsKey) { return max(0, Int(s * 1000)) }
        if let ms = o.double(msKey) { return max(0, Int(ms)) }
        return 0
    }

    /// The part of a long queue that gets sent: 200 songs around the current one,
    /// as the web does. Incoming indices are relative to its start.
    static func window(count: Int, index: Int) -> Range<Int> {
        let start = max(0, min(index - 20, count - 200))
        return start..<min(count, start + 200)
    }

    /// How far a playing state has moved on since the server stamped it, at most 5 s.
    static func lagMs(_ o: JSON) -> Int {
        guard o.bool("isPlaying") == true, let ts = o.double("timestamp") else { return 0 }
        return min(5000, max(0, Int(Date().timeIntervalSince1970 * 1000 - ts)))
    }
}

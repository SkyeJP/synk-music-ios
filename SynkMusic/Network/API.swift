import Foundation

struct APIError: Error, LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

extension Notification.Name {
    static let synkSessionExpired = Notification.Name("synkSessionExpired")
}

/// REST client for https://synkmusic.co.uk/api/, the same base and routes as the Android app.
final class API {
    static let shared = API()
    static let site = "https://synkmusic.co.uk"
    static let base = URL(string: "https://synkmusic.co.uk/api/")!

    static var userAgent: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "4.0.0"
        return "SYNK Music iOS/\(v)"
    }

    let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 25
        return URLSession(configuration: cfg)
    }()

    private static let sessionPaths = ["auth/me", "library/", "playlists", "stream/token", "sync/", "analytics/"]

    func request(_ path: String, method: String = "GET", query: [String: String?] = [:], body: Any? = nil) -> URLRequest {
        var comps = URLComponents(url: API.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { k, v in v.map { URLQueryItem(name: k, value: $0) } }
        if !items.isEmpty { comps.queryItems = items }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(API.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let t = AuthStore.shared.token, !t.isEmpty { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let enc = body as? Encodable {
                req.httpBody = try? JSONEncoder().encode(AnyEncodable(enc))
            } else {
                req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
        }
        return req
    }

    @discardableResult
    func data(_ req: URLRequest) async throws -> Data {
        let sentToken = AuthStore.shared.token
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, let sentToken, !sentToken.isEmpty, isSessionBound(req.url?.path ?? "") {
            if AuthStore.shared.token == sentToken {
                AuthStore.shared.token = nil
                await MainActor.run { NotificationCenter.default.post(name: .synkSessionExpired, object: nil) }
            }
        }
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(status: status, message: msg ?? API.friendly(status))
        }
        return data
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String?] = [:]) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(request(path, query: query)))
    }

    func send<T: Decodable>(_ path: String, method: String = "POST", body: Any? = [String: String]()) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(request(path, method: method, body: body)))
    }

    /// The array under `key` in a JSON object response.
    func list<T: Decodable>(_ path: String, _ query: [String: String?] = [:], key: String) async throws -> [T] {
        let d = try await data(request(path, query: query))
        return try JSONDecoder().decode(Keyed<T>.self, from: d).items(key)
    }

    func sendVoid(_ path: String, method: String = "POST", body: Any? = [String: String]()) async throws {
        try await data(request(path, method: method, body: body))
    }

    func json(_ path: String, _ query: [String: String?] = [:]) async throws -> [String: Any] {
        let d = try await data(request(path, query: query))
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
    }

    private func isSessionBound(_ path: String) -> Bool {
        let p = path.hasPrefix("/api/") ? String(path.dropFirst(5)) : path
        return API.sessionPaths.contains { p.hasPrefix($0) } && !p.hasPrefix("auth/login") &&
            !p.hasPrefix("auth/register") && !p.hasPrefix("auth/verify") && !p.hasPrefix("auth/tv")
    }

    static func friendly(_ status: Int) -> String {
        switch status {
        case 401: return "Invalid email or password"
        case 403: return "Please verify your email first"
        case 409: return "Already in use"
        case 502, 503: return "Server is temporarily unavailable"
        case 0: return "Couldn't reach SYNK"
        default: return "Something went wrong (\(status))"
        }
    }

    static func absoluteStreamURL(_ raw: String) -> URL? {
        if raw.isEmpty { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("/api/") { return URL(string: site + raw) }
        var r = raw
        for p in ["/", "v1/", "api/"] where r.hasPrefix(p) { r.removeFirst(p.count) }
        return URL(string: site + "/api/" + r)
    }
}

private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ v: Encodable) { value = v }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

// MARK: endpoints

struct Keyed<T: Decodable>: Decodable {
    private let c: KeyedDecodingContainer<AnyKey>
    init(from decoder: Decoder) throws { c = try decoder.container(keyedBy: AnyKey.self) }
    func items(_ key: String) -> [T] { c.list(key, T.self) }
}

private struct UserWrap: Decodable {
    var token = ""
    var user: User?
    var userId = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        token = c.str("token"); user = c.obj("user", User.self); userId = c.str("userId")
    }
}

extension API {
    // Auth
    func login(_ email: String, _ password: String) async throws -> (String, User?) {
        let r: UserWrap = try await send("auth/login", body: ["email": email, "password": password])
        return (r.token, r.user)
    }
    func register(_ email: String, _ username: String, _ password: String, invite: String?) async throws {
        var b = ["email": email, "username": username, "password": password]
        if let invite, !invite.isEmpty { b["inviteCode"] = invite }
        let _: UserWrap = try await send("auth/register", body: b)
    }
    func verify(_ email: String, _ code: String) async throws -> (String, User?) {
        let r: UserWrap = try await send("auth/verify", body: ["email": email, "code": code])
        return (r.token, r.user)
    }
    func me() async throws -> User? { let r: UserWrap = try await get("auth/me"); return r.user }
    func logout() async { try? await sendVoid("auth/logout") }
    func profile(_ username: String) async throws -> ProfileResponse {
        try await get("profile/\(username)")
    }

    // Library
    func home() async throws -> [HomeSection] { try await list("library/home", ["limit": "14"], key: "sections") }
    func liked() async throws -> [Track] {
        try await list("library/liked", ["track_limit": "50", "album_limit": "10", "artist_limit": "10"], key: "tracks")
    }
    func recent() async throws -> [Track] { try await list("library/recent", key: "tracks") }
    func likeItem(type: String, hash: String) async throws {
        try await sendVoid("library/liked/add", body: ["type": type, "hash": hash])
    }
    func setLiked(_ hash: String, _ liked: Bool) async throws {
        try await sendVoid(liked ? "library/liked/add" : "library/liked/remove", body: ["type": "track", "hash": hash])
    }

    // Catalog
    func search(_ q: String) async -> SearchResponse {
        async let t: Flexible<Track>? = try? get("search", ["q": q, "type": "tracks", "limit": "20"])
        async let ar: Flexible<Artist>? = try? get("search", ["q": q, "type": "artists"])
        async let al: Flexible<Album>? = try? get("search", ["q": q, "type": "albums"])
        return SearchResponse(tracks: await t?.items ?? [], albums: await al?.items ?? [], artists: await ar?.items ?? [])
    }
    func trending() async throws -> [Track] { let r: Flexible<Track> = try await get("trending"); return r.items }
    func artistRadio(_ name: String) async throws -> [Track] {
        let r: Flexible<Track> = try await get("artists/radio", ["artist": name]); return r.items
    }
    func albumInfo(_ hash: String) async throws -> Album { try await get("albums/info", ["id": hash]) }
    func albumTracks(_ hash: String) async throws -> [Track] { try await list("albums/tracks", ["id": hash], key: "tracks") }
    func artistInfo(_ hash: String) async throws -> Artist { try await get("artists/info/\(hash)") }
    func artistTracks(_ hash: String) async throws -> [Track] {
        try await list("artists/info/\(hash)/tracks", ["limit": "10"], key: "tracks")
    }
    func artistAlbums(_ hash: String) async throws -> [Album] {
        try await list("artists/info/\(hash)/albums", ["limit": "25"], key: "albums")
    }

    // Playlists
    func playlists() async throws -> [Playlist] { let k: Keyed<Playlist> = try await get("playlists"); let d = k.items("data"); return d.isEmpty ? k.items("playlists") : d }
    func playlist(_ id: String) async throws -> (Playlist, [Track]) {
        let obj = try await data(request("playlists/\(id)", query: ["limit": "-1"]))
        struct D: Decodable {
            var info = Playlist(); var tracks: [Track] = []
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                info = c.obj("info", Playlist.self) ?? Playlist(); tracks = c.list("tracks", Track.self)
            }
        }
        let d = try JSONDecoder().decode(D.self, from: obj)
        return (d.info, d.tracks)
    }
    /// Creates a playlist and returns its id.
    func createPlaylist(_ name: String) async throws -> String {
        let d = try await data(request("playlists", method: "POST", body: ["name": name, "description": "", "isPublic": false] as [String: Any]))
        let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] ?? [:]
        let pl = o["playlist"] as? [String: Any] ?? o
        return (pl["id"] as? String) ?? (pl["_id"] as? String) ?? ""
    }
    func deletePlaylist(_ id: String) async throws { try await sendVoid("playlists/\(id)", method: "DELETE", body: nil) }
    func addToPlaylist(_ id: String, hashes: [String]) async throws {
        try await sendVoid("playlists/\(id)/add", body: ["itemhash": hashes.joined(separator: ",")])
    }
    func removeFromPlaylist(_ id: String, hash: String) async throws {
        try await sendVoid("playlists/\(id)/remove", body: ["itemhash": hash])
    }

    // Lyrics and streaming
    func lyrics(_ t: Track) async throws -> Lyrics {
        let d = t.durationSeconds
        return try await get("lyrics", [
            "artist": t.artist, "title": t.displayTitle,
            "duration": d > 0 ? String(d) : nil,
            "isrc": (t.isrc ?? "").isEmpty ? nil : t.isrc,
        ])
    }
    func streamURL(_ t: Track, quality: String?) async throws -> URL? {
        let d = try await data(request("stream/token", method: "POST", body: StreamTokenRequest(t, quality: quality)))
        let url = (try JSONSerialization.jsonObject(with: d) as? [String: Any])?["url"] as? String ?? ""
        return API.absoluteStreamURL(url)
    }

    // Analytics
    func detailedStats(_ period: String) async throws -> DetailedStats { try await get("analytics/stats/detailed", ["period": period]) }
    func topArtists(_ period: String) async throws -> [TopArtistItem] {
        try await list("analytics/top-artists", ["duration": period, "limit": "10"], key: "artists")
    }
    func achievements() async throws -> [Achievement] { try await list("analytics/achievements", key: "achievements") }

    // Listening
    func recordRecent(_ t: Track) async {
        try? await sendVoid("library/recent", body: [
            "id": t.hash, "isrc": t.isrc ?? "", "name": t.displayTitle, "artist": t.artist,
            "album": t.album, "cover": t.coverUrl, "durationMs": t.durationMs,
        ] as [String: Any])
    }
    func logTrack(_ hash: String, seconds: Int) async {
        try? await sendVoid("analytics/track/log", body: [
            "trackhash": hash, "source": "ios", "duration": seconds, "timestamp": Int(Date().timeIntervalSince1970),
        ] as [String: Any])
    }
    func logAnalytics(_ t: Track, isrc: String, listenedMs: Int) async {
        try? await sendVoid("analytics", body: [
            "trackIsrc": isrc, "trackName": t.displayTitle, "artist": t.artist, "album": t.album,
            "listenedMs": listenedMs, "totalDurationMs": t.durationMs,
        ] as [String: Any])
    }
    func clearNowPlaying(_ t: Track) async {
        try? await sendVoid("library/nowplaying/clear", body: ["name": t.displayTitle, "artist": t.artist])
    }

    // Realtime
    func ltCreateParty() async throws -> String {
        let d = try await data(request("listen-together/create", method: "POST", body: [String: String]()))
        return (try JSONSerialization.jsonObject(with: d) as? [String: Any])?["partyId"] as? String ?? ""
    }
    func ltInfo(_ id: String) async throws -> (partyId: String, hostName: String) {
        let o = try await json("listen-together/\(id)")
        return (o["partyId"] as? String ?? "", o["hostName"] as? String ?? "")
    }

    // Device tuning
    func tuningDevices() async throws -> [DeviceTuning] { try await list("tuning/devices", key: "devices") }
    func saveTuning(_ d: DeviceTuning) async throws { try await sendVoid("tuning/devices", method: "PUT", body: d) }
    func deleteTuning(_ key: String) async throws { try await sendVoid("tuning/devices", method: "DELETE", body: ["deviceKey": key]) }
    func tuningSearch(_ q: String) async throws -> [AutoEqResult] { try await list("tuning/search", ["q": q], key: "results") }
    func tuningProfile(_ id: String) async throws -> (Double, [TuneFilter]) {
        struct P: Decodable {
            var preamp = 0.0; var filters: [TuneFilter] = []
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                preamp = c.double("preamp"); filters = c.list("filters", TuneFilter.self)
            }
        }
        let p: P = try await get("tuning/profile", ["id": id])
        return (p.preamp, p.filters)
    }
}

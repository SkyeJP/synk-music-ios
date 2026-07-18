import Foundation

enum APIError: Error {
    case badStatus(Int)
    case decoding(Error)
    case transport(Error)
    case badURL
}

// Thin async/await REST client against the SYNK API. Injects the bearer token
// and SYNK User-Agent on every request, like the Android AuthInterceptor.
final class API {
    static let shared = API()

    let base = URL(string: "https://api.synkmusic.xyz/")!
    private let session = URLSession(configuration: .default)

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()
    private let encoder = JSONEncoder()

    // MARK: request plumbing

    private func makeRequest(_ path: String, method: String = "GET",
                             query: [URLQueryItem] = [], body: Data? = nil) throws -> URLRequest {
        guard var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("SYNK Music iOS/1.0 (blake@synkmusic.xyz)", forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthStore.shared.token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body = body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func run<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let data: Data
        let resp: URLResponse
        do { (data, resp) = try await session.data(for: req) }
        catch { throw APIError.transport(error) }

        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func runVoid(_ req: URLRequest) async throws {
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.badStatus(http.statusCode)
        }
    }

    private func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = [], as type: T.Type) async throws -> T {
        try await run(makeRequest(path, query: query), as: type)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, _ body: B, as type: T.Type) async throws -> T {
        try await run(makeRequest(path, method: "POST", body: try encoder.encode(body)), as: type)
    }

    private func postVoid<B: Encodable>(_ path: String, _ body: B) async throws {
        try await runVoid(makeRequest(path, method: "POST", body: try encoder.encode(body)))
    }

    // MARK: Auth
    func login(_ email: String, _ password: String) async throws -> AuthResponse {
        try await post("v1/auth/login", LoginRequest(email: email, password: password), as: AuthResponse.self)
    }
    func register(_ email: String, _ username: String, _ password: String) async throws -> RegisterResponse {
        try await post("v1/auth/register", RegisterRequest(email: email, username: username, password: password), as: RegisterResponse.self)
    }
    func verify(_ email: String, _ code: String) async throws -> AuthResponse {
        try await post("v1/auth/verify", VerifyRequest(email: email, code: code), as: AuthResponse.self)
    }
    func me() async throws -> MeResponse { try await get("v1/auth/me", as: MeResponse.self) }
    func logout() async throws { try await runVoid(makeRequest("v1/logout")) }

    // MARK: Library / home
    func home(limit: Int = 8) async throws -> HomeResponse {
        try await get("v1/library/home", [.init(name: "limit", value: "\(limit)")], as: HomeResponse.self)
    }
    func liked() async throws -> LikedResponse {
        try await get("v1/library/liked", [
            .init(name: "track_limit", value: "100"),
            .init(name: "album_limit", value: "20"),
            .init(name: "artist_limit", value: "20"),
        ], as: LikedResponse.self)
    }
    func recent() async throws -> TracksWrapper { try await get("v1/library/recent", as: TracksWrapper.self) }

    // MARK: Catalog
    func search(_ q: String, type: String = "tracks", limit: Int = 20) async throws -> SearchResponse {
        try await get("v1/search", [
            .init(name: "q", value: q),
            .init(name: "type", value: type),
            .init(name: "limit", value: "\(limit)"),
        ], as: SearchResponse.self)
    }
    func albumInfo(_ hash: String) async throws -> Album {
        try await get("v1/albums/info", [.init(name: "id", value: hash)], as: Album.self)
    }
    func albumTracks(_ hash: String) async throws -> TracksWrapper {
        try await get("v1/albums/tracks", [.init(name: "id", value: hash)], as: TracksWrapper.self)
    }
    func artistInfo(_ hash: String) async throws -> Artist { try await get("v1/artists/info/\(hash)", as: Artist.self) }
    func artistTracks(_ hash: String) async throws -> TracksWrapper {
        try await get("v1/artists/info/\(hash)/tracks", [.init(name: "limit", value: "20")], as: TracksWrapper.self)
    }
    func artistAlbums(_ hash: String) async throws -> AlbumsWrapper {
        try await get("v1/artists/info/\(hash)/albums", [.init(name: "limit", value: "25")], as: AlbumsWrapper.self)
    }

    // MARK: Playlists
    func playlists() async throws -> PlaylistsResponse { try await get("v1/playlists", as: PlaylistsResponse.self) }
    func playlist(_ id: String) async throws -> PlaylistDetail {
        try await get("v1/playlists/\(id)", [.init(name: "limit", value: "-1")], as: PlaylistDetail.self)
    }
    func addToPlaylist(_ id: String, hashes: [String]) async throws {
        try await postVoid("v1/playlists/\(id)/add", AddToPlaylistBody(itemhash: hashes.joined(separator: ",")))
    }

    // MARK: Lyrics
    func lyrics(artist: String, title: String, duration: Int?, isrc: String?) async throws -> Lyrics {
        var q: [URLQueryItem] = [.init(name: "artist", value: artist), .init(name: "title", value: title)]
        if let duration = duration { q.append(.init(name: "duration", value: "\(duration)")) }
        if let isrc = isrc { q.append(.init(name: "isrc", value: isrc)) }
        return try await get("v1/lyrics", q, as: Lyrics.self)
    }

    // MARK: Stream
    func streamToken(_ body: StreamTokenRequest) async throws -> StreamToken {
        try await post("v1/stream/token", body, as: StreamToken.self)
    }

    // MARK: Likes / tracking
    func toggleLiked(_ body: LikeBody) async throws -> LikeResult {
        try await post("v1/library/liked", body, as: LikeResult.self)
    }
    func recordRecent(_ body: RecentBody) async throws { try await postVoid("v1/library/recent", body) }
    func logTrack(_ body: TrackLogBody) async throws { try await postVoid("v1/analytics/track/log", body) }
    func logAnalytics(_ body: AnalyticsBody) async throws { try await postVoid("v1/analytics", body) }
    func clearNowPlaying(_ body: NowPlayingClearBody) async throws { try await postVoid("v1/library/nowplaying/clear", body) }
}

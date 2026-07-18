import Foundation

// All decodable with lenient defaults so partial payloads never crash decoding.

struct ArtistRef: Codable, Hashable {
    var name = ""
    var artisthash = ""
    var image = ""
}

struct Track: Codable, Hashable, Identifiable {
    var id = ""
    var trackhash = ""
    var type = "track"
    var title = ""
    var name = ""
    var artist = ""
    var artists: [ArtistRef] = []
    var albumartists: [ArtistRef] = []
    var album = ""
    var albumhash = ""
    var image = ""
    var cover: String? = nil
    var isrc: String? = nil
    var duration = 0
    var durationMs = 0
    var explicit = false
    var source: String? = nil

    var displayTitle: String { title.isEmpty ? name : title }
    var hash: String { trackhash.isEmpty ? id : trackhash }
    var coverURL: String { image.isEmpty ? (cover ?? "") : image }
    var durationSeconds: Int { duration > 0 ? duration : durationMs / 1000 }

    enum CodingKeys: String, CodingKey {
        case id, trackhash, type, title, name, artist, artists, albumartists
        case album, albumhash, image, cover, isrc, duration, durationMs, explicit, source
    }
}

struct Album: Codable, Hashable, Identifiable {
    var id = ""
    var albumhash = ""
    var title = ""
    var name = ""
    var artist = ""
    var albumartists: [ArtistRef] = []
    var image = ""
    var genres: [String] = []
    var is_single = false
    var trackcount = 0

    var displayTitle: String { title.isEmpty ? name : title }
    var hash: String { albumhash.isEmpty ? id : albumhash }
}

struct Artist: Codable, Hashable, Identifiable {
    var id = ""
    var artisthash = ""
    var name = ""
    var type = "artist"
    var image = ""
    var trackcount = 0
    var albumcount = 0
    var color = "#717171"
    var genres: [String] = []

    var hash: String { artisthash.isEmpty ? id : artisthash }
}

struct Playlist: Codable, Hashable, Identifiable {
    var id = ""
    var name = ""
    var description = ""
    var isPublic = false
    var image = ""
    var hasCustomImage = false
    var trackCount = 0
    var durationSec = 0
    var coverTracks: [String] = []
    var owner: String? = nil

    var coverURL: String {
        if !image.isEmpty { return image }
        let covers = coverTracks.filter { !$0.isEmpty }.prefix(6)
        if covers.isEmpty { return "" }
        let joined = covers.joined(separator: ",")
        let enc = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? joined
        return "https://api.synkmusic.xyz/v1/covers/playlist?covers=\(enc)"
    }
}

struct UserStats: Codable, Hashable {
    var likedSongs = 0
    var playlists = 0
    var listens = 0
}

struct User: Codable, Hashable {
    var id = ""
    var email = ""
    var username = ""
    var verified = false
    var avatarUrl: String? = nil
    var bannerUrl: String? = nil
    var bio: String? = nil
    var roles: [String] = []
    var onboardingComplete = false
    var stats: UserStats? = nil
}

struct LyricWord: Codable, Hashable {
    var word = ""
    var time = 0
}

struct LyricLine: Codable, Hashable {
    var time = 0
    var text = ""
    var end: Int? = nil
    var words: [LyricWord]? = nil
    var bgWords: [LyricWord]? = nil
    var side: String? = nil
}

struct Lyrics: Codable {
    var lyrics: [LyricLine] = []
    var synced = false
    var richsync = false
    var source = ""
}

struct StreamToken: Codable {
    var url = ""
    var expires: Double = 0
}

// Requests / responses

struct LoginRequest: Codable { let email: String; let password: String }
struct RegisterRequest: Codable { let email: String; let username: String; let password: String }
struct VerifyRequest: Codable { let email: String; let code: String }

struct AuthResponse: Codable { var message = ""; var token = ""; var user: User? = nil }
struct RegisterResponse: Codable { var message = ""; var userId = "" }
struct MeResponse: Codable { var user: User? = nil }

struct StreamTokenRequest: Codable {
    var id: String
    var artist: String?
    var title: String?
    var isrc: String?
    var quality: String?
    var durationMs: Int?
}

// Home is a list of sections whose items are heterogeneous (track or album).
struct HomeSection: Codable {
    var key = ""
    var title = ""
    var items: [AnyItem] = []
    var kind: String { key == "new_releases" ? "album" : "track" }
}

struct HomeResponse: Codable { var sections: [HomeSection] = [] }

// A card can wrap either a track or an album depending on the section.
struct AnyItem: Codable, Hashable {
    var track: Track?
    var album: Album?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let t = try? c.decode(Track.self), !t.hash.isEmpty, t.type != "album" {
            track = t
        }
        if track == nil, let a = try? c.decode(Album.self) {
            album = a
        } else if track == nil, let t = try? c.decode(Track.self) {
            track = t
        }
    }
    func encode(to encoder: Encoder) throws {}
}

struct SearchResponse: Codable {
    var tracks: [Track] = []
    var topResult: Track? = nil
    var results: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []
}

struct PlaylistsResponse: Codable { var data: [Playlist] = [] }
struct PlaylistDetail: Codable { var info = Playlist(); var tracks: [Track] = [] }
struct LikedResponse: Codable {
    var tracks: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []
}
struct TracksWrapper: Codable { var tracks: [Track] = [] }
struct AlbumsWrapper: Codable { var albums: [Album] = [] }

struct LikeBody: Codable {
    var isrc: String?; var name: String?; var artist: String?
    var album: String?; var cover: String?; var durationMs: Int?
}
struct LikeResult: Codable { var liked = false }
struct AddToPlaylistBody: Codable { let itemhash: String }
struct RecentBody: Codable {
    var id: String?; var isrc: String?; var name = ""
    var artist = ""; var album = ""; var cover = ""; var durationMs = 0
}
struct TrackLogBody: Codable {
    let trackhash: String; var source = "ios"; let duration: Int; let timestamp: Int
}
struct AnalyticsBody: Codable {
    let trackIsrc: String; let trackName: String; let artist: String
    var album = ""; let listenedMs: Int; let totalDurationMs: Int
}
struct NowPlayingClearBody: Codable { let name: String; let artist: String }

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var cs = CharacterSet.urlQueryAllowed
        cs.remove(charactersIn: "&+=,")
        return cs
    }()
}

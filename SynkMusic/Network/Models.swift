import Foundation

// Every model decodes leniently: missing keys fall back to defaults and numbers
// may arrive as ints, doubles or strings, like kotlinx's coerceInputValues.

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue); self.intValue = intValue }
}

typealias Lenient = KeyedDecodingContainer<AnyKey>

extension KeyedDecodingContainer where K == AnyKey {
    func str(_ k: String, _ d: String = "") -> String { strOrNil(k) ?? d }
    func strOrNil(_ k: String) -> String? {
        let key = AnyKey(k)
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }
    func int(_ k: String, _ d: Int = 0) -> Int { intOrNil(k) ?? d }
    func intOrNil(_ k: String) -> Int? {
        let key = AnyKey(k)
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }
    func double(_ k: String, _ d: Double = 0) -> Double {
        let key = AnyKey(k)
        if let v = try? decodeIfPresent(Double.self, forKey: key) { return v }
        if let s = try? decodeIfPresent(String.self, forKey: key), let v = Double(s) { return v }
        return d
    }
    func bool(_ k: String, _ d: Bool = false) -> Bool {
        let key = AnyKey(k)
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s == "true" || s == "1" }
        return d
    }
    func list<T: Decodable>(_ k: String, _ t: T.Type) -> [T] {
        guard var arr = try? nestedUnkeyedContainer(forKey: AnyKey(k)) else { return [] }
        var out: [T] = []
        while !arr.isAtEnd {
            if let v = try? arr.decode(T.self) { out.append(v) } else { _ = try? arr.decode(Skip.self) }
        }
        return out
    }
    func obj<T: Decodable>(_ k: String, _ t: T.Type) -> T? { try? decodeIfPresent(T.self, forKey: AnyKey(k)) }
}

struct Skip: Decodable { init(from decoder: Decoder) throws {} }

func encodeURIComponent(_ s: String) -> String {
    var cs = CharacterSet.alphanumerics
    cs.insert(charactersIn: "-_.*")
    return (s.addingPercentEncoding(withAllowedCharacters: cs) ?? s).replacingOccurrences(of: "%20", with: "+")
}

enum Covers {
    static func absolute(_ s: String) -> String {
        if s.hasPrefix("//") { return "https:" + s }
        if s.hasPrefix("/") { return "https://synkmusic.co.uk" + s }
        return s
    }
    static func usable(_ s: String) -> Bool { !s.isEmpty && !s.contains("LEONARD") && !s.contains("generated") }
}

struct ArtistRef: Codable, Hashable {
    var name = ""
    var artisthash = ""
    var image = ""
    init(name: String = "", artisthash: String = "", image: String = "") {
        self.name = name; self.artisthash = artisthash; self.image = image
    }
    init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) { name = s; return }
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str("name"); artisthash = c.str("artisthash"); image = c.str("image")
    }
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
    var trackNumber = 0

    init(id: String = "", trackhash: String = "", title: String = "", name: String = "", artist: String = "",
         album: String = "", albumhash: String = "", image: String = "", cover: String? = nil, isrc: String? = nil,
         duration: Int = 0, durationMs: Int = 0) {
        self.id = id; self.trackhash = trackhash; self.title = title; self.name = name; self.artist = artist
        self.album = album; self.albumhash = albumhash; self.image = image; self.cover = cover; self.isrc = isrc
        self.duration = duration; self.durationMs = durationMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); trackhash = c.str("trackhash"); type = c.str("type", "track")
        title = c.str("title"); name = c.str("name"); artist = c.str("artist")
        artists = c.list("artists", ArtistRef.self); albumartists = c.list("albumartists", ArtistRef.self)
        album = c.str("album"); albumhash = c.str("albumhash"); image = c.str("image")
        cover = c.strOrNil("cover"); isrc = c.strOrNil("isrc")
        duration = c.int("duration"); durationMs = c.int("durationMs"); explicit = c.bool("explicit")
        source = c.strOrNil("source"); trackNumber = c.int("trackNumber")
    }

    var displayTitle: String { title.isEmpty ? name : title }
    var hash: String { trackhash.isEmpty ? id : trackhash }
    var durationSeconds: Int { duration > 0 ? duration : durationMs / 1000 }
    var durationMillis: Int { durationMs > 0 ? durationMs : duration * 1000 }
    var coverUrl: String {
        let src = image.isEmpty ? (cover ?? "") : image
        if Covers.usable(src) { return Covers.absolute(src) }
        if !artist.isEmpty && !displayTitle.isEmpty {
            return "https://synkmusic.co.uk/api/covers/proxy?artist=\(encodeURIComponent(artist))&title=\(encodeURIComponent(displayTitle))"
        }
        return ""
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
    var isSingle = false
    var trackcount = 0
    var date: Int? = nil

    init(albumhash: String = "", title: String = "", artist: String = "", image: String = "") {
        self.albumhash = albumhash; self.title = title; self.artist = artist; self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); albumhash = c.str("albumhash"); title = c.str("title"); name = c.str("name")
        artist = c.str("artist"); albumartists = c.list("albumartists", ArtistRef.self)
        image = c.str("image"); genres = c.list("genres", String.self); isSingle = c.bool("is_single")
        trackcount = c.int("trackcount"); date = c.intOrNil("date") ?? c.intOrNil("year")
        if date == nil, let rd = c.strOrNil("releaseDate"), let y = Int(rd.prefix(4)) { date = y }
        if albumhash.isEmpty && !id.isEmpty { albumhash = id }
        if artist.isEmpty { artist = albumartists.first?.name ?? "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(albumhash, forKey: AnyKey("albumhash")); try c.encode(displayTitle, forKey: AnyKey("title"))
        try c.encode(artist, forKey: AnyKey("artist")); try c.encode(image, forKey: AnyKey("image"))
    }

    var displayTitle: String { title.isEmpty ? name : title }
    var hash: String { albumhash.isEmpty ? id : albumhash }
    var coverUrl: String {
        if Covers.usable(image) { return Covers.absolute(image) }
        if !artist.isEmpty && !displayTitle.isEmpty {
            return "https://synkmusic.co.uk/api/covers/proxy?artist=\(encodeURIComponent(artist))&title=\(encodeURIComponent(displayTitle))"
        }
        return ""
    }
    var year: String {
        guard let d = date, d > 0 else { return "" }
        if (1000...3000).contains(d) { return String(d) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return String(cal.component(.year, from: Date(timeIntervalSince1970: TimeInterval(d))))
    }
}

struct Artist: Codable, Hashable, Identifiable {
    var id = ""
    var artisthash = ""
    var name = ""
    var image = ""
    var genres: [String] = []

    init(artisthash: String = "", name: String = "", image: String = "") {
        self.artisthash = artisthash; self.name = name; self.image = image
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); artisthash = c.str("artisthash"); name = c.str("name")
        image = c.str("image"); genres = c.list("genres", String.self)
        if image.isEmpty { image = c.str("picture") }
        if artisthash.isEmpty && !id.isEmpty { artisthash = id }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(artisthash, forKey: AnyKey("artisthash")); try c.encode(name, forKey: AnyKey("name"))
        try c.encode(image, forKey: AnyKey("image"))
    }

    var hash: String { artisthash.isEmpty ? id : artisthash }
    var coverUrl: String {
        if !image.isEmpty { return Covers.absolute(image) }
        if !name.isEmpty { return "https://synkmusic.co.uk/api/covers/proxy?artist=\(encodeURIComponent(name))" }
        return ""
    }
}

struct Playlist: Decodable, Hashable, Identifiable {
    var id = ""
    var name = ""
    var description = ""
    var image = ""
    var trackCount = 0
    var coverTracks: [String] = []
    var owner: String? = nil
    var ownerId: String? = nil
    var isPublic = false
    var folder: String? = nil
    var pinned = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); name = c.str("name"); description = c.str("description"); image = c.str("image")
        trackCount = c.int("trackCount"); coverTracks = c.list("coverTracks", String.self)
        owner = c.strOrNil("owner"); ownerId = c.strOrNil("ownerId"); isPublic = c.bool("isPublic")
        folder = c.strOrNil("folder").flatMap { $0.isEmpty ? nil : $0 }; pinned = c.bool("pinned")
    }

    var coverUrl: String {
        if !image.isEmpty { return image.hasPrefix("/") ? "https://synkmusic.co.uk" + image : image }
        let covers = coverTracks.filter { !$0.isEmpty }.prefix(6)
        if covers.isEmpty { return "" }
        return "https://synkmusic.co.uk/api/covers/playlist?covers=\(encodeURIComponent(covers.joined(separator: ",")))"
    }
}

struct User: Codable, Hashable {
    var id = ""
    var email = ""
    var username = ""
    var avatarUrl: String? = nil
    var bannerUrl: String? = nil
    var bio: String? = nil
    var roles: [String] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); email = c.str("email"); username = c.str("username")
        avatarUrl = c.strOrNil("avatarUrl"); bannerUrl = c.strOrNil("bannerUrl"); bio = c.strOrNil("bio")
        roles = c.list("roles", String.self)
    }
}

struct LyricWord: Decodable, Hashable {
    var word = ""
    var time = 0
    var end: Int? = nil
    var chars: [[Int]]? = nil

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        word = c.str("word"); time = c.int("time"); end = c.intOrNil("end")
        chars = c.obj("chars", [[Double]].self).map { $0.map { $0.map { Int($0) } } }
    }
}

struct LyricLine: Decodable, Hashable {
    var time = 0
    var text = ""
    var end: Int? = nil
    var words: [LyricWord]? = nil
    var bgWords: [LyricWord]? = nil

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        time = c.int("time"); text = c.str("text"); end = c.intOrNil("end")
        let w = c.list("words", LyricWord.self); words = w.isEmpty ? nil : w
        let b = c.list("bgWords", LyricWord.self); bgWords = b.isEmpty ? nil : b
    }
}

struct Lyrics: Decodable {
    var lyrics: [LyricLine] = []
    var synced = false

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        lyrics = c.list("lyrics", LyricLine.self); synced = c.bool("synced")
    }
}

struct ProfileUser: Decodable {
    var id = ""
    var username = ""
    var bio: String? = nil
    var avatarUrl: String? = nil
    var bannerUrl: String? = nil
    var roles: [String] = []
    var followerCount = 0
    var followingCount = 0

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); username = c.str("username"); bio = c.strOrNil("bio")
        avatarUrl = c.strOrNil("avatarUrl"); bannerUrl = c.strOrNil("bannerUrl"); roles = c.list("roles", String.self)
        followerCount = c.int("followerCount"); followingCount = c.int("followingCount")
    }
}

struct ProfileStats: Decodable {
    var totalListens = 0
    var totalMinutesListened = 0
    var uniqueTracks = 0
    var playlistCount = 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        totalListens = c.int("totalListens"); totalMinutesListened = c.int("totalMinutesListened")
        uniqueTracks = c.int("uniqueTracks"); playlistCount = c.int("playlistCount")
    }
}

struct ProfileArtist: Decodable, Hashable {
    var name = ""
    var image = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str("name"); image = c.str("image")
    }
}

struct ProfileResponse: Decodable {
    var user = ProfileUser()
    var stats: ProfileStats? = nil
    var topArtists: [ProfileArtist] = []
    var onRepeat: [Track] = []
    var likedSongs: [Track] = []
    var firstSong: Track? = nil
    var mutualArtists: [String] = []

    init(user: ProfileUser) { self.user = user }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        user = c.obj("user", ProfileUser.self) ?? ProfileUser(); stats = c.obj("stats", ProfileStats.self)
        topArtists = c.list("topArtists", ProfileArtist.self); onRepeat = c.list("onRepeat", Track.self)
        likedSongs = c.list("likedSongs", Track.self); firstSong = c.obj("firstSong", Track.self)
        mutualArtists = c.list("mutualArtists", String.self)
    }
}

/// A home shelf item, told apart by its "type" (no type means a track).
struct HomeItem: Decodable {
    enum Kind { case track, album, artist }
    var kind = Kind.track
    var track = Track()
    var album = Album()
    var artist = Artist()
    var reason = ""

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        reason = c.str("reason")
        switch c.strOrNil("type") {
        case "album":
            kind = .album
            album = try Album(from: decoder)
            if album.albumhash.isEmpty { album.albumhash = c.str("id") }
        case "artist":
            kind = .artist
            artist = try Artist(from: decoder)
            if artist.artisthash.isEmpty { artist.artisthash = c.str("id").isEmpty ? c.str("trackhash") : c.str("id") }
        default:
            track = try Track(from: decoder)
        }
    }
}

struct HomeSection: Decodable {
    var key = ""
    var title = ""
    var items: [HomeItem] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        key = c.str("key"); title = c.str("title"); items = c.list("items", HomeItem.self)
    }
}

struct SearchResponse {
    var tracks: [Track] = []
    var albums: [Album] = []
    var artists: [Artist] = []
    var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty }
}

/// A list wherever the server puts it: a bare array, or under one of `keys`,
/// or under `results.<key>`.
struct Flexible<T: Decodable>: Decodable {
    var items: [T] = []
    static var keys: [String] { ["tracks", "albums", "artists", "items", "results"] }

    init(from decoder: Decoder) throws {
        if var arr = try? decoder.unkeyedContainer() {
            while !arr.isAtEnd { if let v = try? arr.decode(T.self) { items.append(v) } else { _ = try? arr.decode(Skip.self) } }
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        for k in Flexible.keys {
            let v = c.list(k, T.self)
            if !v.isEmpty { items = v; return }
        }
        if let r = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("results")) {
            for k in Flexible.keys {
                let v = r.list(k, T.self)
                if !v.isEmpty { items = v; return }
            }
        }
    }
}

struct DailyPoint: Decodable, Hashable {
    var streams = 0
    var minutes = 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        streams = c.int("streams"); minutes = c.int("minutes")
    }
}

struct DetailedStats: Decodable {
    var totalStreams = 0
    var totalDurationMs = 0
    var uniqueTracks = 0
    var uniqueArtists = 0
    var daily: [DailyPoint] = []
    var hourly: [Int] = []
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        totalStreams = c.int("totalStreams"); totalDurationMs = c.int("totalDurationMs")
        uniqueTracks = c.int("uniqueTracks"); uniqueArtists = c.int("uniqueArtists")
        daily = c.list("daily", DailyPoint.self); hourly = c.list("hourly", Double.self).map { Int($0) }
    }
}

struct TopArtistItem: Decodable, Hashable {
    var name = ""
    var image = ""
    var helpText = ""
    var playcount = 0
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = c.str("name"); image = c.str("image"); helpText = c.str("help_text")
        playcount = (try? c.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey("extra")))?.int("playcount") ?? 0
    }
}

struct Achievement: Decodable, Hashable {
    var id = ""
    var name = ""
    var description = ""
    var tier = "Locked"
    var tierIndex = -1
    var progress = 0
    var threshold = 0
    var nextThreshold: Int? = nil
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); name = c.str("name"); description = c.str("description"); tier = c.str("tier", "Locked")
        tierIndex = c.int("tierIndex", -1); progress = c.int("progress"); threshold = c.int("threshold")
        nextThreshold = c.intOrNil("nextThreshold")
    }
}

struct TuneFilter: Codable, Hashable {
    var type = "PK"
    var fc = 1000.0
    var gain = 0.0
    var q = 1.0
    init(type: String, fc: Double, gain: Double, q: Double) { self.type = type; self.fc = fc; self.gain = gain; self.q = q }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        type = c.str("type", "PK"); fc = c.double("fc", 1000); gain = c.double("gain"); q = c.double("q", 1)
    }
}

struct DeviceTuning: Codable, Hashable {
    var deviceKey = ""
    var deviceName = ""
    var enabled = true
    var source = "test"
    var label = ""
    var autoEqId: String? = nil
    var preamp = 0.0
    var filters: [TuneFilter] = []

    init(source: String, label: String, autoEqId: String? = nil, preamp: Double, filters: [TuneFilter]) {
        self.source = source; self.label = label; self.autoEqId = autoEqId; self.preamp = preamp; self.filters = filters
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        deviceKey = c.str("deviceKey"); deviceName = c.str("deviceName"); enabled = c.bool("enabled", true)
        source = c.str("source", "test"); label = c.str("label"); autoEqId = c.strOrNil("autoEqId")
        preamp = c.double("preamp"); filters = c.list("filters", TuneFilter.self)
    }
}

struct AutoEqResult: Decodable, Hashable, Identifiable {
    var id = ""
    var name = ""
    var source = ""
    var form = ""
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        id = c.str("id"); name = c.str("name"); source = c.str("source"); form = c.str("form")
    }
}

// Request bodies

struct StreamTokenRequest: Encodable {
    var id: String
    var artist: String?
    var title: String?
    var isrc: String?
    var quality: String?
    var durationMs: Int?

    init(_ t: Track, quality: String?) {
        id = t.hash
        artist = t.artist.isEmpty ? nil : t.artist
        title = t.displayTitle.isEmpty ? nil : t.displayTitle
        isrc = (t.isrc ?? "").isEmpty ? nil : t.isrc
        self.quality = quality
        durationMs = t.durationMillis > 0 ? t.durationMillis : nil
    }
}

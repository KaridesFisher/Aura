import Foundation

public enum MediaKind: String, Codable, CaseIterable, Sendable {
    case live, movie, series, episode
    public var label: String {
        switch self { case .live: return "Canlı TV"; case .movie: return "Film"; case .series: return "Dizi"; case .episode: return "Bölüm" }
    }
}

public enum SourceKind: String, Codable, Sendable { case xtream, m3u, demo }

public struct PlaylistSource: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var server: String
    public var kind: SourceKind
    public var lastSync: Date?
    public var expiresAt: Date?
    public var connectionLimit: Int?
    public var epgURL: String?
    public init(id: UUID = UUID(), name: String, server: String, kind: SourceKind = .xtream) {
        self.id = id; self.name = name; self.server = server; self.kind = kind
    }
}

public struct Credentials: Codable, Sendable {
    public var username: String
    public var password: String
    public init(username: String, password: String) { self.username = username; self.password = password }
}

public struct MediaItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceID: UUID
    public var streamID: String
    public var kind: MediaKind
    public var title: String
    public var categoryID: String
    public var category: String
    public var artwork: String?
    public var backdrop: String?
    public var overview: String?
    public var year: String?
    public var rating: Double?
    public var duration: Double?
    public var fileExtension: String
    public var directURL: String?
    public var epgID: String?
    public var archiveDays: Int
    public var isAdult: Bool
    public var season: Int?
    public var episode: Int?
    public var seriesID: String?
    public var tmdbID: String?
    public var added: Date?
    public init(sourceID: UUID, streamID: String, kind: MediaKind, title: String,
                categoryID: String = "", category: String = "Genel", artwork: String? = nil,
                backdrop: String? = nil, overview: String? = nil, year: String? = nil,
                rating: Double? = nil, duration: Double? = nil, fileExtension: String = "mp4",
                directURL: String? = nil, epgID: String? = nil, archiveDays: Int = 0,
                isAdult: Bool = false, season: Int? = nil, episode: Int? = nil,
                seriesID: String? = nil, tmdbID: String? = nil, added: Date? = nil) {
        self.id = "\(sourceID.uuidString):\(kind.rawValue):\(streamID)"
        self.sourceID = sourceID; self.streamID = streamID; self.kind = kind; self.title = title
        self.categoryID = categoryID; self.category = category; self.artwork = artwork
        self.backdrop = backdrop; self.overview = overview; self.year = year; self.rating = rating
        self.duration = duration; self.fileExtension = fileExtension; self.directURL = directURL
        self.epgID = epgID; self.archiveDays = archiveDays; self.isAdult = isAdult
        self.season = season; self.episode = episode; self.seriesID = seriesID; self.tmdbID = tmdbID; self.added = added
    }
    public var subtitleQuery: String {
        title.replacingOccurrences(of: #"\b(2160p|1080p|720p|4K|UHD|FHD|HD|TR|EN|MULTI)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct GuideProgramme: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var channelID: String
    public var title: String
    public var summary: String
    public var start: Date
    public var end: Date
    public init(channelID: String, title: String, summary: String = "", start: Date, end: Date) {
        self.id = "\(channelID):\(start.timeIntervalSince1970)"
        self.channelID = channelID; self.title = title; self.summary = summary; self.start = start; self.end = end
    }
    public func progress(at date: Date = Date()) -> Double {
        guard end > start else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / end.timeIntervalSince(start)))
    }
    public var isNow: Bool { start <= Date() && end > Date() }
}

public struct WatchState: Codable, Sendable {
    public var position: Double = 0
    public var duration: Double = 0
    public var favorite: Bool = false
    public var watched: Bool = false
    public var lastPlayed: Date?
    public var updatedAt: Date = Date()
    public init() {}
    public var progress: Double { duration.isFinite && position.isFinite && duration > 0 ? min(1, max(0, position / duration)) : 0 }
    public var isInProgress: Bool { lastPlayed != nil && position >= 1 && !watched && (duration <= 0 || position < duration) }
    public var displayProgress: Double { watched ? 1 : progress }
    public mutating func updatePlayback(position: Double, duration: Double, at date: Date = Date()) {
        guard position.isFinite, duration.isFinite else { return }
        if duration > 0 { self.duration = duration }
        self.position = self.duration > 0 ? min(max(0, position), self.duration) : max(0, position)
        lastPlayed = date; updatedAt = date
        if self.duration > 0 && self.position >= max(self.duration - 10, self.duration * 0.99) { watched = true }
    }
}

public struct GuideCacheEntry: Codable, Sendable {
    public var programmes: [GuideProgramme]
    public var fetchedAt: Date
    public init(programmes: [GuideProgramme], fetchedAt: Date = Date()) {
        self.programmes = programmes; self.fetchedAt = fetchedAt
    }
    public func needsRefresh(at date: Date = Date()) -> Bool {
        date.timeIntervalSince(fetchedAt) >= 30 * 60 || fetchedAt > date ||
        (!programmes.isEmpty && programmes.allSatisfy { $0.end <= date })
    }
}

public enum WatchHistory {
    public static func recent(in items: [MediaItem], states: [String: WatchState], limit: Int = 12) -> [MediaItem] {
        Array(items.filter { ($0.kind == .movie || $0.kind == .episode) && states[$0.id]?.lastPlayed != nil }
            .sorted { (states[$0.id]?.lastPlayed ?? .distantPast) > (states[$1.id]?.lastPlayed ?? .distantPast) }.prefix(max(0, limit)))
    }
    public static func continuing(in items: [MediaItem], states: [String: WatchState], limit: Int = 12) -> [MediaItem] {
        recent(in: items.filter { states[$0.id]?.isInProgress == true }, states: states, limit: limit)
    }
    public static func nextEpisode(in episodes: [MediaItem], states: [String: WatchState]) -> MediaItem? {
        let ordered = episodes.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        if let latest = recent(in: ordered, states: states, limit: 1).first {
            if states[latest.id]?.watched != true { return latest }
            if let index = ordered.firstIndex(where: { $0.id == latest.id }),
               let next = ordered.dropFirst(index + 1).first(where: { states[$0.id]?.watched != true }) { return next }
        }
        return ordered.first(where: { states[$0.id]?.watched != true }) ?? ordered.first
    }
}

public struct PersonalLibrary: Codable, Sendable {
    public var states: [String: WatchState] = [:]
    public var renamed: [String: String] = [:]
    public var hiddenCategories: Set<String> = []
    public var updatedAt: Date = Date()
    public init() {}
    public mutating func merge(_ other: PersonalLibrary) {
        for (key, state) in other.states where states[key] == nil || states[key]!.updatedAt < state.updatedAt { states[key] = state }
        if other.updatedAt > updatedAt {
            renamed = other.renamed; hiddenCategories = other.hiddenCategories; updatedAt = other.updatedAt
        }
    }
}

public enum AuraError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}

public enum XtreamAddress {
    public static func parse(_ text: String, username: String = "", password: String = "") throws -> (String, Credentials) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""), components.host != nil else {
            throw AuraError.message("Geçerli bir http:// veya https:// sunucu adresi gir.")
        }
        let query = components.queryItems ?? []
        let user = username.isEmpty ? query.first(where: { $0.name == "username" })?.value ?? "" : username
        let pass = password.isEmpty ? query.first(where: { $0.name == "password" })?.value ?? "" : password
        if ["get.php", "player_api.php", "xmltv.php"].contains(components.url?.lastPathComponent ?? "") {
            components.path = (components.path as NSString).deletingLastPathComponent
        }
        components.query = nil; components.fragment = nil; components.user = nil; components.password = nil
        guard !user.isEmpty, !pass.isEmpty else { throw AuraError.message("Kullanıcı adı ve şifre gerekli. Bilgileri içeren Xtream bağlantısını da yapıştırabilirsin.") }
        return (components.url!.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")), Credentials(username: user, password: pass))
    }

    public static func apiURL(server: String, credentials: Credentials, action: String? = nil, parameters: [String: String] = [:]) throws -> URL {
        guard var c = URLComponents(string: server + "/player_api.php") else { throw AuraError.message("Sunucu adresi geçersiz.") }
        var query = [URLQueryItem(name: "username", value: credentials.username), URLQueryItem(name: "password", value: credentials.password)]
        if let action { query.append(URLQueryItem(name: "action", value: action)) }
        query += parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        c.queryItems = query
        guard let url = c.url else { throw AuraError.message("Bağlantı oluşturulamadı.") }; return url
    }
    public static func guideURL(server: String, credentials: Credentials) throws -> URL {
        let api = try apiURL(server: server, credentials: credentials)
        guard var components = URLComponents(url: api, resolvingAgainstBaseURL: false) else { throw AuraError.message("Rehber bağlantısı oluşturulamadı.") }
        components.path = (components.path as NSString).deletingLastPathComponent + "/xmltv.php"
        guard let url = components.url else { throw AuraError.message("Rehber bağlantısı oluşturulamadı.") }; return url
    }

    public static func streamURL(server: String, credentials: Credentials, item: MediaItem, liveFormat: String = "m3u8") throws -> URL {
        if let direct = item.directURL, let url = URL(string: direct), ["http", "https", "file"].contains(url.scheme ?? "") { return url }
        let kind = item.kind == .live ? "live" : item.kind == .movie ? "movie" : "series"
        let ext = item.kind == .live ? liveFormat : item.fileExtension
        return try pathURL(server: server, parts: [kind, credentials.username, credentials.password, "\(item.streamID).\(ext)"])
    }

    public static func catchupURL(server: String, credentials: Credentials, item: MediaItem, programme: GuideProgramme, offsetMinutes: Int = 0) throws -> URL {
        guard item.archiveDays > 0, programme.end < Date(), programme.start > Date().addingTimeInterval(-Double(item.archiveDays) * 86400) else {
            throw AuraError.message("Bu program için sağlayıcında arşiv kaydı bulunmuyor.")
        }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd:HH-mm"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let start = formatter.string(from: programme.start.addingTimeInterval(Double(offsetMinutes * 60)))
        let minutes = max(1, Int(ceil(programme.end.timeIntervalSince(programme.start) / 60)))
        return try pathURL(server: server, parts: ["timeshift", credentials.username, credentials.password, String(minutes), start, "\(item.streamID).ts"])
    }
    private static func pathURL(server: String, parts: [String]) throws -> URL {
        guard var c = URLComponents(string: server), ["https", "http"].contains(c.scheme ?? ""), c.host != nil else { throw AuraError.message("Sunucu adresi geçersiz.") }
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        c.percentEncodedPath = c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty ? "" : c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !c.percentEncodedPath.isEmpty { c.percentEncodedPath = "/" + c.percentEncodedPath }
        c.percentEncodedPath += "/" + parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }.joined(separator: "/")
        c.query = nil; c.fragment = nil
        guard let url = c.url else { throw AuraError.message("Yayın bağlantısı oluşturulamadı.") }; return url
    }
}

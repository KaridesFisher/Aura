import Foundation

public struct XtreamLibrary: Sendable {
    public var source: PlaylistSource
    public var items: [MediaItem]
}

public struct XtreamClient: Sendable {
    public var source: PlaylistSource
    public var credentials: Credentials
    private var session: URLSession
    public init(source: PlaylistSource, credentials: Credentials, session: URLSession = .shared) { self.source = source; self.credentials = credentials; self.session = session }

    private func request(_ action: String? = nil, parameters: [String: String] = [:]) async throws -> Any {
        let url = try XtreamAddress.apiURL(server: source.server, credentials: credentials, action: action, parameters: parameters)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData); request.timeoutInterval = 50
        request.setValue("Aura/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AuraError.message("Sunucu isteği başarısız. Adresi ve hesap bilgilerini kontrol et.") }
        guard data.count < 150_000_000 else { throw AuraError.message("Sunucunun yanıtı çok büyük.") }
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw AuraError.message("Sunucu geçerli bir Xtream yanıtı göndermedi.") }
    }

    public func load() async throws -> XtreamLibrary {
        guard let account = try await request() as? [String: Any],
              let user = account["user_info"] as? [String: Any], user.string("auth") == "1" else {
            throw AuraError.message("Xtream girişi reddedildi. Kullanıcı adı ve şifreyi kontrol et.")
        }
        let status = user.string("status").lowercased()
        guard status.isEmpty || status == "active" else { throw AuraError.message("Hesabın etkin değil: \(user.string("status")).") }
        var updated = source
        updated.connectionLimit = Int(user.string("max_connections"))
        if let epoch = Double(user.string("exp_date")) { updated.expiresAt = Date(timeIntervalSince1970: epoch) }
        // A failing catalog must never silently replace a previously complete catalog.
        async let live = catalog(.live)
        async let movies = catalog(.movie)
        async let series = catalog(.series)
        let items = try await live + movies + series
        guard !items.isEmpty else { throw AuraError.message("Sunucu boş katalog gönderdi. Kayıtlı kitaplık korundu; daha sonra yeniden dene.") }
        updated.lastSync = Date()
        return XtreamLibrary(source: updated, items: items)
    }

    private func catalog(_ kind: MediaKind) async throws -> [MediaItem] {
        let prefix = kind == .live ? "live" : kind == .movie ? "vod" : "series"
        let categoriesJSON = try await request("get_\(prefix)_categories")
        let categories = categoriesJSON as? [[String: Any]] ?? []
        let names = Dictionary(categories.map { ($0.string("category_id"), $0.string("category_name")) }, uniquingKeysWith: { first, _ in first })
        let action = kind == .series ? "get_series" : "get_\(prefix)_streams"
        guard let list = try await request(action) as? [[String: Any]] else { throw AuraError.message("\(kind.label) kataloğu okunamadı.") }
        return list.compactMap { Self.decodeItem($0, kind: kind, sourceID: source.id, categories: names) }
    }

    public static func decodeItem(_ row: [String: Any], kind: MediaKind, sourceID: UUID, categories: [String: String]) -> MediaItem? {
        let stream = row.string(kind == .series ? "series_id" : "stream_id")
        guard !stream.isEmpty else { return nil }
        let cat = row.string("category_id"), title = row.string("name")
        let artwork = row.string(kind == .series ? "cover" : "stream_icon")
        let backs = row["backdrop_path"] as? [String]
        let year = row.string("year").isEmpty ? String(row.string("releaseDate").prefix(4)) : row.string("year")
        return MediaItem(sourceID: sourceID, streamID: stream, kind: kind, title: title,
                         categoryID: cat, category: categories[cat] ?? "Genel", artwork: artwork.isEmpty ? nil : artwork,
                         backdrop: backs?.first, overview: row.string("plot").nilIfEmpty, year: year.nilIfEmpty,
                         rating: Double(row.string("rating")), fileExtension: row.string("container_extension").nilIfEmpty ?? "mp4",
                         epgID: row.string("epg_channel_id").nilIfEmpty,
                         archiveDays: row.string("tv_archive") == "1" ? Int(row.string("tv_archive_duration")) ?? 0 : 0,
                         isAdult: row.string("is_adult") == "1" || title.range(of: #"\b(adult|xxx|18\+)\b"#, options: [.regularExpression, .caseInsensitive]) != nil,
                         tmdbID: row.string("tmdb").nilIfEmpty,
                         added: Double(row.string("added")).map { Date(timeIntervalSince1970: $0) })
    }

    public func details(_ item: MediaItem) async throws -> MediaItem {
        guard item.kind == .movie else { return item }
        guard let result = try await request("get_vod_info", parameters: ["vod_id": item.streamID]) as? [String: Any],
              let info = result["info"] as? [String: Any] else { return item }
        var copy = item
        copy.overview = info.string("plot").nilIfEmpty ?? info.string("description").nilIfEmpty
        copy.backdrop = (info["backdrop_path"] as? [String])?.first
        copy.duration = Double(info.string("duration_secs"))
        copy.tmdbID = info.string("tmdb_id").nilIfEmpty
        return copy
    }

    public func episodes(_ series: MediaItem) async throws -> [MediaItem] {
        guard let result = try await request("get_series_info", parameters: ["series_id": series.streamID]) as? [String: Any],
              let seasons = result["episodes"] as? [String: [[String: Any]]] else { throw AuraError.message("Dizi bölümleri alınamadı.") }
        return seasons.flatMap { season, episodes in
            episodes.compactMap { row -> MediaItem? in
                let id = row.string("id"); guard !id.isEmpty else { return nil }
                let info = row["info"] as? [String: Any] ?? [:]
                return MediaItem(sourceID: source.id, streamID: id, kind: .episode, title: row.string("title"), categoryID: series.categoryID,
                                 category: series.title, artwork: info.string("movie_image").nilIfEmpty ?? series.artwork,
                                 backdrop: series.backdrop, overview: info.string("plot").nilIfEmpty,
                                 duration: Double(info.string("duration_secs")), fileExtension: row.string("container_extension").nilIfEmpty ?? "mp4",
                                 isAdult: series.isAdult, season: Int(season), episode: Int(row.string("episode_num")), seriesID: series.streamID)
            }
        }.sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
    }

    public func guide(_ item: MediaItem) async throws -> [GuideProgramme] {
        guard let result = try await request("get_simple_data_table", parameters: ["stream_id": item.streamID]) as? [String: Any],
              let rows = result["epg_listings"] as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard let start = Double(row.string("start_timestamp")), let end = Double(row.string("stop_timestamp")), end > start else { return nil }
            func decode(_ value: String) -> String { Data(base64Encoded: value).flatMap { String(data: $0, encoding: .utf8) } ?? value }
            return GuideProgramme(channelID: item.epgID ?? item.streamID, title: decode(row.string("title")), summary: decode(row.string("description")), start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end))
        }.sorted { $0.start < $1.start }
    }
}

extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String {
        if let value = self[key] as? String { return value }
        if let value = self[key] as? NSNumber { return value.stringValue }
        return ""
    }
}
extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }

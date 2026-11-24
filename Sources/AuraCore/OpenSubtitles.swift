import Foundation

public struct SubtitleResult: Identifiable, Codable, Sendable {
    public let id: String
    public let attributes: Attributes
    public struct Attributes: Codable, Sendable {
        public let language: String
        public let release: String?
        public let downloadCount: Int?
        public let hearingImpaired: Bool?
        public let foreignPartsOnly: Bool?
        public let fps: Double?
        public let files: [File]
        enum CodingKeys: String, CodingKey {
            case language, release, files, fps
            case downloadCount = "download_count", hearingImpaired = "hearing_impaired", foreignPartsOnly = "foreign_parts_only"
        }
    }
    public struct File: Codable, Sendable {
        public let fileID: Int
        public let fileName: String
        enum CodingKeys: String, CodingKey { case fileID = "file_id", fileName = "file_name" }
    }
}

public struct SubtitleSession: Codable, Sendable {
    public var token: String
    public var baseURL: String
    public init(token: String = "", baseURL: String = "api.opensubtitles.com") { self.token = token; self.baseURL = baseURL }
}

public struct OpenSubtitlesClient: Sendable {
    public var apiKey: String
    public var session: SubtitleSession
    public init(apiKey: String, session: SubtitleSession = SubtitleSession()) { self.apiKey = apiKey; self.session = session }

    private func request(_ path: String, method: String = "GET", query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> Data {
        guard !apiKey.isEmpty else { throw AuraError.message("Önce Ayarlar → Altyazı bölümüne OpenSubtitles API anahtarını ekle.") }
        // Authentication tokens may only be sent to the service's documented hosts.
        let host = session.baseURL.replacingOccurrences(of: "https://", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard ["api.opensubtitles.com", "vip-api.opensubtitles.com"].contains(host) else { throw AuraError.message("OpenSubtitles sunucu adresi tanınmıyor. Yeniden giriş yap.") }
        var components = URLComponents(string: "https://\(host)/api/v1/\(path)")!
        if !query.isEmpty { components.queryItems = query.sorted { $0.name < $1.name } }
        var request = URLRequest(url: components.url!); request.httpMethod = method; request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "Api-Key")
        request.setValue("Aura v1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !session.token.isEmpty { request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message: String
            switch status {
            case 401, 403: message = "OpenSubtitles erişimi reddetti. API anahtarını kontrol et veya yeniden giriş yap."
            case 406, 429: message = "OpenSubtitles indirme kotasına veya hız sınırına ulaşıldı. Daha sonra tekrar dene."
            default: message = "OpenSubtitles şu anda yanıt veremiyor (\(status))."
            }
            throw AuraError.message(message)
        }
        return data
    }

    public func login(username: String, password: String) async throws -> SubtitleSession {
        let data = try await request("login", method: "POST", body: ["username": username, "password": password])
        struct Response: Decodable { let token: String; let base_url: String? }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return SubtitleSession(token: response.token, baseURL: response.base_url ?? "api.opensubtitles.com")
    }
    public func search(query: String, language: String, season: Int? = nil, episode: Int? = nil) async throws -> [SubtitleResult] {
        var parameters = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "languages", value: language)]
        if let season { parameters.append(URLQueryItem(name: "season_number", value: String(season))) }
        if let episode { parameters.append(URLQueryItem(name: "episode_number", value: String(episode))) }
        parameters.append(URLQueryItem(name: "order_by", value: "download_count"))
        parameters.append(URLQueryItem(name: "order_direction", value: "desc"))
        let data = try await request("subtitles", query: parameters)
        struct Response: Decodable { let data: [SubtitleResult] }
        return try JSONDecoder().decode(Response.self, from: data).data
    }
    public func download(fileID: Int) async throws -> Data {
        let data = try await request("download", method: "POST", body: ["file_id": fileID, "sub_format": "srt"])
        struct Response: Decodable { let link: String }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let url = URL(string: response.link), url.scheme == "https" else { throw AuraError.message("Altyazı indirme bağlantısı geçersiz.") }
        let (subtitle, http) = try await URLSession.shared.data(from: url)
        guard (http as? HTTPURLResponse)?.statusCode == 200, subtitle.count < 10_000_000 else { throw AuraError.message("Altyazı dosyası indirilemedi.") }
        return subtitle
    }
}

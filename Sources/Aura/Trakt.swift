import SwiftUI
import AuraCore

private struct TraktToken: Codable {
    var access_token: String
    var refresh_token: String
    var created_at: Double
    var expires_in: Double
}
private struct TraktAccount: Codable {
    var clientID: String
    var clientSecret: String
    var token: TraktToken
}
private struct TraktHTTPError: Error { let status: Int }

@MainActor final class TraktManager: ObservableObject {
    @Published var connected = false
    @Published var busy = false
    @Published var userCode = ""
    @Published var status = ""
    @Published var enabled = UserDefaults.standard.bool(forKey: "trakt-scrobble") {
        didSet { UserDefaults.standard.set(enabled, forKey: "trakt-scrobble") }
    }
    private var account: TraktAccount?
    private var authTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var authorizationGeneration = UUID()
    init() {
        if let data = try? Vault.read("trakt-account"), let saved = try? JSONDecoder().decode(TraktAccount.self, from: data) { account = saved; connected = true }
    }
    private func request(_ path: String, clientID: String, body: [String: Any], token: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.trakt.tv/" + path)!); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version"); request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("Aura/1.0", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw TraktHTTPError(status: code) }; return data
    }
    func connect(clientID: String, secret: String) {
        authTask?.cancel(); let generation = UUID(); authorizationGeneration = generation
        busy = true; status = "Yetkilendirme kodu alınıyor…"; userCode = ""
        authTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.authorizationGeneration == generation { self.busy = false } }
            do {
                struct Device: Decodable { let device_code: String; let user_code: String; let verification_url: String; let expires_in: Int; let interval: Int }
                let data = try await self.request("oauth/device/code", clientID: clientID, body: ["client_id": clientID])
                let device = try JSONDecoder().decode(Device.self, from: data)
                self.userCode = device.user_code; self.status = "Trakt sayfasında bu kodu girip bağlantıyı onayla."
                if let url = URL(string: device.verification_url), url.host == "trakt.tv", url.scheme == "https" { NSWorkspace.shared.open(url) }
                let expiry = Date().addingTimeInterval(Double(device.expires_in))
                var interval = max(5, device.interval)
                while !Task.isCancelled && Date() < expiry {
                    try await Task.sleep(for: .seconds(interval))
                    do {
                        let response = try await self.request("oauth/device/token", clientID: clientID, body: ["code": device.device_code, "client_id": clientID, "client_secret": secret])
                        let token = try JSONDecoder().decode(TraktToken.self, from: response)
                        guard !Task.isCancelled, self.authorizationGeneration == generation else { return }
                        let saved = TraktAccount(clientID: clientID, clientSecret: secret, token: token)
                        try Vault.save(JSONEncoder().encode(saved), account: "trakt-account")
                        self.account = saved; self.connected = true; self.enabled = true; self.userCode = ""; self.status = "Trakt hesabın bağlandı."; return
                    } catch let error as TraktHTTPError {
                        if error.status == 400 { continue }
                        if error.status == 429 { interval += 5; continue }
                        throw AuraError.message(error.status == 418 ? "Trakt bağlantısı onaylanmadı." : "Yetkilendirme kodu geçersiz veya süresi doldu. Yeniden dene.")
                    }
                }
                if !Task.isCancelled { self.status = "Kodun süresi doldu. Yeniden bağlanabilirsin." }
            } catch is CancellationError { }
            catch { self.status = "Trakt bağlantısı kurulamadı. Uygulama anahtarlarını kontrol et." }
        }
    }
    func cancelAuthentication() { authorizationGeneration = UUID(); authTask?.cancel(); authTask = nil; busy = false; userCode = ""; status = "Bağlantı iptal edildi." }
    func disconnect() {
        cancelAuthentication(); eventTask?.cancel(); account = nil; connected = false; enabled = false
        Vault.remove("trakt-account"); status = "Bu Mac’teki bağlantı kaldırıldı. Trakt izinlerini hesabının bağlı uygulamalar bölümünden yönetebilirsin."
    }
    func track(_ event: String, item: MediaItem, progress: Double, seriesTMDB: String? = nil) {
        guard enabled, connected, item.kind == .movie || item.kind == .episode, progress.isFinite else { return }
        var body: [String: Any] = ["progress": min(100, max(0, progress)), "app_version": "1.0.0"]
        if item.kind == .movie, let id = item.tmdbID.flatMap(Int.init) { body["movie"] = ["ids": ["tmdb": id]] }
        else if item.kind == .episode, let id = seriesTMDB.flatMap(Int.init), let season = item.season, let episode = item.episode {
            body["show"] = ["ids": ["tmdb": id]]; body["episode"] = ["season": season, "number": episode]
        } else { status = "Bu içerikte TMDB kimliği yok; izleme bilgisi gönderilmedi."; return }
        let previous = eventTask
        eventTask = Task { [weak self] in
            await previous?.value
            guard !Task.isCancelled, let self, var account = self.account else { return }
            do {
                if account.token.created_at + account.token.expires_in < Date().timeIntervalSince1970 + 120 {
                    let data = try await self.request("oauth/token", clientID: account.clientID, body: ["refresh_token": account.token.refresh_token, "client_id": account.clientID, "client_secret": account.clientSecret, "redirect_uri": "urn:ietf:wg:oauth:2.0:oob", "grant_type": "refresh_token"])
                    account.token = try JSONDecoder().decode(TraktToken.self, from: data)
                    try Vault.save(JSONEncoder().encode(account), account: "trakt-account"); self.account = account
                }
                guard !Task.isCancelled, self.connected else { return }
                _ = try await self.request("scrobble/" + event, clientID: account.clientID, body: body, token: account.token.access_token)
                self.status = "Son izleme bilgisi Trakt’a gönderildi."
            } catch let error as TraktHTTPError {
                if error.status == 401 { self.status = "Trakt oturumunun süresi doldu. Hesabını yeniden bağla." }
                else if error.status != 422 && error.status != 409 { self.status = "Trakt isteği tamamlanamadı (\(error.status))." }
            } catch { self.status = "Trakt’a ulaşılamadı. Yerel izleme ilerlemen kaydedildi." }
        }
    }
}

struct TraktSettings: View {
    @ObservedObject var manager: TraktManager
    @State private var clientID = ""
    @State private var secret = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Label("Trakt", systemImage: "checkmark.circle").font(.system(size: 17, weight: .medium)); Spacer(); Link("Uygulama anahtarları ↗", destination: URL(string: "https://trakt.tv/oauth/applications")!).font(.system(size: 11)) }
            Text("İzleme geçmişini Trakt hesabına gönder. Kendi Trakt uygulamanın Client ID ve Client Secret anahtarlarını girip tarayıcıda yetkilendir. Sağlayıcının TMDB kimliği verdiği filmler ve bölümler desteklenir.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(AuraTheme.muted)
            if manager.connected {
                Toggle("İzleme bilgisini Trakt’a gönder", isOn: $manager.enabled)
                Button("Bağlantıyı kaldır") { manager.disconnect() }.buttonStyle(QuietButton())
            } else {
                HStack { LabeledInput(label: "Client ID", placeholder: "Trakt Client ID", value: $clientID, secure: true); LabeledInput(label: "Client Secret", placeholder: "Trakt Client Secret", value: $secret, secure: true) }
                if !manager.userCode.isEmpty { Text(manager.userCode).font(.system(size: 29, weight: .light, design: .monospaced)).tracking(4).foregroundStyle(AuraTheme.accent).textSelection(.enabled) }
                HStack {
                    Button(manager.busy ? "Onay bekleniyor…" : "Trakt hesabını bağla") { manager.connect(clientID: clientID, secret: secret) }.buttonStyle(AccentButton(compact: true)).disabled(manager.busy || clientID.isEmpty || secret.isEmpty)
                    if manager.busy { Button("İptal") { manager.cancelAuthentication() }.buttonStyle(QuietButton()) }
                }
            }
            if !manager.status.isEmpty { Text(manager.status).font(.system(size: 11)).foregroundStyle(AuraTheme.accent) }
        }.font(.system(size: 12)).padding(23).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}

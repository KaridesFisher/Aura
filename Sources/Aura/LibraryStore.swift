import SwiftUI
import AuraCore
import UniformTypeIdentifiers
import UserNotifications
import CryptoKit

enum Destination: String, CaseIterable, Identifiable {
    case home, live, movies, series, guide, favorites, downloads, multiview, sources, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: return "Senin için"; case .live: return "Canlı TV"; case .movies: return "Filmler"
        case .series: return "Diziler"; case .guide: return "Yayın rehberi"; case .favorites: return "Listem"
        case .downloads: return "İndirilenler"; case .multiview: return "Çoklu ekran"; case .sources: return "Kaynaklar"; case .settings: return "Ayarlar"
        }
    }
    var icon: String {
        switch self {
        case .home: return "square.grid.2x2"; case .live: return "dot.radiowaves.left.and.right"
        case .movies: return "film"; case .series: return "play.rectangle.on.rectangle"
        case .guide: return "calendar"; case .favorites: return "bookmark"; case .downloads: return "arrow.down.circle"
        case .multiview: return "rectangle.split.2x2"; case .sources: return "square.stack.3d.up"; case .settings: return "slider.horizontal.3"
        }
    }
}

@MainActor final class LibraryStore: ObservableObject {
    @Published var sources: [PlaylistSource] = []
    @Published var items: [MediaItem] = []
    @Published var personal = PersonalLibrary()
    @Published var preferences = PlayerPreferences()
    @Published var playerPresented = false
    @Published var destination: Destination = .home
    @Published var query = "" {
        didSet { if query.isEmpty { searchMatches = [] } }
    }
    private var searchMatches = Set<String>()
    func search(_ text: String) async {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if term.isEmpty { query = ""; return }
        let snapshot = items, names = personal.renamed
        let worker = Task.detached(priority: .userInitiated) {
            MediaSearch.matchingIDs(in: snapshot, renamed: names, query: term)
        }
        let matches = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard !Task.isCancelled else { return }
        searchMatches = matches; query = term
    }
    @Published var selectedCategory = "Tümü"
    @Published var selectedSource: UUID? {
        didSet { UserDefaults.standard.set(selectedSource?.uuidString, forKey: "selected-source") }
    }
    @Published var showAddSource = false
    @Published var selectedItem: MediaItem?
    @Published var loadingSources: Set<UUID> = []
    @Published var error: String?
    @Published var notice: String?
    @Published var guide: [String: [GuideProgramme]] = [:]
    @Published var guideRefreshingSources: Set<UUID> = []
    @Published var guideRefreshStatus = ""
    @Published var unlocked = false
    @Published var showUnlock = false
    @Published var syncFolder: URL?
    @Published var lastFolderSync: Date?
    private var syncTimer: Timer?
    private var syncInFlight = false
    private var pendingSave: Task<Void, Never>?
    private let persistenceQueue = DispatchQueue(label: "dev.aura.persistence", qos: .utility)
    private var loadFailed = false
    private var catalogDirty = false
    private var guideDirty = false
    private var guideCache: [String: GuideCacheEntry] = [:]
    private var guideSourceDates: [UUID: Date] = [:]
    private var guideSourceTasks: [UUID: Task<Void, Never>] = [:]
    private var lastSourceGuideAttempt: [UUID: Date] = [:]
    private var guideTasks: [String: Task<Void, Never>] = [:]
    private var lastGuideAttempt: [String: Date] = [:]
    private var guideTimer: Timer?
    let player = PlaybackController()
    let transfers = TransferManager()
    let trakt = TraktManager()

    init() {
        do {
            if let saved = try Disk.load("library.aura", as: SavedLibrary.self) { sources = saved.sources; items = saved.items; personal = saved.personal }
            if let saved = try Disk.load("personal.aura", as: PersonalLibrary.self) { personal = saved }
            if let prefs = try Disk.load("preferences.aura", as: PlayerPreferences.self) { preferences = prefs }
        } catch { self.error = "Kayıtlı kitaplık açılamadı. Mevcut dosyanın üzerine yazılmadı. \(error.localizedDescription)"; loadFailed = true }
        if sources.isEmpty && !loadFailed { sources = [Demo.source]; items = Demo.items; catalogDirty = true }
        // A damaged guide cache must not prevent the account or library loading.
        do {
            let savedGuide = try Disk.load("guide.aura", as: SavedGuide.self) ?? SavedGuide()
            guideCache = savedGuide.channels; guideSourceDates = savedGuide.refreshedSources
            let channels = Set(items.filter { $0.kind == .live }.map(\.id))
            guideCache = guideCache.filter { channels.contains($0.key) }
            guide = guideCache.mapValues(\.programmes)
        } catch { notice = "Kayıtlı rehber yeniden indirilecek. Hesabın ve kitaplığın korundu." }
        selectedSource = UserDefaults.standard.string(forKey: "selected-source").flatMap(UUID.init(uuidString:))
        if selectedSource == nil || !sources.contains(where: { $0.id == selectedSource }) { selectedSource = sources.first(where: { $0.kind != .demo })?.id }
        player.store = self; transfers.store = self
        restoreSyncFolder()
        syncTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in Task { @MainActor in self?.syncPersonal() } }
        guideTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                await self.refreshGuideSources()
            }
        }
        if !loadFailed { persist() }
        // Always issue a fresh EPG request on launch, regardless of cache age.
        Task { await refreshGuideSources(force: true) }
        Task { await refreshStaleSources() }
    }

    var isDemoOnly: Bool { sources.allSatisfy { $0.kind == .demo } }
    var visibleItems: [MediaItem] {
        items.filter { item in
            (!preferences.hideAdult || !item.isAdult || unlocked) &&
            !personal.hiddenCategories.contains("\(item.sourceID):\(item.categoryID)") &&
            (selectedSource == nil || item.sourceID == selectedSource)
        }
    }
    var currentItems: [MediaItem] {
        var list = visibleItems
        switch destination {
        case .live, .guide, .multiview: list = list.filter { $0.kind == .live }
        case .movies: list = list.filter { $0.kind == .movie }
        case .series: list = list.filter { $0.kind == .series }
        case .favorites: list = list.filter { personal.states[$0.id]?.favorite == true }
        default: break
        }
        if selectedCategory != "Tümü" { list = list.filter { $0.category == selectedCategory } }
        if !query.isEmpty { list = list.filter { searchMatches.contains($0.id) } }
        return list
    }
    var categories: [String] {
        let kind: MediaKind? = [.live, .guide, .multiview].contains(destination) ? .live : destination == .movies ? .movie : destination == .series ? .series : nil
        let names = Array(Set(visibleItems.filter { kind == nil || $0.kind == kind }.map(\.category)))
        return ["Tümü"] + (kind == .live ? LiveCategoryOrder.sorted(names) : names.sorted())
    }
    var continueWatching: [MediaItem] {
        WatchHistory.continuing(in: visibleItems, states: personal.states)
    }
    var recentlyWatched: [MediaItem] { WatchHistory.recent(in: visibleItems, states: personal.states) }
    func parentSeries(_ item: MediaItem) -> MediaItem? { items.first { $0.sourceID == item.sourceID && $0.kind == .series && $0.streamID == item.seriesID } }
    func title(_ item: MediaItem) -> String { personal.renamed[item.id] ?? item.title }
    func source(_ item: MediaItem) -> PlaylistSource? { sources.first { $0.id == item.sourceID } }
    func credentials(_ id: UUID) throws -> Credentials {
        guard let data = try Vault.read("source-\(id)"), let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { throw AuraError.message("Bu kaynağın giriş bilgileri eksik. Kaynağı yeniden ekle.") }
        return credentials
    }
    func client(_ item: MediaItem) throws -> XtreamClient {
        guard let source = source(item) else { throw AuraError.message("Kaynak bulunamadı.") }
        return XtreamClient(source: source, credentials: try credentials(source.id))
    }
    func url(_ item: MediaItem) throws -> URL {
        if let direct = item.directURL, direct.hasPrefix("bundlevideo:"), let url = AuraResources.bundle.url(forResource: String(direct.dropFirst(12)), withExtension: "mp4", subdirectory: "Resources/Video") { return url }
        if let direct = item.directURL, let url = URL(string: direct) { return url }
        guard let source = source(item) else { throw AuraError.message("Kaynak bulunamadı.") }
        return try XtreamAddress.streamURL(server: source.server, credentials: credentials(source.id), item: item, liveFormat: preferences.liveFormat)
    }
    func play(_ item: MediaItem, overrideURL: URL? = nil, fromBeginning: Bool = false) {
        if item.isAdult && preferences.hideAdult && !unlocked { showUnlock = true; return }
        if item.kind == .series { selectedItem = item; return }
        do {
            let url = try overrideURL ?? self.url(item)
            let state = personal.states[item.id]
            let resume = !fromBeginning && preferences.rememberPosition && item.kind != .live && state?.watched != true ? state?.position ?? 0 : 0
            player.play(item, url: url, resume: resume)
            var next = state ?? WatchState(); next.position = resume
            if resume == 0 { next.watched = false }
            next.lastPlayed = Date(); next.updatedAt = Date(); personal.states[item.id] = next
            persist()
        } catch { self.error = error.localizedDescription }
    }
    func toggleFavorite(_ item: MediaItem) {
        var state = personal.states[item.id] ?? WatchState(); state.favorite.toggle(); state.updatedAt = Date()
        personal.states[item.id] = state; persist()
    }
    func markWatched(_ item: MediaItem) {
        var state = personal.states[item.id] ?? WatchState(); state.watched.toggle(); state.updatedAt = Date()
        personal.states[item.id] = state; persist()
    }
    func saveProgress(_ item: MediaItem, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite else { return }
        var state = personal.states[item.id] ?? WatchState()
        state.updatePlayback(position: position, duration: duration)
        personal.states[item.id] = state; persist()
    }
    func rename(_ item: MediaItem, to title: String) { personal.renamed[item.id] = title; personal.updatedAt = Date(); persist() }
    func hideCategory(_ item: MediaItem) { personal.hiddenCategories.insert("\(item.sourceID):\(item.categoryID)"); personal.updatedAt = Date(); persist() }
    func persist() {
        guard !loadFailed else { return }
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400)); guard !Task.isCancelled, let self else { return }; self.saveInBackground()
        }
    }
    private func saveInBackground() {
        guard !loadFailed else { return }
        let library = catalogDirty ? SavedLibrary(sources: sources, items: items, personal: personal) : nil
        let epg = guideDirty ? SavedGuide(channels: guideCache, refreshedSources: guideSourceDates) : nil
        let personalSnapshot = personal, preferencesSnapshot = preferences
        catalogDirty = false; guideDirty = false
        persistenceQueue.async { [weak self] in
            do {
                if let library { try Disk.save(library, name: "library.aura") }
                try Disk.save(personalSnapshot, name: "personal.aura")
                try Disk.save(preferencesSnapshot, name: "preferences.aura")
                if let epg { try Disk.save(epg, name: "guide.aura") }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if library != nil { self.catalogDirty = true }
                    if epg != nil { self.guideDirty = true }
                    self.error = "Değişiklikler kaydedilemedi: \(message)"
                }
            }
        }
    }
    func flush() {
        guard !loadFailed else { return }
        pendingSave?.cancel()
        do {
          // Drain older snapshots before the final synchronous shutdown save.
          try persistenceQueue.sync {
            try Disk.save(SavedLibrary(sources: sources, items: items, personal: personal), name: "library.aura"); catalogDirty = false
            try Disk.save(personal, name: "personal.aura")
            try Disk.save(preferences, name: "preferences.aura")
            try Disk.save(SavedGuide(channels: guideCache, refreshedSources: guideSourceDates), name: "guide.aura"); guideDirty = false
          }
        }
        catch { self.error = "Değişiklikler kaydedilemedi: \(error.localizedDescription)" }
    }

    func addXtream(name: String, address: String, username: String, password: String) async throws {
        let (server, credentials) = try XtreamAddress.parse(address, username: username, password: password)
        let id = stableSourceID(server + "|" + credentials.username)
        guard !sources.contains(where: { $0.id == id }) else { throw AuraError.message("Bu hesap zaten ekli. Kaynaklar bölümünden yenileyebilirsin.") }
        let source = PlaylistSource(id: id, name: name.isEmpty ? "Xtream" : name, server: server)
        let result = try await XtreamClient(source: source, credentials: credentials).load()
        try Vault.save(JSONEncoder().encode(credentials), account: "source-\(source.id)")
        sources.append(result.source); items += result.items; selectedSource = source.id; catalogDirty = true; persist(); notice = "\(result.items.count.formatted()) içerik kitaplığına eklendi."
        Task { await refreshGuideSource(result.source, force: true) }
    }
    func addM3U(name: String, address: String, epgURL: String) async throws {
        guard let url = URL(string: address), ["http", "https", "file"].contains(url.scheme ?? "") else { throw AuraError.message("Geçerli bir M3U bağlantısı gir.") }
        let data: Data
        if url.isFileURL { data = try Data(contentsOf: url) }
        else {
            var request = URLRequest(url: url); request.timeoutInterval = 45
            let (body, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuraError.message("M3U listesi indirilemedi.") }; data = body
        }
        guard data.count < 100_000_000, let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") else { throw AuraError.message("Geçerli bir UTF-8 M3U listesi bulunamadı.") }
        let id = stableSourceID(address)
        guard !sources.contains(where: { $0.id == id }) else { throw AuraError.message("Bu liste zaten ekli.") }
        var source = PlaylistSource(id: id, name: name.isEmpty ? "M3U" : name, server: address, kind: .m3u)
        source.epgURL = epgURL.isEmpty ? nil : epgURL; source.lastSync = Date()
        let parsed = M3UParser.parse(text, sourceID: source.id, baseURL: url)
        guard !parsed.isEmpty else { throw AuraError.message("Listede oynatılabilir içerik yok.") }
        sources.append(source); items += parsed; catalogDirty = true; persist()
        Task { await refreshGuideSource(source, force: true) }
    }
    func removeSource(_ source: PlaylistSource) {
        if player.current?.sourceID == source.id { player.close() }
        sources.removeAll { $0.id == source.id }; items.removeAll { $0.sourceID == source.id }
        for key in Array(guideCache.keys) where key.hasPrefix(source.id.uuidString + ":") {
            guideCache[key] = nil; guide[key] = nil; lastGuideAttempt[key] = nil
            guideTasks[key]?.cancel(); guideTasks[key] = nil
        }
        guideDirty = true
        guideSourceTasks[source.id]?.cancel(); guideSourceTasks[source.id] = nil
        guideSourceDates[source.id] = nil; lastSourceGuideAttempt[source.id] = nil
        Vault.remove("source-\(source.id)"); if selectedSource == source.id { selectedSource = nil }; catalogDirty = true; persist()
    }
    func refresh(_ source: PlaylistSource) async {
        guard source.kind != .demo, !loadingSources.contains(source.id) else { return }
        loadingSources.insert(source.id); defer { loadingSources.remove(source.id) }
        do {
            var result: [MediaItem], updated = source
            if source.kind == .xtream {
                let library = try await XtreamClient(source: source, credentials: credentials(source.id)).load()
                result = library.items; updated = library.source
            } else {
                guard let url = URL(string: source.server) else { return }
                let data: Data
                if url.isFileURL { data = try Data(contentsOf: url) }
                else { let (body, response) = try await URLSession.shared.data(from: url); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuraError.message("M3U yenilenemedi.") }; data = body }
                result = M3UParser.parse(String(decoding: data, as: UTF8.self), sourceID: source.id, baseURL: url)
                guard !result.isEmpty else { throw AuraError.message("Yenilenen listede içerik yok. Önceki liste korundu.") }
                updated.lastSync = Date()
            }
            items.removeAll { $0.sourceID == source.id && $0.kind != .episode }; items += result
            if let i = sources.firstIndex(where: { $0.id == source.id }) { sources[i] = updated }
            // Keep the last usable guide visible until a new response succeeds.
            let channels = Set(items.filter { $0.kind == .live }.map(\.id))
            guideCache = guideCache.filter { channels.contains($0.key) }; guide = guideCache.mapValues(\.programmes)
            guideDirty = true; catalogDirty = true; persist()
            await refreshGuideSource(updated, force: true)
        } catch { self.error = "\(source.name): \(error.localizedDescription)" }
    }
    func refreshStaleSources() async {
        for source in sources where source.lastSync == nil || source.lastSync! < Date().addingTimeInterval(-6 * 3600) { await refresh(source) }
    }
    func loadEpisodes(_ series: MediaItem) async throws -> [MediaItem] {
        let episodes = try await client(series).episodes(series)
        items.removeAll { $0.sourceID == series.sourceID && $0.seriesID == series.streamID && $0.kind == .episode }
        items += episodes; catalogDirty = true; persist(); return episodes
    }
    func refreshGuideSources(force: Bool = false) async {
        // One XMLTV download per source updates the entire channel guide.
        // Separate tasks ensure an unreachable source cannot delay the others.
        let requests = sources.filter { $0.kind != .demo }.map { source in
            Task { await self.refreshGuideSource(source, force: force) }
        }
        for request in requests { await request.value }
    }
    func refreshGuideSource(_ source: PlaylistSource, force: Bool = false) async {
        guard source.kind == .xtream || source.epgURL != nil else { return }
        if let existing = guideSourceTasks[source.id] { await existing.value; return }
        if !force {
            if let last = guideSourceDates[source.id], Date().timeIntervalSince(last) < 30 * 60 { return }
            if let last = lastSourceGuideAttempt[source.id], Date().timeIntervalSince(last) < 60 { return }
        }
        lastSourceGuideAttempt[source.id] = Date()
        guideRefreshingSources.insert(source.id)
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.guideSourceTasks[source.id] = nil; self.guideRefreshingSources.remove(source.id) }
            var tryChannelAPI = false
            do {
                let url: URL
                if source.kind == .xtream { url = try XtreamAddress.guideURL(server: source.server, credentials: self.credentials(source.id)) }
                else if let address = source.epgURL, let parsed = URL(string: address) { url = parsed }
                else { return }
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                request.setValue(self.preferences.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                tryChannelAPI = [200, 404, 405].contains(status)
                guard status == 200, data.count < 150_000_000 else { throw AuraError.message("Rehber indirilemedi.") }
                let indexed = try await Task.detached { () -> [String: [GuideProgramme]] in
                    let programmes = try XMLTVParser.parse(data)
                    guard !programmes.isEmpty else { throw AuraError.message("Sunucu boş rehber gönderdi.") }
                    return Dictionary(grouping: programmes, by: \.channelID)
                }.value
                guard !Task.isCancelled, self.sources.contains(where: { $0.id == source.id }) else { return }
                var matched = false
                var updatedCache = self.guideCache, updatedGuide = self.guide
                let refreshedAt = Date()
                for channel in self.items where channel.sourceID == source.id && channel.kind == .live {
                    if let programmes = indexed[channel.epgID ?? channel.streamID] ?? indexed[channel.streamID] {
                        updatedCache[channel.id] = GuideCacheEntry(programmes: programmes, fetchedAt: refreshedAt)
                        updatedGuide[channel.id] = programmes; matched = true
                    }
                }
                guard matched else { throw AuraError.message("Programlar kanallarla eşleştirilemedi.") }
                self.guideCache = updatedCache; self.guide = updatedGuide
                self.guideSourceDates[source.id] = Date(); self.guideDirty = true; self.persist()
                self.guideRefreshStatus = "Son yenileme: " + Date().formatted(date: .omitted, time: .shortened)
            } catch {
                guard !Task.isCancelled else { return }
                self.guideRefreshStatus = "Bağlantı kurulamadı · Son kayıtlı rehber korunuyor"
                // Some Xtream providers expose only the channel API. Refresh
                // previously viewed channels, then load others on demand.
                if source.kind == .xtream && tryChannelAPI {
                    let recent = self.items.filter { $0.sourceID == source.id && $0.kind == .live && self.guideCache[$0.id] != nil }
                        .sorted { (self.guideCache[$0.id]?.fetchedAt ?? .distantPast) > (self.guideCache[$1.id]?.fetchedAt ?? .distantPast) }
                    for channel in recent.prefix(24) {
                        guard !Task.isCancelled else { return }
                        await self.loadGuide(channel, force: true)
                    }
                }
            }
        }
        guideSourceTasks[source.id] = task; await task.value
    }
    func loadGuide(_ item: MediaItem, force: Bool = false) async {
        guard guideTasks[item.id] == nil else { return }
        if !force {
            if let cached = guideCache[item.id], !cached.needsRefresh() { return }
            if let attempt = lastGuideAttempt[item.id], Date().timeIntervalSince(attempt) < 60 { return }
        }
        if let source = source(item), source.kind == .m3u {
            await refreshGuideSource(source, force: force); return
        }
        lastGuideAttempt[item.id] = Date()
        let task = Task { [weak self] in
            guard let self else { return }
            defer { self.guideTasks[item.id] = nil }
            do {
                if self.source(item)?.kind == .xtream {
                    let programmes = try await self.client(item).guide(item)
                    guard !Task.isCancelled, self.source(item) != nil else { return }
                    self.cacheGuide(programmes, for: item)
                }
                else { self.cacheGuide([], for: item) }
            } catch {
                if Task.isCancelled { return }
                // Never blank an existing guide when the provider is offline.
                self.notice = self.guide[item.id] == nil ? "Rehber şu an yenilenemedi. Bağlantı geldiğinde tekrar denenecek." : "Rehber yenilenemedi; son kaydedilen programlar gösteriliyor."
            }
        }
        guideTasks[item.id] = task; await task.value
    }
    private func cacheGuide(_ programmes: [GuideProgramme], for item: MediaItem) {
        guideCache[item.id] = GuideCacheEntry(programmes: programmes)
        guide[item.id] = programmes; guideDirty = true; persist()
    }
    func catchup(_ programme: GuideProgramme, channel: MediaItem) {
        do {
            guard let source = source(channel), source.kind == .xtream else { throw AuraError.message("Arşivden izleme için Xtream kaynağı gerekli.") }
            let url = try XtreamAddress.catchupURL(server: source.server, credentials: credentials(source.id), item: channel, programme: programme, offsetMinutes: preferences.catchupOffset)
            var recording = channel; recording.kind = .movie; recording.title = programme.title; recording.duration = programme.end.timeIntervalSince(programme.start)
            recording.id = channel.id + ":catchup:\(programme.id)"; play(recording, overrideURL: url)
        } catch { self.error = error.localizedDescription }
    }
    func remind(_ programme: GuideProgramme) async {
        do {
            guard programme.start > Date() else { return }
            let center = UNUserNotificationCenter.current()
            guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw AuraError.message("Sistem Ayarları’ndan Aura bildirimlerine izin ver.") }
            let content = UNMutableNotificationContent(); content.title = programme.title; content.body = "Program birazdan başlıyor."; content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, programme.start.timeIntervalSinceNow - 60), repeats: false)
            try await center.add(UNNotificationRequest(identifier: programme.id, content: content, trigger: trigger)); notice = "Hatırlatıcı eklendi."
        } catch { self.error = error.localizedDescription }
    }
    func verifyPIN(_ pin: String) -> Bool {
        let hash = SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined()
        return hash == Vault.text("parental-pin")
    }
    func setPIN(_ pin: String) throws {
        guard pin.count >= 4, pin.allSatisfy(\.isNumber) else { throw AuraError.message("En az 4 rakamlı bir PIN gir.") }
        try Vault.saveText(SHA256.hash(data: Data(pin.utf8)).map { String(format: "%02x", $0) }.joined(), "parental-pin")
    }
    func chooseSyncFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "Eşitleme klasörü seç"
        panel.message = "iCloud Drive veya başka bir eşitlenen klasör seç. Yalnızca favoriler, adlar ve izleme ilerlemesi paylaşılır. Kaynakları diğer Mac’e ayrıca eklemelisin."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil); try Vault.save(bookmark, account: "sync-folder"); syncFolder = url; _ = url.startAccessingSecurityScopedResource(); syncPersonal() }
        catch { self.error = error.localizedDescription }
    }
    private func restoreSyncFolder() {
        guard let data = try? Vault.read("sync-folder") else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) { syncFolder = url; _ = url.startAccessingSecurityScopedResource() }
    }
    func syncPersonal() {
        guard let syncFolder, !syncInFlight else { return }
        syncInFlight = true
        let url = syncFolder.appendingPathComponent("Aura-personal.json")
        let snapshot = personal
        persistenceQueue.async { [weak self] in
            do {
                var merged = snapshot
                if FileManager.default.fileExists(atPath: url.path) { merged.merge(try JSONDecoder().decode(PersonalLibrary.self, from: Data(contentsOf: url))) }
                try JSONEncoder().encode(merged).write(to: url, options: .atomic)
                let result = merged
                Task { @MainActor [weak self] in
                    guard let self else { return }; self.syncInFlight = false
                    guard self.syncFolder == syncFolder else { return }
                    self.personal.merge(result); self.lastFolderSync = Date(); self.persist()
                }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in self?.syncInFlight = false; self?.error = "Eşitleme başarısız: \(message)" }
            }
        }
    }
    func stopSync() { syncFolder?.stopAccessingSecurityScopedResource(); syncFolder = nil; Vault.remove("sync-folder") }
    private func stableSourceID(_ text: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(text.utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
}

enum Demo {
    static let source = PlaylistSource(id: UUID(uuidString: "00000000-A0A0-4000-8000-000000000001")!, name: "Aura Koleksiyonu", server: "", kind: .demo)
    static let items: [MediaItem] = [
        movie("Sintel · Fragman", file: "Sintel", year: "2010", description: "Bir dostluğun peşinde, bilinmeyene doğru. Blender Studio’nun açık lisanslı fantastik kısa filminin fragmanı. Bu örnek video uygulamayla birlikte gelir; internet olmadan da deneyebilirsin.", category: "Fantastik", length: 52),
        movie("Big Buck Bunny", file: "BigBuckBunny", year: "2008", description: "Ormanın en sakin sakininin beklenmedik macerası. Blender Studio’nun neşeli animasyonu.", category: "Animasyon", length: 596),
        movie("Tears of Steel", file: "TearsOfSteel", year: "2012", description: "İnsanlar, robotlar ve Amsterdam’da bir gelecek hikâyesi. Açık sinemanın sınırlarını keşfet.", category: "Bilim kurgu", length: 734),
        movie("Elephants Dream", file: "ElephantsDream", year: "2006", description: "İki karakter, tuhaf bir makine ve hayal gücünün sınırları. İlk açık kaynak Blender filmi.", category: "Kısa film", length: 653),
        MediaItem(sourceID: source.id, streamID: "apple-hls", kind: .live, title: "HLS Test Yayını", categoryID: "demo", category: "Örnek yayın", artwork: "bundle:mountains", directURL: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")
    ]
    static func movie(_ title: String, file: String, year: String, description: String, category: String, length: Double) -> MediaItem {
        MediaItem(sourceID: source.id, streamID: file, kind: .movie, title: title, categoryID: category, category: category,
                  artwork: "bundle:\(file)", backdrop: "bundle:\(file)", overview: description, year: year, duration: length,
                  directURL: ["Sintel": "bundlevideo:SintelTrailer", "BigBuckBunny": "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8", "TearsOfSteel": "https://download.blender.org/demo/movies/ToS/tears_of_steel_720p.mov", "ElephantsDream": "https://download.blender.org/ED/elephantsdream-720-h264-st-aac.mov"][file])
    }
}

import Foundation
import AuraCore

final class AuraCoreTests {
    let source = UUID(uuidString: "ABCDABCD-1234-4000-8000-000000000001")!
    func testLanguageSelectionAcrossEpisodeTrackOrderChanges() {
        expectEqual(MediaLanguage.canonical("tr,tur,en,eng"), "tr")
        expectEqual(MediaLanguage.canonical("eng-US"), "en")
        expectEqual(MediaLanguage.name("tur"), "Türkçe")
        expectEqual(MediaLanguage.name("eng"), "İngilizce")
        expectEqual(MediaLanguage.preferredIndex(languages: ["tur", "eng"], titles: ["Türkçe", "English"], language: "en", title: nil), 1)
        expectEqual(MediaLanguage.preferredIndex(languages: ["eng", "tur"], titles: ["English", "Türkçe"], language: "en", title: nil), 0)
        expectEqual(MediaLanguage.preferredIndex(languages: ["eng", "eng"], titles: ["Forced", "SDH"], language: "en", title: "SDH"), 1)
        expectNil(MediaLanguage.preferredIndex(languages: ["tur"], titles: ["Türkçe"], language: "en", title: nil))
    }
    func testSearchUsesRenamedTitlesCategoriesAndWhitespace() {
        let first = MediaItem(sourceID: source, streamID: "a", kind: .series, title: "House of the Dragon", category: "Fantastik")
        let second = MediaItem(sourceID: source, streamID: "b", kind: .movie, title: "Film", category: "Bilim kurgu")
        expectEqual(MediaSearch.matchingIDs(in: [first, second], renamed: [:], query: "  DRAGON  "), [first.id])
        expectEqual(MediaSearch.matchingIDs(in: [first, second], renamed: [:], query: "bilim"), [second.id])
        expectEqual(MediaSearch.matchingIDs(in: [first], renamed: [first.id: "Özel ad"], query: "Özel"), [first.id])
        expectTrue(MediaSearch.matchingIDs(in: [first], renamed: [:], query: "  ").isEmpty)
    }

    func testFullXtreamLinkExtractsEncodedCredentialsAndSubdirectory() throws {
        let (server, auth) = try XtreamAddress.parse("https://example.com:8080/sub/get.php?username=a%2Bb&password=p%26%2F%3F&type=m3u_plus")
        expectEqual(server, "https://example.com:8080/sub")
        expectEqual(auth.username, "a+b"); expectEqual(auth.password, "p&/?")
        let url = try XtreamAddress.apiURL(server: server, credentials: auth, action: "get_live_streams")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        expectEqual(query.first { $0.name == "password" }?.value, "p&/?")
        let guide = try XtreamAddress.guideURL(server: server, credentials: auth)
        expectEqual(guide.path, "/sub/xmltv.php")
        expectEqual(URLComponents(url: guide, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "username" }?.value, "a+b")
        expectEqual(URLComponents(url: guide, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "password" }?.value, "p&/?")
    }
    func testMalformedAndMissingCredentialsAreRejected() {
        expectThrows(try XtreamAddress.parse("javascript:alert(1)", username: "x", password: "y"))
        expectThrows(try XtreamAddress.parse("https://example.com"))
        expectThrows(try XtreamAddress.parse("ftp://example.com", username: "x", password: "y"))
    }
    func testStreamPathEscapesCredentialSeparators() throws {
        let item = MediaItem(sourceID: source, streamID: "42", kind: .live, title: "Kanal")
        let url = try XtreamAddress.streamURL(server: "https://example.com/sub", credentials: Credentials(username: "a/b", password: "p?#%"), item: item)
        expectEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath, "/sub/live/a%2Fb/p%3F%23%25/42.m3u8")
        expectNil(url.query); expectNil(url.fragment)
    }
    func testCatchupRejectsUnavailableArchiveAndEncodesDuration() throws {
        var item = MediaItem(sourceID: source, streamID: "8", kind: .live, title: "Arşiv", archiveDays: 2)
        let start = Date().addingTimeInterval(-7200)
        let programme = GuideProgramme(channelID: "8", title: "Program", start: start, end: start.addingTimeInterval(3600))
        let auth = Credentials(username: "u", password: "p")
        let url = try XtreamAddress.catchupURL(server: "https://example.com", credentials: auth, item: item, programme: programme)
        expectTrue(url.path.contains("/timeshift/u/p/60/"))
        item.archiveDays = 0
        expectThrows(try XtreamAddress.catchupURL(server: "https://example.com", credentials: auth, item: item, programme: programme))
    }
    func testCatalogHandlesMixedNumberAndStringFields() {
        let row: [String: Any] = ["stream_id": 42, "name": "Test", "category_id": "5", "rating": "8.2", "tv_archive": "1", "tv_archive_duration": 7, "is_adult": 0]
        let item = XtreamClient.decodeItem(row, kind: .live, sourceID: source, categories: ["5": "Spor"])
        expectEqual(item?.streamID, "42"); expectEqual(item?.category, "Spor")
        expectEqual(item?.rating, 8.2); expectEqual(item?.archiveDays, 7)
        expectNil(XtreamClient.decodeItem(["name": "Eksik"], kind: .live, sourceID: source, categories: [:]))
    }
    func testM3UQuotedCommasRelativeURLsAndStableIDs() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bbc" tvg-logo="https://example.com/logo.png" group-title="News, World",BBC News
        streams/live.m3u8
        #EXTINF:-1 group-title="Sinema",Bir Film
        https://example.com/movie.mp4
        #EXTINF:-1,Geçersiz
        javascript:alert(1)
        """
        let first = M3UParser.parse(text, sourceID: source, baseURL: URL(string: "https://example.com/list.m3u")!)
        let second = M3UParser.parse(text, sourceID: source, baseURL: URL(string: "https://example.com/list.m3u")!)
        expectEqual(first.count, 2); expectEqual(first[0].title, "BBC News"); expectEqual(first[0].category, "News, World")
        expectEqual(first[0].directURL, "https://example.com/streams/live.m3u8"); expectEqual(first[1].kind, .movie)
        expectEqual(first.map(\.id), second.map(\.id))
    }
    func testXMLTVDecodesEntitiesAndTimezone() throws {
        let text = """
        <?xml version="1.0"?><tv><programme channel="test" start="20261102180000 +0300" stop="20261102190000 +0300"><title>Haber &amp; Dünya</title><desc>Günün özeti.</desc></programme><programme channel="test" start="invalid" stop="invalid"><title>Bozuk</title></programme></tv>
        """
        let programmes = try XMLTVParser.parse(Data(text.utf8))
        expectEqual(programmes.count, 1); expectEqual(programmes[0].title, "Haber & Dünya")
        expectEqual(programmes[0].end.timeIntervalSince(programmes[0].start), 3600)
        let formatter = ISO8601DateFormatter()
        expectEqual(formatter.string(from: programmes[0].start), "2026-11-02T15:00:00Z")
    }
    func testSubtitleTimingSupportsSRTAndVTTAndSkipsBadCues() {
        let text = """
        WEBVTT

        1
        00:00:01,250 --> 00:00:03,500
        <i>Merhaba</i>
        Dünya

        00:05.000 --> 00:07.200 align:center
        İkinci satır

        00:10.000 --> 00:09.000
        Hatalı
        """
        let cues = SubtitleParser.parse(text)
        expectEqual(cues.count, 2); expectEqual(cues[0].start, 1.25); expectEqual(cues[0].text, "Merhaba\nDünya")
        expectEqual(cues[1].end, 7.2)
    }
    func testPersonalSyncUsesNewestPerItemAndPreservesOtherItems() {
        var a = PersonalLibrary(), b = PersonalLibrary()
        var old = WatchState(); old.position = 20; old.updatedAt = Date(timeIntervalSince1970: 1)
        var new = old; new.position = 80; new.favorite = true; new.updatedAt = Date(timeIntervalSince1970: 2)
        a.states["first"] = old; a.states["second"] = old
        b.states["first"] = new; b.states["third"] = old
        a.merge(b)
        expectEqual(a.states.count, 3); expectEqual(a.states["first"]?.position, 80); expectEqual(a.states["first"]?.favorite, true)
    }
    func testWatchPositionRoundTripAndCompletionBoundary() throws {
        var state = WatchState()
        state.updatePlayback(position: 960, duration: 1000, at: Date(timeIntervalSince1970: 10))
        expectTrue(state.isInProgress); expectEqual(state.watched, false)
        state.updatePlayback(position: 970, duration: 0, at: Date(timeIntervalSince1970: 11))
        let restored = try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(state))
        expectEqual(restored.position, 970); expectEqual(restored.duration, 1000); expectTrue(restored.isInProgress)
        state.updatePlayback(position: .nan, duration: 1000)
        expectEqual(state.position, 970)
        state.updatePlayback(position: 995, duration: 1000)
        expectTrue(state.watched); expectEqual(state.isInProgress, false); expectEqual(state.displayProgress, 1)
    }
    func testHistoryOrdersFilmsAndEpisodesAndKeepsCompletedItems() {
        let movie = MediaItem(sourceID: source, streamID: "film", kind: .movie, title: "Film", artwork: "https://fixture.invalid/film.jpg")
        let episode = MediaItem(sourceID: source, streamID: "ep", kind: .episode, title: "Bölüm")
        let live = MediaItem(sourceID: source, streamID: "live", kind: .live, title: "Canlı")
        var partial = WatchState(); partial.updatePlayback(position: 960, duration: 1000, at: Date(timeIntervalSince1970: 20))
        var completed = WatchState(); completed.updatePlayback(position: 1000, duration: 1000, at: Date(timeIntervalSince1970: 30))
        let states = [movie.id: partial, episode.id: completed, live.id: completed]
        expectEqual(WatchHistory.recent(in: [movie, live, episode], states: states).map(\.id), [episode.id, movie.id])
        let continuing = WatchHistory.continuing(in: [movie, live, episode], states: states)
        expectEqual(continuing.map(\.id), [movie.id]); expectEqual(continuing.first?.artwork, movie.artwork)
        expectTrue(WatchHistory.recent(in: [movie], states: states, limit: 0).isEmpty)
    }
    func testSeriesResumesLatestEpisodeAndAdvancesAcrossSeasons() {
        let first = MediaItem(sourceID: source, streamID: "1", kind: .episode, title: "İlk", season: 1, episode: 1)
        let second = MediaItem(sourceID: source, streamID: "2", kind: .episode, title: "İkinci", season: 1, episode: 2)
        let third = MediaItem(sourceID: source, streamID: "3", kind: .episode, title: "Yeni sezon", season: 2, episode: 1)
        var completed = WatchState(); completed.updatePlayback(position: 100, duration: 100, at: Date(timeIntervalSince1970: 10))
        var partial = WatchState(); partial.updatePlayback(position: 40, duration: 100, at: Date(timeIntervalSince1970: 20))
        var states = [first.id: completed, second.id: partial]
        expectEqual(WatchHistory.nextEpisode(in: [third, second, first], states: states)?.id, second.id)
        states[second.id]?.updatePlayback(position: 100, duration: 100, at: Date(timeIntervalSince1970: 30))
        expectEqual(WatchHistory.nextEpisode(in: [third, second, first], states: states)?.id, third.id)
        expectNil(WatchHistory.nextEpisode(in: [], states: states))
    }
    func testGuideCacheSurvivesRoundTripAndRefreshesExpiredProgrammes() throws {
        let now = Date(timeIntervalSince1970: 10000)
        let programme = GuideProgramme(channelID: "channel", title: "Kayıtlı program", start: now.addingTimeInterval(-60), end: now.addingTimeInterval(3600))
        let cache = GuideCacheEntry(programmes: [programme], fetchedAt: now)
        let restored = try JSONDecoder().decode(GuideCacheEntry.self, from: JSONEncoder().encode(cache))
        expectEqual(restored.programmes, [programme]); expectEqual(restored.fetchedAt, now)
        expectEqual(restored.needsRefresh(at: now.addingTimeInterval(60)), false)
        expectTrue(restored.needsRefresh(at: now.addingTimeInterval(1800)))
        let ended = GuideCacheEntry(programmes: [programme], fetchedAt: now.addingTimeInterval(3590))
        expectTrue(ended.needsRefresh(at: now.addingTimeInterval(3601)))
        let empty = GuideCacheEntry(programmes: [], fetchedAt: now)
        expectEqual(empty.needsRefresh(at: now.addingTimeInterval(30)), false)
        expectTrue(empty.needsRefresh(at: now.addingTimeInterval(-1)))
    }
    func testXtreamAuthenticationCatalogEpisodesAndGuideUsingTransportFixture() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]
        let client = XtreamClient(source: PlaylistSource(id: source, name: "Fixture", server: "https://fixture.invalid"), credentials: Credentials(username: "user", password: "pass"), session: URLSession(configuration: config))
        let library = try await client.load()
        expectEqual(library.items.count, 3); expectEqual(library.source.connectionLimit, 2)
        let live = try unwrap(library.items.first { $0.kind == .live })
        let guide = try await client.guide(live)
        expectEqual(guide.first?.title, "Türkçe haber")
        let series = try unwrap(library.items.first { $0.kind == .series })
        let episodes = try await client.episodes(series)
        expectEqual(episodes.count, 2); expectEqual(episodes.first?.episode, 1); expectEqual(episodes.first?.fileExtension, "mkv")
    }
    func testOpenSubtitlesNeverSendsCredentialsToUntrustedHost() async {
        let client = OpenSubtitlesClient(apiKey: "secret", session: SubtitleSession(token: "token", baseURL: "attacker.invalid"))
        do { _ = try await client.search(query: "film", language: "tr"); fail("Untrusted host accepted") }
        catch { expectTrue(error.localizedDescription.contains("sunucu adresi")) }
    }
}

final class FixtureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let action = query.first { $0.name == "action" }?.value ?? "auth"
        let value: Any
        switch action {
        case "auth": value = ["user_info": ["auth": 1, "status": "Active", "max_connections": "2", "exp_date": "1800000000"]]
        case "get_live_categories", "get_vod_categories", "get_series_categories": value = [["category_id": 1, "category_name": "Test"]]
        case "get_live_streams": value = [["stream_id": 10, "name": "Canlı", "category_id": "1"]]
        case "get_vod_streams": value = [["stream_id": "20", "name": "Film", "category_id": 1, "container_extension": "mkv"]]
        case "get_series": value = [["series_id": 30, "name": "Dizi", "category_id": "1"]]
        case "get_series_info": value = ["episodes": ["1": [["id": "32", "title": "İkinci", "episode_num": 2, "container_extension": "mp4"], ["id": "31", "title": "İlk", "episode_num": "1", "container_extension": "mkv"]]]]
        case "get_simple_data_table": value = ["epg_listings": [["title": Data("Türkçe haber".utf8).base64EncodedString(), "description": "", "start_timestamp": "1793631600", "stop_timestamp": 1793635200]]]
        default: value = [:]
        }
        let data = try! JSONSerialization.data(withJSONObject: value)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

struct CheckFailure: Error { let message: String }
var failures: [String] = []
func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) { failures.append("\(file):\(line): \(message)") }
func expectEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { fail("Expected \(b), got \(a)", file: file, line: line) } }
func expectTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { fail("Expected true", file: file, line: line) } }
func expectNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) { if value != nil { fail("Expected nil", file: file, line: line) } }
func expectThrows<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try value(); fail("Expected an error", file: file, line: line) } catch {} }
func unwrap<T>(_ value: T?) throws -> T { guard let value else { throw CheckFailure(message: "Expected a value") }; return value }
@main struct AuraCoreChecks {
    static func main() async {
        let tests = AuraCoreTests()
        let synchronous: [(String, () throws -> Void)] = [
            ("Language preference across episodes", tests.testLanguageSelectionAcrossEpisodeTrackOrderChanges),
            ("Search matching", tests.testSearchUsesRenamedTitlesCategoriesAndWhitespace),
            ("Xtream credential parsing", tests.testFullXtreamLinkExtractsEncodedCredentialsAndSubdirectory),
            ("Invalid addresses", tests.testMalformedAndMissingCredentialsAreRejected),
            ("Stream path escaping", tests.testStreamPathEscapesCredentialSeparators),
            ("Catch-up validity", tests.testCatchupRejectsUnavailableArchiveAndEncodesDuration),
            ("Mixed catalog types", tests.testCatalogHandlesMixedNumberAndStringFields),
            ("M3U parsing", tests.testM3UQuotedCommasRelativeURLsAndStableIDs),
            ("XMLTV times and entities", tests.testXMLTVDecodesEntitiesAndTimezone),
            ("Subtitle timing", tests.testSubtitleTimingSupportsSRTAndVTTAndSkipsBadCues),
            ("Personal library merge", tests.testPersonalSyncUsesNewestPerItemAndPreservesOtherItems),
            ("Resume persistence and completion", tests.testWatchPositionRoundTripAndCompletionBoundary),
            ("Recent and continuing history", tests.testHistoryOrdersFilmsAndEpisodesAndKeepsCompletedItems),
            ("Series resume and next season", tests.testSeriesResumesLatestEpisodeAndAdvancesAcrossSeasons),
            ("Persistent EPG and refresh timing", tests.testGuideCacheSurvivesRoundTripAndRefreshesExpiredProgrammes)
        ]
        for (name, run) in synchronous {
            let count = failures.count
            do { try run() } catch { fail("\(name): \(error)") }
            print("\(failures.count == count ? "PASS" : "FAIL") \(name)")
        }
        do { try await tests.testXtreamAuthenticationCatalogEpisodesAndGuideUsingTransportFixture(); print("PASS Xtream transport integration") } catch { fail("Xtream fixture: \(error)") }
        await tests.testOpenSubtitlesNeverSendsCredentialsToUntrustedHost()
        print("PASS OpenSubtitles host validation")
        if failures.isEmpty { print("17 checks passed.") }
        else { failures.forEach { print("FAIL: \($0)") }; exit(1) }
    }
}

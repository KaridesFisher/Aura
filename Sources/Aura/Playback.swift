import SwiftUI
import AppKit
import AVKit
import OpenGL
import CMPV
import AuraCore
import IOKit.pwr_mgt
import UniformTypeIdentifiers

// The C callback owns no view and never calls GL or the synchronous mpv API.
// This bridge outlives every surface and stays alive until mpv is destroyed.
final class VideoRenderEvents {
    private let lock = NSLock()
    private var source: DispatchSourceUserDataAdd?
    func connect(_ source: DispatchSourceUserDataAdd?) { lock.lock(); self.source = source; lock.unlock() }
    func signal() { lock.lock(); source?.add(data: 1); lock.unlock() }
}

final class VideoRenderMeter {
    private let lock = NSLock()
    private var frames = 0
    private var longest = 0.0
    private var since = ProcessInfo.processInfo.systemUptime
    func record(milliseconds: Double) {
        lock.lock(); frames += 1; longest = max(longest, milliseconds); lock.unlock()
    }
    func snapshot() -> (fps: Double, longest: Double) {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let value = (Double(frames) / max(0.001, now - since), longest)
        frames = 0; longest = 0; since = now
        return value
    }
}

final class MPVSession {
    let handle: OpaquePointer
    var renderContext: NSOpenGLContext?
    weak var surface: MPVOpenGLView?
    let renderMeter = VideoRenderMeter()
    let renderEvents = VideoRenderEvents()
    static var libraryPath: String {
        if let path = ProcessInfo.processInfo.environment["AURA_MPV_LIBRARY"] { return path }
        return Bundle.main.privateFrameworksURL?.appendingPathComponent("libmpv.2.dylib").path ?? "libmpv.2.dylib"
    }
    init(recorder: Bool = false) throws {
        let result = recorder ? aura_mpv_create_recorder(Self.libraryPath) : aura_mpv_create(Self.libraryPath)
        guard let result else { throw AuraError.message("mpv oynatma altyapısı açılamadı. Uygulamayı paketlenmiş Aura.app üzerinden başlat.") }
        handle = result
        if !recorder {
            let attributes: [NSOpenGLPixelFormatAttribute] = [UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core), UInt32(NSOpenGLPFADoubleBuffer), UInt32(NSOpenGLPFAAccelerated), 0]
            guard let format = NSOpenGLPixelFormat(attributes: attributes), let context = NSOpenGLContext(format: format, share: nil) else {
                throw AuraError.message("Mac’in grafik bağlamı oluşturulamadı.")
            }
            renderContext = context; context.makeCurrentContext()
            guard aura_mpv_init_gl(handle) >= 0 else { throw AuraError.message("Video çizim altyapısı başlatılamadı.") }
            aura_mpv_set_render_callback(handle, { context in
                guard let context else { return }
                Unmanaged<VideoRenderEvents>.fromOpaque(context).takeUnretainedValue().signal()
            }, Unmanaged.passUnretained(renderEvents).toOpaque())
        }
    }
    deinit { renderContext?.makeCurrentContext(); aura_mpv_destroy(handle) }
    func command(_ args: String...) { command(args) }
    func command(_ args: [String]) {
        let pointers = args.map { strdup($0) }
        defer { pointers.forEach { free($0) } }
        let converted: [UnsafePointer<CChar>?] = pointers.map { $0.map { UnsafePointer($0) } } + [nil]
        converted.withUnsafeBufferPointer { _ = aura_mpv_command(handle, $0.baseAddress!) }
    }
    func set(_ name: String, _ value: String) { _ = aura_mpv_set_string(handle, name, value) }
    func number(_ name: String) -> Double { aura_mpv_get_number(handle, name) }
    func string(_ name: String) -> String {
        guard let pointer = aura_mpv_get_string(handle, name) else { return "" }
        defer { aura_mpv_free_string(handle, pointer) }; return String(cString: pointer)
    }
}

struct MediaTrack: Identifiable, Equatable {
    let id: Int
    let type: String
    let title: String
    let language: String
    let selected: Bool
    var displayName: String {
        let name = MediaLanguage.name(language)
        if title.isEmpty { return name == "Bilinmeyen dil" ? "\(type == "audio" ? "Ses" : "Altyazı") \(id)" : name }
        return name == "Bilinmeyen dil" ? title : "\(name) · \(title)"
    }
}

@MainActor final class PlaybackController: ObservableObject {
    weak var store: LibraryStore?
    @Published var current: MediaItem?
    @Published var openSequence = 0
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var isPlaying = false
    @Published var buffering = false
    @Published var playbackError: String?
    @Published var retryCount = 0
    @Published var volume = UserDefaults.standard.object(forKey: "player-volume") as? Double ?? 0.0
    @Published var rate = 1.0
    @Published var tracks: [MediaTrack] = []
    @Published var subtitleDelay = 0.0
    @Published var subtitleName: String?
    @Published var showSubtitles = false
    @Published var showStats = false
    @Published var stats = ""
    @Published var sleepUntil: Date?
    @Published var isMini = false
    @Published var isFullscreen = false
    @Published var nativeMode = false
    let nativePlayer = AVPlayer()
    var session: MPVSession?
    var streamURL: URL?
    weak var window: NSWindow?
    private var timer: Timer?
    private var resumeAt = 0.0
    private var tick = 0
    private var failed = false
    private var autoNextFired = false
    private var retryTask: Task<Void, Never>?
    private var assertion: IOPMAssertionID = 0
    private var hasAssertion = false
    private var triedTS = false
    private var mediaReady = false
    private var restoreAudio = false
    private var restoreSubtitle = false

    init() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.update() } }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func play(_ item: MediaItem, url: URL, resume: Double = 0) {
        if let current { scrobble("stop"); store?.saveProgress(current, position: position, duration: duration) }
        retryTask?.cancel(); nativePlayer.pause(); nativePlayer.replaceCurrentItem(with: nil); nativeMode = false
        do { if session == nil { session = try MPVSession() } }
        catch { store?.error = error.localizedDescription; return }
        current = item; streamURL = url; position = resume; duration = item.duration ?? 0; mediaReady = false
        resumeAt = resume; retryCount = 0; playbackError = nil; failed = false; autoNextFired = false; triedTS = false
        tracks = []; subtitleName = nil; subtitleDelay = 0; rate = 1
        restoreAudio = true; restoreSubtitle = true
        session?.set("volume", String(volume)); session?.set("speed", "1"); session?.set("pause", "no")
        session?.set("slang", MediaLanguage.mpvCodes(store?.preferences.subtitleLanguage ?? "tr"))
        session?.set("alang", MediaLanguage.mpvCodes(store?.preferences.audioLanguage ?? "tr"))
        session?.set("aid", "auto")
        session?.set("sid", store?.preferences.subtitlesEnabled == false ? "no" : "auto")
        session?.set("sub-font-size", String(store?.preferences.subtitleSize ?? 42))
        session?.set("user-agent", store?.preferences.userAgent ?? "Aura/1.0")
        session?.set("sub-delay", "0"); session?.set("sub-visibility", "yes")
        configureBuffering(for: item)
        session?.command("loadfile", url.absoluteString, "replace")
        isPlaying = true; buffering = true; openSequence += 1; preventSleep(true)
    }
    private func configureBuffering(for item: MediaItem) {
        let options = item.kind == .live
            ? (store?.preferences.livePlaybackMode ?? .lowLatency).mpvOptions
            : LivePlaybackMode.onDemandOptions
        for (name, value) in options { session?.set(name, value) }
    }
    private func nativeItem(url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        if current?.kind == .live {
            let mode = store?.preferences.livePlaybackMode ?? .lowLatency
            item.preferredForwardBufferDuration = mode.bufferSeconds
            nativePlayer.automaticallyWaitsToMinimizeStalling = mode != .lowLatency
        } else {
            nativePlayer.automaticallyWaitsToMinimizeStalling = true
        }
        return item
    }
    func applyLivePlaybackPreference() {
        guard current?.kind == .live else { return }
        // Preserve a deliberate pause; resume applies the new policy on reconnect.
        if !isPlaying { return }
        if nativeMode, let streamURL {
            nativePlayer.replaceCurrentItem(with: nativeItem(url: streamURL))
            nativePlayer.play()
        } else { restart() }
    }
    func togglePause() {
        guard let current else { return }
        if !isPlaying, current.kind == .live, let streamURL {
            // Reopen the live endpoint, discarding the paused demuxer buffer.
            // Seeking to a buffered timestamp can leave HLS/TS behind live.
            retryTask?.cancel(); retryCount = 0; failed = false; playbackError = nil
            resumeAt = 0; position = 0; duration = 0; mediaReady = false
            autoNextFired = false; buffering = true; isPlaying = true
            restoreAudio = true; restoreSubtitle = true
            configureBuffering(for: current)
            if nativeMode {
                nativePlayer.replaceCurrentItem(with: nativeItem(url: streamURL))
                nativePlayer.play()
            } else {
                session?.command("loadfile", streamURL.absoluteString, "replace")
                session?.set("pause", "no")
            }
            preventSleep(true)
            return
        }
        isPlaying.toggle()
        if nativeMode { isPlaying ? nativePlayer.play() : nativePlayer.pause() }
        else { session?.set("pause", isPlaying ? "no" : "yes") }
        preventSleep(isPlaying)
        if !isPlaying { store?.saveProgress(current, position: position, duration: duration) }
        scrobble(isPlaying ? "start" : "pause")
    }
    func pause() { if isPlaying { togglePause() } }
    func seek(_ seconds: Double, relative: Bool = false) {
        if nativeMode { nativePlayer.seek(to: CMTime(seconds: max(0, relative ? position + seconds : seconds), preferredTimescale: 600)) }
        else { session?.command("seek", String(seconds), relative ? "relative+exact" : "absolute+exact") }
    }
    func skip(forward: Bool) {
        seek(Double(store?.preferences.seekStep ?? 10) * (forward ? 1 : -1), relative: true)
    }
    func setVolume(_ value: Double) { volume = value; UserDefaults.standard.set(value, forKey: "player-volume"); session?.set("volume", String(value)); nativePlayer.volume = Float(value / 100) }
    func setRate(_ value: Double) { rate = value; session?.set("speed", String(value)); if nativeMode && isPlaying { nativePlayer.rate = Float(value) } }
    func setSubtitleDelay(_ value: Double) { subtitleDelay = value; session?.set("sub-delay", String(value)) }
    func selectTrack(_ track: MediaTrack) {
        session?.set(track.type == "audio" ? "aid" : "sid", String(track.id))
        let language = MediaLanguage.canonical(track.language)
        if track.type == "audio" {
            restoreAudio = false
            if !language.isEmpty && language != "und" { store?.preferences.audioLanguage = language }
            store?.preferences.preferredAudioTitle = track.title
        } else {
            restoreSubtitle = false; session?.set("sub-visibility", "yes")
            store?.preferences.subtitlesEnabled = true
            if !language.isEmpty && language != "und" { store?.preferences.subtitleLanguage = language }
            store?.preferences.preferredSubtitleTitle = track.title
        }
        store?.persist(); updateTracks()
    }
    func disableSubtitles() {
        restoreSubtitle = false; session?.set("sid", "no"); subtitleName = nil
        store?.preferences.subtitlesEnabled = false; store?.persist(); updateTracks()
    }
    func addSubtitle(_ url: URL, name: String? = nil) {
        restoreSubtitle = false; store?.preferences.subtitlesEnabled = true; store?.persist()
        session?.command("sub-add", url.path, "select"); subtitleName = name ?? url.lastPathComponent; updateTracks()
    }
    func importSubtitle() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = ["srt", "vtt", "ass", "ssa", "sub"].compactMap { UTType(filenameExtension: $0) }
        // Do not nest a blocking modal loop inside SwiftUI's subtitle sheet.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addSubtitle(url)
        }
    }
    func restart() {
        guard let item = current, let url = streamURL else { return }
        play(item, url: url, resume: item.kind == .live ? 0 : position)
    }
    func close() {
        if let current { scrobble("stop"); store?.saveProgress(current, position: position, duration: duration) }
        retryTask?.cancel(); session?.command("stop"); nativePlayer.pause(); nativePlayer.replaceCurrentItem(with: nil)
        current = nil; isPlaying = false; buffering = false; preventSleep(false)
    }
    func toggleMini() {
        guard let window else { return }
        isMini.toggle(); window.level = isMini ? .floating : .normal
        window.collectionBehavior = isMini ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.managed]
        window.setContentSize(isMini ? NSSize(width: 540, height: 360) : NSSize(width: 1120, height: 730))
    }
    func toggleFullscreen() {
        if isMini { toggleMini() }
        guard let target = window ?? NSApp.windows.first(where: { $0.title.contains("Oynatıcı") }) else { return }
        target.styleMask.insert(.resizable)
        target.collectionBehavior.remove(.fullScreenNone)
        target.collectionBehavior.remove(.fullScreenAuxiliary)
        target.collectionBehavior.insert(.fullScreenPrimary)
        target.toggleFullScreen(nil)
    }
    func enableNativeMode() {
        guard let streamURL else { return }
        session?.set("pause", "yes"); nativeMode = true
        nativePlayer.replaceCurrentItem(with: nativeItem(url: streamURL)); nativePlayer.allowsExternalPlayback = true
        nativePlayer.volume = Float(volume / 100)
        if current?.kind != .live { nativePlayer.seek(to: CMTime(seconds: position, preferredTimescale: 600)) }
        nativePlayer.play(); isPlaying = true
    }
    func disableNativeMode() {
        let time = nativePlayer.currentTime().seconds; nativePlayer.pause(); nativeMode = false
        if time.isFinite { seek(time) }; session?.set("pause", "no"); isPlaying = true
    }
    private func preventSleep(_ value: Bool) {
        if value && !hasAssertion { hasAssertion = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "Aura oynatılıyor" as CFString, &assertion) == kIOReturnSuccess }
        else if !value && hasAssertion { IOPMAssertionRelease(assertion); hasAssertion = false }
    }
    private func update() {
        guard let current else { return }
        tick += 1
        if let sleepUntil, Date() >= sleepUntil { pause(); self.sleepUntil = nil }
        if nativeMode {
            let p = nativePlayer.currentTime().seconds, d = nativePlayer.currentItem?.duration.seconds ?? 0
            if p.isFinite { position = p }; if d.isFinite && d > 0 { duration = d }
            isPlaying = nativePlayer.rate > 0; buffering = nativePlayer.timeControlStatus == .waitingToPlayAtSpecifiedRate
            if nativePlayer.currentItem?.status == .failed { playbackError = "Apple oynatıcısı bu akışı açamadı. mpv moduna geri dön."; buffering = false }
        } else if let session {
            let event = aura_mpv_poll(session.handle)
            if event == 2 {
                failed = false; mediaReady = true; playbackError = nil; retryTask?.cancel()
                if resumeAt > 0 { seek(resumeAt); resumeAt = 0 }
                updateTracks()
                scrobble("start")
            }
            if event == -1 && !failed { failed = true; handleFailure() }
            let p = session.number("time-pos"), d = session.number("duration")
            if mediaReady && p.isFinite { position = p }; if mediaReady && d.isFinite && d > 0 { duration = d }
            buffering = !failed && (!mediaReady || session.string("paused-for-cache") == "yes")
            if !failed { isPlaying = session.string("pause") != "yes" }
            if tick % 4 == 0 { updateTracks() }
            let eof = session.string("eof-reached") == "yes"
            if eof { isPlaying = false; preventSleep(false); if !autoNextFired { autoNextFired = true; scrobble("stop"); playNextEpisode() } }
            if showStats && tick % 4 == 0 {
                let codec = session.string("video-codec"), width = Int(session.number("width")), height = Int(session.number("height"))
                let rendering = session.renderMeter.snapshot()
                stats = "\(width) × \(height) · \(String(format: "%.2f", session.number("container-fps"))) fps\n\(codec) · \(session.string("hwdec-current"))\nÖnbellek: \(String(format: "%.1f", session.number("demuxer-cache-duration"))) sn\nDüşen kare: \(Int(session.number("frame-drop-count")))\nÇizilen: \(String(format: "%.1f", rendering.fps)) kare/sn · en uzun \(String(format: "%.1f", rendering.longest)) ms"
            }
        }
        if tick % 20 == 0 && (nativeMode ? nativePlayer.currentItem?.status == .readyToPlay : mediaReady) { store?.saveProgress(current, position: position, duration: duration) }
    }
    private func updateTracks() {
        guard let session else { return }
        let count = min(100, max(0, Int(session.number("track-list/count"))))
        let result = (0..<count).map { i in
            MediaTrack(id: Int(session.number("track-list/\(i)/id")), type: session.string("track-list/\(i)/type"),
                       title: session.string("track-list/\(i)/title"), language: session.string("track-list/\(i)/lang"),
                       selected: session.string("track-list/\(i)/selected") == "yes")
        }
        if result != tracks { tracks = result }
        guard mediaReady, let preferences = store?.preferences else { return }
        for type in ["audio", "sub"] {
            guard type == "audio" ? restoreAudio : restoreSubtitle else { continue }
            if type == "sub" && preferences.subtitlesEnabled == false {
                session.set("sid", "no"); restoreSubtitle = false; continue
            }
            let candidates = result.filter { $0.type == type }
            if let index = MediaLanguage.preferredIndex(languages: candidates.map(\.language), titles: candidates.map(\.title), language: type == "audio" ? preferences.audioLanguage : preferences.subtitleLanguage, title: type == "audio" ? preferences.preferredAudioTitle : preferences.preferredSubtitleTitle) {
                session.set(type == "audio" ? "aid" : "sid", String(candidates[index].id))
                if type == "audio" { restoreAudio = false }
                else { restoreSubtitle = false; session.set("sub-visibility", "yes") }
            }
        }
    }
    private func handleFailure() {
        guard let current, let url = streamURL else { return }
        buffering = false
        if current.kind == .live, !triedTS, url.pathExtension == "m3u8", url.path.contains("/live/") {
            triedTS = true; let fallback = url.deletingPathExtension().appendingPathExtension("ts"); streamURL = fallback
            configureBuffering(for: current)
            session?.command("loadfile", fallback.absoluteString, "replace"); failed = false; buffering = true; return
        }
        guard store?.preferences.autoReconnect == true, retryCount < 3 else {
            playbackError = "Yayın açılamadı. Sağlayıcının bağlantı sınırını ve internet bağlantını kontrol edip yeniden dene."
            isPlaying = false; preventSleep(false); return
        }
        retryCount += 1; playbackError = "Bağlantı yenileniyor… (\(retryCount)/3)"
        let delay = pow(2.0, Double(retryCount))
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay)); guard !Task.isCancelled, let self else { return }
            self.resumeAt = current.kind == .live ? 0 : self.position
            self.failed = false; self.mediaReady = false; self.buffering = true; self.configureBuffering(for: current)
            self.session?.command("loadfile", url.absoluteString, "replace")
        }
    }
    func playNextEpisode() {
        guard let current, current.kind == .episode, let store, store.preferences.autoNext else { return }
        let episodes = store.items.filter { $0.sourceID == current.sourceID && $0.seriesID == current.seriesID && $0.kind == .episode }
            .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
        if let i = episodes.firstIndex(where: { $0.id == current.id }), i + 1 < episodes.count { store.play(episodes[i + 1]) }
    }
    private func scrobble(_ event: String) {
        guard let current, let store else { return }
        let show = store.items.first { $0.sourceID == current.sourceID && $0.kind == .series && $0.streamID == current.seriesID }
        store.trakt.track(event, item: current, progress: duration > 0 ? position / duration * 100 : 0, seriesTMDB: show?.tmdbID)
    }
}

final class MPVOpenGLView: NSOpenGLView {
    let session: MPVSession
    private let renderQueue = DispatchQueue(label: "dev.aura.video-render", qos: .userInteractive)
    private let stateLock = NSLock()
    private let renderQueueKey = DispatchSpecificKey<Bool>()
    private var frameTimer: DispatchSourceTimer?
    private var displaySignal: DispatchSourceUserDataAdd?
    private var renderSize = NSSize.zero
    private var active = false
    private var forceFrame = true
    init?(session: MPVSession) {
        self.session = session
        renderQueue.setSpecific(key: renderQueueKey, value: true)
        let attributes: [NSOpenGLPixelFormatAttribute] = [UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core), UInt32(NSOpenGLPFADoubleBuffer), UInt32(NSOpenGLPFAAccelerated), 0]
        super.init(frame: .zero, pixelFormat: NSOpenGLPixelFormat(attributes: attributes))
        openGLContext = session.renderContext
        wantsBestResolutionOpenGLSurface = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func prepareOpenGL() {
        super.prepareOpenGL()
        attachSurface()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { tearDown() }
        else { attachSurface() }
    }
    private func attachSurface() {
        guard window != nil, let context = openGLContext, let cgl = context.cglContextObj else { return }
        // A reused session does not guarantee another prepareOpenGL callback.
        // Drain the previous view before assigning its context to this drawable.
        if let previous = session.surface, previous !== self { previous.tearDown() }
        session.surface = self
        CGLLockContext(cgl)
        context.view = self
        context.update()
        context.makeCurrentContext()
        var interval: GLint = 0; context.setValues(&interval, for: .swapInterval)
        let ready = aura_mpv_init_gl(session.handle) >= 0
        NSOpenGLContext.clearCurrentContext()
        CGLUnlockContext(cgl)
        stateLock.lock()
        active = ready; renderSize = convertToBacking(bounds).size; forceFrame = true
        stateLock.unlock()
        guard displaySignal == nil, ready else { return }
        let signal = DispatchSource.makeUserDataAddSource(queue: renderQueue)
        signal.setEventHandler { [weak self] in self?.renderFrame() }
        signal.resume()
        displaySignal = signal
        session.renderEvents.connect(signal)
        signal.add(data: 1)
        // A slow heartbeat recovers a missed notification without using a
        // display-link frequency as a ceiling for video frame delivery.
        let timer = DispatchSource.makeTimerSource(queue: renderQueue)
        timer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in self?.renderFrame() }
        frameTimer = timer; timer.resume()
    }
    private func renderFrame() {
        stateLock.lock()
        let enabled = active, size = renderSize, force = forceFrame
        forceFrame = false
        stateLock.unlock()
        guard enabled, size.width > 0, size.height > 0,
              let context = session.renderContext, let cgl = context.cglContextObj else { return }
        autoreleasepool {
            let started = ProcessInfo.processInfo.systemUptime
            CGLLockContext(cgl)
            defer { NSOpenGLContext.clearCurrentContext(); CGLUnlockContext(cgl) }
            context.makeCurrentContext()
            let pending = aura_mpv_needs_frame(session.handle) != 0
            if pending || force {
                // libmpv may leave internal framebuffer bindings behind.
                // This view owns the window's default drawable.
                aura_mpv_render_window(session.handle, Int32(size.width), Int32(size.height))
                context.flushBuffer(); aura_mpv_report_swap(session.handle)
                session.renderMeter.record(milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000)
            }
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        stateLock.lock(); renderSize = convertToBacking(bounds).size; forceFrame = true; stateLock.unlock()
        displaySignal?.add(data: 1)
    }
    override func reshape() {
        if let cgl = openGLContext?.cglContextObj {
            CGLLockContext(cgl); super.reshape(); CGLUnlockContext(cgl)
        } else { super.reshape() }
        stateLock.lock(); renderSize = convertToBacking(bounds).size; forceFrame = true; stateLock.unlock()
        displaySignal?.add(data: 1)
    }
    func tearDown() {
        stateLock.lock(); active = false; stateLock.unlock()
        if session.surface === self { session.renderEvents.connect(nil) }
        displaySignal?.cancel(); displaySignal = nil
        frameTimer?.cancel(); frameTimer = nil
        // No queued render may outlive its drawable or race with the next view.
        if DispatchQueue.getSpecific(key: renderQueueKey) == nil { renderQueue.sync {} }
        if let context = openGLContext, context.view === self, let cgl = context.cglContextObj {
            CGLLockContext(cgl); context.clearDrawable(); CGLUnlockContext(cgl)
        }
        if session.surface === self { session.surface = nil }
    }
    deinit { tearDown() }
}

struct MPVSurface: NSViewRepresentable {
    let session: MPVSession
    func makeNSView(context: Context) -> NSView { MPVOpenGLView(session: session) ?? NSTextField(labelWithString: "Grafik yüzeyi açılamadı. Menüden Apple oynatıcıyı seçebilirsin.") }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? MPVOpenGLView)?.tearDown() }
}

struct NativeVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView(); view.player = player; view.controlsStyle = .none; view.allowsPictureInPicturePlayback = true
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { view.player = player }
}

struct RoutePicker: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.player = player; return view }
    func updateNSView(_ view: AVRoutePickerView, context: Context) { view.player = player }
}

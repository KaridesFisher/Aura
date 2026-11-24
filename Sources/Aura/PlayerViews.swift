import SwiftUI
import AuraCore
import AVKit

struct WindowReader: NSViewRepresentable {
    var resolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> WindowProbe { WindowProbe(resolve: resolve) }
    func updateNSView(_ view: WindowProbe, context: Context) { view.resolve = resolve; view.resolveIfNeeded() }
}

final class WindowProbe: NSView {
    var resolve: (NSWindow) -> Void
    private weak var configuredWindow: NSWindow?
    init(resolve: @escaping (NSWindow) -> Void) { self.resolve = resolve; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); resolveIfNeeded() }
    func resolveIfNeeded() {
        guard let window, window !== configuredWindow else { return }
        configuredWindow = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window, self.window === window else { return }; self.resolve(window)
        }
    }
}

struct PlayerScreen: View {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject var player: PlaybackController
    @State private var scrubbing = false
    @State private var seekPosition = 0.0
    @State private var recording = false
    @State private var controlsVisible = false
    @State private var hideControlsTask: Task<Void, Never>?
    var body: some View {
        ZStack {
          Color.black
          VStack(spacing: 0) {
            if let item = player.current {
                ZStack {
                    Color.black
                    if player.nativeMode { NativeVideoSurface(player: player.nativePlayer) }
                    else if let session = player.session { MPVSurface(session: session) }
                    // Capture clicks above both mpv and AVPlayer without hover UI.
                    Color.clear.contentShape(Rectangle()).onTapGesture { videoTapped() }
                    if player.buffering && player.playbackError == nil {
                        VStack(spacing: 15) { ProgressView().controlSize(.large).tint(AuraTheme.accent); Text("Yayın hazırlanıyor").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)) }.padding(25).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let error = player.playbackError {
                        VStack(spacing: 17) {
                            Image(systemName: player.retryCount < 3 ? "arrow.triangle.2.circlepath" : "wifi.exclamationmark").font(.system(size: 26, weight: .light)).foregroundStyle(AuraTheme.accent)
                            Text(error).font(.system(size: 12)).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 380)
                            Button("Yeniden dene") { player.restart() }.buttonStyle(AccentButton(compact: true))
                        }.padding(30).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 13))
                    }
                    if player.showStats { VStack { HStack { Text(player.stats).font(.system(size: 11, design: .monospaced)).lineSpacing(5).padding(15).background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8)); Spacer() }; Spacer() }.padding(20).allowsHitTesting(false) }
                }.onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            if let url { Task { @MainActor in if ["srt", "vtt", "ass", "ssa", "sub"].contains(url.pathExtension.lowercased()) { player.addSubtitle(url) } } }
                        }; return true
                    }
            } else { EmptyState(icon: "play.rectangle", title: "Bir hikâye seç.", message: "Kitaplığından bir içerik seçtiğinde burada oynatılır.") }
          }
          if let item = player.current, controlsVisible {
              VStack(spacing: 0) {
                  playerHeader(item).background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
                  Spacer()
                  playerControls(item).background(LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
              }.transition(.opacity)
          }
        }.background(AuraTheme.background).foregroundStyle(AuraTheme.text).tint(AuraTheme.accent).frame(minWidth: 500, minHeight: 340)
            .onChange(of: player.isPlaying) { _, _ in scheduleControlsHide() }
            .onChange(of: player.isFullscreen) { _, _ in scheduleControlsHide() }
            .onChange(of: player.showSubtitles) { _, _ in scheduleControlsHide() }
            .onChange(of: recording) { _, _ in scheduleControlsHide() }
            .background(WindowReader { window in
                window.tabbingMode = .disallowed
                player.window = window; window.minSize = NSSize(width: 500, height: 340)
                window.styleMask.insert(.resizable)
                if !player.isMini { window.collectionBehavior.remove(.fullScreenNone); window.collectionBehavior.insert(.fullScreenPrimary) }
            })
            .sheet(isPresented: $player.showSubtitles) { SubtitleSheet(player: player).environmentObject(store) }
            .sheet(isPresented: $recording) { if let item = player.current { RecordingSheet(item: item).environmentObject(store) } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
                if let window = notification.object as? NSWindow, window === player.window { player.isFullscreen = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
                if let window = notification.object as? NSWindow, window === player.window { player.isFullscreen = false }
            }
            .onDisappear { hideControlsTask?.cancel() }
    }
    private func videoTapped() {
        if controlsVisible { player.togglePause() }
        else { controlsVisible = true }
        scheduleControlsHide()
    }
    private func scheduleControlsHide() {
        hideControlsTask?.cancel()
        guard controlsVisible, player.isPlaying, !player.showSubtitles, !recording else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
        }
    }
    private func playerHeader(_ item: MediaItem) -> some View {
        HStack(spacing: 13) {
            IconButton(icon: "chevron.left", help: "Kitaplığa dön") {
                player.pause()
                if player.isMini { player.toggleMini() }
                store.playerPresented = false
            }
            Image(systemName: "waveform").foregroundStyle(AuraTheme.accent).font(.system(size: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.title(item)).font(.system(size: player.isMini ? 11 : 13, weight: .medium)).lineLimit(1)
                if !player.isMini { Text(item.kind == .episode ? "\(item.season ?? 1). sezon · \(item.episode ?? 1). bölüm" : item.category).font(.system(size: 10)).foregroundStyle(AuraTheme.muted).lineLimit(1) }
            }
            Spacer()
            if player.nativeMode { RoutePicker(player: player.nativePlayer).frame(width: 30, height: 30) }
            if item.kind == .live { HStack(spacing: 5) { Circle().fill(AuraTheme.accent).frame(width: 5, height: 5); Text("CANLI").tracking(1.5) }.font(.system(size: 8, weight: .semibold)).foregroundStyle(AuraTheme.accent).padding(.horizontal, 10).padding(.vertical, 7).background(AuraTheme.accent.opacity(0.07), in: Capsule()) }
            IconButton(icon: player.isMini ? "pip.exit" : "pip.enter", help: "Mini oynatıcı") { player.toggleMini() }
        }.padding(.horizontal, 24).padding(.top, player.isMini ? 28 : 32).padding(.bottom, 17)
    }
    private func playerControls(_ item: MediaItem) -> some View {
        VStack(spacing: 6) {
            if item.kind != .live {
                HStack(spacing: 12) {
                    Text(clockText(scrubbing ? seekPosition : player.position)).frame(width: player.duration > 3600 ? 60 : 43, alignment: .leading)
                    Slider(value: Binding(get: { scrubbing ? seekPosition : min(player.position, max(1, player.duration)) }, set: { seekPosition = $0 }), in: 0...max(1, player.duration), onEditingChanged: { editing in
                        if editing { seekPosition = player.position; scrubbing = true }
                        else { player.seek(seekPosition); scrubbing = false }
                    }).controlSize(.small)
                    Text(clockText(player.duration)).frame(width: player.duration > 3600 ? 60 : 43, alignment: .trailing)
                }.font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted)
            }
            HStack(spacing: player.isMini ? 5 : 12) {
                if item.kind != .live && !player.isMini { IconButton(icon: "gobackward.\(store.preferences.seekStep)", help: "\(store.preferences.seekStep) saniye geri") { player.skip(forward: false) } }
                Button { player.togglePause() } label: { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16)).frame(width: 42, height: 42).foregroundStyle(AuraTheme.background).background(AuraTheme.accent, in: Circle()) }.buttonStyle(.plain).help("Oynat / duraklat")
                if item.kind != .live && !player.isMini {
                    IconButton(icon: "goforward.\(store.preferences.seekStep)", help: "\(store.preferences.seekStep) saniye ileri") { player.skip(forward: true) }
                    Picker("Atlama süresi", selection: Binding(get: { store.preferences.seekStep }, set: { store.preferences.seekStep = $0; store.persist() })) {
                        Text("5 sn").tag(5); Text("10 sn").tag(10)
                    }.labelsHidden().pickerStyle(.menu).frame(width: 72).help("İleri / geri atlama süresi").accessibilityLabel("Atlama süresi")
                }
                HStack(spacing: 5) {
                    IconButton(icon: player.volume == 0 ? "speaker.slash" : "speaker.wave.2", help: "Sesi kapat / aç", size: 13) { player.setVolume(player.volume == 0 ? 85 : 0) }
                    if !player.isMini { Slider(value: Binding(get: { player.volume }, set: { player.setVolume($0) }), in: 0...100).controlSize(.mini).frame(width: 68) }
                }
                Spacer(minLength: 2)
                if player.nativeMode {
                    Button("mpv’ye dön") { player.disableNativeMode() }.buttonStyle(QuietButton())
                } else {
                    if !player.isMini {
                        Menu { ForEach([0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], id: \.self) { rate in Button("\(rate.formatted())×") { player.setRate(rate) } } } label: { Text("\(player.rate.formatted())×").font(.system(size: 11, weight: .medium)).monospacedDigit() }.menuStyle(.borderlessButton).fixedSize().frame(width: 42)
                        Menu {
                            ForEach(player.tracks.filter { $0.type == "audio" }) { track in Button { player.selectTrack(track) } label: { Text("\(track.selected ? "✓ " : "")\(track.displayName)") } }
                        } label: { Image(systemName: "waveform").frame(width: 26) }.menuStyle(.borderlessButton).fixedSize().help("Ses parçası")
                    }
                    IconButton(icon: "captions.bubble", help: "Altyazı seç veya internetten ara") { player.showSubtitles = true }
                }
                Menu {
                    Button(player.showStats ? "Yayın bilgilerini gizle" : "Yayın bilgileri") { player.showStats.toggle() }
                    if !player.nativeMode { Button("AirPlay ve sistem PiP · Apple oynatıcı") { player.enableNativeMode() } }
                    Divider()
                    Menu("Görüntü oranı") {
                        Button("Otomatik") { player.session?.set("video-aspect-override", "-1"); player.session?.set("panscan", "0") }
                        Button("16:9") { player.session?.set("video-aspect-override", "16:9") }
                        Button("4:3") { player.session?.set("video-aspect-override", "4:3") }
                        Button("Ekranı doldur") { player.session?.set("panscan", "1") }
                    }
                    Menu("Uyku zamanlayıcısı") {
                        ForEach([15, 30, 60, 90], id: \.self) { minutes in Button("\(minutes) dakika sonra durdur") { player.sleepUntil = Date().addingTimeInterval(Double(minutes * 60)) } }
                        if player.sleepUntil != nil { Button("Zamanlayıcıyı iptal et") { player.sleepUntil = nil } }
                    }
                    if item.kind == .live { Button("Yayını kaydet…") { recording = true } }
                    if item.kind == .episode { Button("Sonraki bölüm") { player.playNextEpisode() } }
                    Divider()
                    Button("Bağlantıyı yenile") { player.restart() }
                } label: { Image(systemName: "ellipsis").font(.system(size: 16)).frame(width: 25) }.menuStyle(.borderlessButton).fixedSize().help("Diğer oynatma ayarları")
                IconButton(icon: "arrow.up.left.and.arrow.down.right", help: "Tam ekran") { player.toggleFullscreen() }
            }
            if let date = player.sleepUntil, !player.isMini { Text("\(date.formatted(date: .omitted, time: .shortened)) saatinde duracak").font(.system(size: 9)).foregroundStyle(AuraTheme.muted).frame(maxWidth: .infinity, alignment: .trailing) }
        }.padding(.horizontal, player.isMini ? 15 : 24).padding(.top, 13).padding(.bottom, 15)
    }
}

struct SubtitleSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @ObservedObject var player: PlaybackController
    @State private var query = ""
    @State private var language = "tr"
    @State private var results: [SubtitleResult] = []
    @State private var searching = false
    @State private var downloading: String?
    @State private var error: String?
    @State private var searched = false
    private var isLive: Bool { player.current?.kind == .live }
    private var client: OpenSubtitlesClient {
        let session = Vault.text("opensubtitles-session").data(using: .utf8).flatMap { try? JSONDecoder().decode(SubtitleSession.self, from: $0) } ?? SubtitleSession()
        return OpenSubtitlesClient(apiKey: Vault.text("opensubtitles-api-key"), session: session)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SheetHeading(eyebrow: "BİR HİKÂYE, HER DİLDE", title: "Altyazılar") { dismiss() }
            HStack(spacing: 12) {
                Button { player.disableSubtitles() } label: { Label("Kapalı", systemImage: "nosign") }.buttonStyle(QuietButton())
                if !isLive { Button { player.importSubtitle() } label: { Label("Dosyadan ekle", systemImage: "doc.badge.plus") }.buttonStyle(QuietButton()) }
                Spacer()
                Stepper(value: Binding(get: { player.subtitleDelay }, set: { player.setSubtitleDelay($0) }), in: -120...120, step: 0.1) {
                    Text("Gecikme: \(String(format: "%+.1f", player.subtitleDelay)) sn").font(.system(size: 11, design: .monospaced))
                }.fixedSize()
            }
            if !player.tracks.filter({ $0.type == "sub" }).isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "YAYINDAKİ / EKLENEN ALTYAZILAR")
                    ForEach(player.tracks.filter { $0.type == "sub" }) { track in
                        Button { player.selectTrack(track) } label: {
                            HStack { Image(systemName: track.selected ? "checkmark.circle.fill" : "circle").foregroundStyle(track.selected ? AuraTheme.accent : AuraTheme.muted); Text(track.displayName); Spacer(); Text(MediaLanguage.name(track.language)).foregroundStyle(AuraTheme.muted) }.font(.system(size: 12)).padding(10).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
            }
            if isLive && player.tracks.filter({ $0.type == "sub" }).isEmpty {
                Text("Bu canlı yayında altyazı parçası bulunmuyor.").font(.system(size: 12)).foregroundStyle(AuraTheme.muted).padding(.vertical, 24)
            }
            if !isLive {
            Divider().overlay(AuraTheme.line)
            HStack { Eyebrow(text: "OPENSUBTITLES.COM"); Spacer(); if let name = player.subtitleName { Text(name).font(.system(size: 10)).foregroundStyle(AuraTheme.accent).lineLimit(1) } }
            HStack(spacing: 10) {
                TextField("Film veya dizi adı", text: $query).textFieldStyle(.plain).font(.system(size: 12)).padding(12).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 8)).onSubmit(search)
                Picker("Dil", selection: $language) { Text("Türkçe").tag("tr"); Text("English").tag("en"); Text("Deutsch").tag("de"); Text("Français").tag("fr"); Text("Español").tag("es"); Text("العربية").tag("ar") }.labelsHidden().frame(width: 120)
                Button(action: search) { if searching { ProgressView().controlSize(.small) } else { Label("Ara", systemImage: "magnifyingglass") } }.buttonStyle(AccentButton(compact: true)).disabled(searching || query.isEmpty)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).lineSpacing(4) }
            ScrollView {
                LazyVStack(spacing: 9) {
                    if results.isEmpty {
                        VStack(spacing: 13) { Image(systemName: "captions.bubble").font(.system(size: 28, weight: .ultraLight)); Text(searched ? "Bu aramada altyazı bulunamadı." : "Adını ara, dilini seç, altyazıyı ekle.").font(.system(size: 12)); if !searched { Text("API anahtarını Ayarlar → Altyazı bölümünden ekleyebilirsin.").font(.system(size: 10)) } }.foregroundStyle(AuraTheme.muted).frame(maxWidth: .infinity).padding(.vertical, 42)
                    }
                    ForEach(results) { result in
                        HStack(spacing: 15) {
                            Text(result.attributes.language.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(AuraTheme.accent).frame(width: 38, height: 37).background(AuraTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(result.attributes.release ?? result.attributes.files.first?.fileName ?? "Altyazı").font(.system(size: 12)).lineLimit(2)
                                HStack(spacing: 10) { Text("\((result.attributes.downloadCount ?? 0).formatted()) indirme"); if result.attributes.hearingImpaired == true { Image(systemName: "ear.badge.waveform") }; if let fps = result.attributes.fps { Text("\(fps.formatted()) fps") } }.font(.system(size: 9)).foregroundStyle(AuraTheme.muted)
                            }
                            Spacer(minLength: 5)
                            if downloading == result.id { ProgressView().controlSize(.small) }
                            else if result.attributes.files.count > 1 {
                                Menu { ForEach(result.attributes.files, id: \.fileID) { file in Button(file.fileName) { download(result, file: file) } } } label: { Image(systemName: "arrow.down.circle").font(.system(size: 18)) }.menuStyle(.borderlessButton).fixedSize()
                            } else if let file = result.attributes.files.first { IconButton(icon: "arrow.down.circle", help: "Altyazıyı ekle") { download(result, file: file) } }
                        }.padding(12).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
            }
        }.padding(30).frame(width: 700, height: isLive ? 330 : 630).background(AuraTheme.background).foregroundStyle(AuraTheme.text).tint(AuraTheme.accent)
            .onAppear { query = player.current?.subtitleQuery ?? ""; language = store.preferences.subtitleLanguage }
    }
    private func search() {
        searching = true; error = nil; searched = true
        Task {
            defer { searching = false }
            do { results = try await client.search(query: query, language: language, season: player.current?.season, episode: player.current?.episode) }
            catch { self.error = error.localizedDescription }
        }
    }
    private func download(_ result: SubtitleResult, file: SubtitleResult.File) {
        guard downloading == nil else { return }; downloading = result.id; error = nil
        Task {
            defer { downloading = nil }
            do {
                let data = try await client.download(fileID: file.fileID)
                let url = Disk.folder("Subtitles").appendingPathComponent("\(file.fileID).srt")
                try data.write(to: url, options: .atomic); player.addSubtitle(url, name: file.fileName); dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

@MainActor final class MultiviewModel: ObservableObject {
    @Published var players: [PlaybackController] = []
    @Published var focused = 0
    func add(_ item: MediaItem, store: LibraryStore) {
        guard players.count < 4 else { return }
        let limit = store.source(item)?.connectionLimit ?? 4
        let used = players.filter { $0.current?.sourceID == item.sourceID }.count
        guard used < limit else { store.error = "Bu kaynak en fazla \(limit) eşzamanlı bağlantıya izin veriyor."; return }
        do {
            let url = try store.url(item)
            if players.isEmpty { store.player.close() }
            let player = PlaybackController(); player.store = store; player.setVolume(players.isEmpty ? 85 : 0)
            player.play(item, url: url); players.append(player)
        } catch { store.error = error.localizedDescription }
    }
    func focus(_ index: Int) { focused = index; for (i, player) in players.enumerated() { player.setVolume(i == index ? 85 : 0) } }
    func remove(_ index: Int) { players[index].close(); players.remove(at: index); if !players.isEmpty { focus(min(focused, players.count - 1)) } }
    func close() { players.forEach { $0.close() }; players = [] }
}

struct MultiviewScreen: View {
    @EnvironmentObject var store: LibraryStore
    @StateObject private var model = MultiviewModel()
    @State private var picking = false
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) { Text("Bir ekranda, dört ayrı dünya.").font(.system(size: 23, weight: .light)); Text("Sesini duymak istediğin ekrana tıkla. Her yayın, kaynağındaki bir bağlantıyı kullanır.").font(.system(size: 11)).foregroundStyle(AuraTheme.muted) }
                Spacer(); Button { picking = true } label: { Label("Kanal ekle", systemImage: "plus") }.buttonStyle(AccentButton(compact: true)).disabled(model.players.count >= 4)
            }
            GeometryReader { geometry in
                let height = max(170, (geometry.size.height - 16) / 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible())], spacing: 16) {
                    ForEach(0..<4, id: \.self) { index in
                        if index < model.players.count { MultiviewTile(player: model.players[index], selected: model.focused == index, select: { model.focus(index) }, remove: { model.remove(index) }).frame(height: height) }
                        else {
                            Button { picking = true } label: { VStack(spacing: 13) { Image(systemName: "plus").font(.system(size: 23, weight: .ultraLight)); Text("Bir yayın ekle").font(.system(size: 11)) }.foregroundStyle(AuraTheme.muted).frame(maxWidth: .infinity).frame(height: height).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(AuraTheme.line)) }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.padding(32).onDisappear { model.close() }
            .sheet(isPresented: $picking) {
                VStack(alignment: .leading, spacing: 20) {
                    SheetHeading(eyebrow: "ÇOKLU EKRAN", title: "Bir yayın seç.") { picking = false }
                    TextField("Kanal ara", text: $query).textFieldStyle(.roundedBorder)
                    ScrollView { LazyVStack(spacing: 7) {
                        ForEach(store.visibleItems.filter { $0.kind == .live && (query.isEmpty || $0.title.localizedStandardContains(query)) }) { item in
                            Button { model.add(item, store: store); picking = false } label: { HStack { Artwork(address: item.artwork).frame(width: 40, height: 28).clipShape(RoundedRectangle(cornerRadius: 5)); Text(item.title).font(.system(size: 12)); Spacer(); Image(systemName: "plus.circle").foregroundStyle(AuraTheme.accent) }.padding(12).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                        }
                    } }
                }.padding(30).frame(width: 500, height: 550).background(AuraTheme.background).foregroundStyle(AuraTheme.text)
            }
    }
}

struct MultiviewTile: View {
    @ObservedObject var player: PlaybackController
    let selected: Bool
    let select: () -> Void
    let remove: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ZStack { Color.black; if let session = player.session { MPVSurface(session: session) }; if player.buffering { ProgressView().controlSize(.small) }; if let error = player.playbackError { Text(error).font(.system(size: 10)).padding(15).background(.black.opacity(0.8)) } }.contentShape(Rectangle()).onTapGesture(perform: select)
            HStack { Image(systemName: selected ? "speaker.wave.2.fill" : "speaker.slash").foregroundStyle(selected ? AuraTheme.accent : AuraTheme.muted); Text(player.current?.title ?? "").font(.system(size: 10)).lineLimit(1); Spacer(); IconButton(icon: "xmark", help: "Yayını kaldır", size: 10, action: remove) }.padding(.leading, 12).background(AuraTheme.surface)
        }.clipShape(RoundedRectangle(cornerRadius: 11)).overlay(RoundedRectangle(cornerRadius: 11).stroke(selected ? AuraTheme.accent.opacity(0.6) : AuraTheme.line, lineWidth: selected ? 1.5 : 1))
    }
}

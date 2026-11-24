import SwiftUI
import AuraCore
import UniformTypeIdentifiers

struct SheetHeading: View {
    let eyebrow: String
    let title: String
    let close: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) { Eyebrow(text: eyebrow); Text(title).font(.system(size: 29, weight: .light)).tracking(-0.7) }
            Spacer(); IconButton(icon: "xmark", help: "Kapat", size: 13, action: close)
        }
    }
}
struct LabeledInput: View {
    let label: String
    let placeholder: String
    @Binding var value: String
    var secure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(AuraTheme.muted)
            Group { if secure { SecureField(placeholder, text: $value) } else { TextField(placeholder, text: $value) } }
                .textFieldStyle(.plain).font(.system(size: 13)).padding(13).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(AuraTheme.line))
        }
    }
}

struct AddSourceSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var type = "Xtream"
    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var password = ""
    @State private var epg = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SheetHeading(eyebrow: "KENDİ YAYINLARIN, KENDİ ALANIN", title: "Bir kaynak ekle.") { if !busy { dismiss() } }
            Text("Sağlayıcının verdiği bağlantıyı ekle. Kanalların, filmlerin ve dizilerin otomatik olarak kitaplığına yerleşsin.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(AuraTheme.muted)
            Picker("Kaynak türü", selection: $type) { Text("Xtream Codes").tag("Xtream"); Text("M3U / M3U8").tag("M3U") }.pickerStyle(.segmented)
            VStack(spacing: 17) {
                LabeledInput(label: "Kaynak adı", placeholder: "Örneğin: Evdeki yayınlarım", value: $name)
                LabeledInput(label: type == "Xtream" ? "Sunucu veya tam Xtream bağlantısı" : "M3U bağlantısı", placeholder: type == "Xtream" ? "https://sunucu.com:8080" : "https://sunucu.com/liste.m3u", value: $address)
                if type == "Xtream" {
                    HStack(spacing: 14) { LabeledInput(label: "Kullanıcı adı", placeholder: "Kullanıcı adın", value: $username); LabeledInput(label: "Şifre", placeholder: "Şifren", value: $password, secure: true) }
                    Text("get.php?username=…&password=… içeren bağlantılarda kullanıcı adı ve şifreyi ayrıca yazmana gerek yok.").font(.system(size: 10)).lineSpacing(4).foregroundStyle(AuraTheme.muted)
                } else {
                    LabeledInput(label: "XMLTV rehberi · isteğe bağlı", placeholder: "https://sunucu.com/epg.xml", value: $epg)
                    Button("Bilgisayarımdan M3U seç…") {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "m3u"), UTType(filenameExtension: "m3u8")].compactMap { $0 }
                        if panel.runModal() == .OK { address = panel.url?.absoluteString ?? "" }
                    }.buttonStyle(.link).font(.system(size: 11))
                }
            }
            if let error { Label(error, systemImage: "exclamationmark.circle").font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Label("Giriş bilgileri Anahtar Zinciri’nde saklanır.", systemImage: "lock.shield").font(.system(size: 10)).foregroundStyle(AuraTheme.muted)
                Spacer()
                Button {
                    busy = true; error = nil
                    Task {
                        do {
                            if type == "Xtream" { try await store.addXtream(name: name, address: address, username: username, password: password) }
                            else { try await store.addM3U(name: name, address: address, epgURL: epg) }
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                        busy = false
                    }
                } label: { HStack(spacing: 8) { if busy { ProgressView().controlSize(.small).tint(AuraTheme.background) }; Text(busy ? "Kitaplık alınıyor…" : "Bağlan ve ekle"); if !busy { Image(systemName: "arrow.right") } } }.buttonStyle(AccentButton()).disabled(busy || address.isEmpty)
            }
        }.padding(34).frame(width: 590).background(AuraTheme.background).foregroundStyle(AuraTheme.text).interactiveDismissDisabled(busy)
    }
}

struct DetailSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let item: MediaItem
    @State private var detailed: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var season = 1
    @State private var loading = false
    @State private var error: String?
    private var media: MediaItem { detailed ?? item }
    private var nextEpisode: MediaItem? { WatchHistory.nextEpisode(in: episodes, states: store.personal.states) }
    private var playLabel: String {
        let target = item.kind == .series ? nextEpisode : media
        guard let target else { return "Şimdi izle" }
        let state = store.personal.states[target.id]
        let action = state?.isInProgress == true ? "Devam et" : state?.watched == true ? "Yeniden izle" : "Şimdi izle"
        return item.kind == .series ? "\(action) · S\(target.season ?? 1) B\(target.episode ?? 1)" : action
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ZStack(alignment: .bottomLeading) {
                    Artwork(address: media.backdrop ?? media.artwork).frame(height: 250)
                    LinearGradient(colors: [.clear, AuraTheme.background], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 11) {
                        Eyebrow(text: "\(media.kind.label.uppercased()) / \(media.category.uppercased())")
                        Text(store.title(media)).font(.system(size: 37, weight: .light)).tracking(-0.9).lineLimit(2)
                    }.padding(.horizontal, 32).padding(.bottom, 12)
                }.overlay(alignment: .topTrailing) { IconButton(icon: "xmark", help: "Kapat", size: 13) { dismiss() }.background(.black.opacity(0.5), in: Circle()).padding(16) }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 13) {
                        if let year = media.year { Text(year) }
                        if let duration = media.duration, duration > 0 { Text("\(Int(duration / 60)) dk") }
                        if let rating = media.rating, rating > 0 { Label(String(format: "%.1f", rating), systemImage: "star.fill").foregroundStyle(AuraTheme.accent) }
                        if let source = store.source(item) { Text(source.name).foregroundStyle(AuraTheme.muted) }
                    }.font(.system(size: 11)).foregroundStyle(AuraTheme.muted)
                    HStack(spacing: 10) {
                        Button { if item.kind == .series { if let nextEpisode { store.play(nextEpisode); dismiss() } } else { store.play(media); dismiss() } } label: { Label(playLabel, systemImage: "play.fill") }.buttonStyle(AccentButton()).disabled(item.kind == .series && episodes.isEmpty)
                        Button { store.toggleFavorite(item) } label: { Label(store.personal.states[item.id]?.favorite == true ? "Listemde" : "Listeme ekle", systemImage: store.personal.states[item.id]?.favorite == true ? "bookmark.fill" : "bookmark") }.buttonStyle(QuietButton())
                        if item.kind == .movie || item.kind == .episode { Button { store.transfers.download(media) } label: { Image(systemName: "arrow.down") }.buttonStyle(QuietButton()).help("Çevrimdışı indir") }
                    }
                    if item.kind != .series, let state = store.personal.states[item.id], state.position > 0 || state.watched { WatchProgress(state: state) }
                    if let overview = media.overview, !overview.isEmpty { Text(overview).font(.system(size: 13)).lineSpacing(7).foregroundStyle(AuraTheme.text.opacity(0.7)).textSelection(.enabled) }
                    if item.kind == .series { episodeList }
                    if let error { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
                }.padding(.horizontal, 32).padding(.bottom, 34)
            }
        }.frame(width: 770, height: 650).background(AuraTheme.background).foregroundStyle(AuraTheme.text)
            .task {
                guard store.source(item)?.kind == .xtream else { return }
                if item.kind == .series {
                    episodes = store.items.filter { $0.sourceID == item.sourceID && $0.seriesID == item.streamID && $0.kind == .episode }
                        .sorted { ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0) }
                    season = nextEpisode?.season ?? episodes.first?.season ?? 1
                }
                loading = true; defer { loading = false }
                do {
                    if item.kind == .series { episodes = try await store.loadEpisodes(item); season = nextEpisode?.season ?? episodes.first?.season ?? 1 }
                    else { detailed = try await store.client(item).details(item) }
                } catch { self.error = error.localizedDescription }
            }
    }
    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bölümler").font(.system(size: 18, weight: .medium)); Spacer()
                Picker("Sezon", selection: $season) { ForEach(Array(Set(episodes.compactMap(\.season))).sorted(), id: \.self) { season in Text("\(season). sezon").tag(season) } }.fixedSize()
            }
            if loading { ProgressView().frame(maxWidth: .infinity).padding(25) }
            ForEach(episodes.filter { $0.season == season }) { episode in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Text(String(format: "%02d", episode.episode ?? 0)).font(.system(size: 16, weight: .light, design: .monospaced)).foregroundStyle(AuraTheme.muted).frame(width: 30)
                        Artwork(address: episode.artwork, title: episode.title).frame(width: 82, height: 48).clipShape(RoundedRectangle(cornerRadius: 5))
                        VStack(alignment: .leading, spacing: 5) { Text(episode.title).font(.system(size: 12, weight: .medium)); if let duration = episode.duration { Text("\(Int(duration / 60)) dakika").font(.system(size: 10)).foregroundStyle(AuraTheme.muted) } }
                        Spacer()
                        if store.personal.states[episode.id]?.watched == true { Image(systemName: "checkmark.circle.fill").foregroundStyle(AuraTheme.accent) }
                        IconButton(icon: "arrow.down.circle", help: "İndir") { store.transfers.download(episode) }
                        IconButton(icon: "play.fill", help: store.personal.states[episode.id]?.isInProgress == true ? "Bölüme devam et" : "Bölümü izle") { store.play(episode); dismiss() }
                    }
                    if let state = store.personal.states[episode.id], state.position > 0 || state.watched { WatchProgress(state: state) }
                }.padding(12).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 9))
                    .contextMenu {
                        Button("Baştan oynat", systemImage: "backward.end") { store.play(episode, fromBeginning: true); dismiss() }
                        Button(store.personal.states[episode.id]?.watched == true ? "İzlenmedi olarak işaretle" : "İzlendi olarak işaretle", systemImage: "checkmark.circle") { store.markWatched(episode) }
                    }
            }
        }
    }
}

struct RecordingSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let item: MediaItem
    @State private var start = Date()
    @State private var minutes = 60
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SheetHeading(eyebrow: "YAYIN KAYDI", title: "Sonra da izlersin.") { dismiss() }
            Text(store.title(item)).font(.system(size: 16, weight: .medium))
            DatePicker("Başlangıç", selection: $start, in: Date()...).datePickerStyle(.field)
            Stepper("Süre: \(minutes) dakika", value: $minutes, in: 1...720, step: 15)
            Text("Kayıt sırasında Aura açık, Mac uyanık olmalı. Kayıt, sağlayıcındaki bir yayın bağlantısını kullanır. Dosya MKV olarak İndirilenler’e kaydedilir.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(AuraTheme.muted)
            HStack { Spacer(); Button("Kaydı planla") { store.transfers.schedule(item, start: start, minutes: minutes); dismiss() }.buttonStyle(AccentButton()) }
        }.padding(32).frame(width: 490).background(AuraTheme.background).foregroundStyle(AuraTheme.text)
    }
}

struct UnlockSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var pin = ""
    @State private var failed = false
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock").font(.system(size: 28, weight: .light)).foregroundStyle(AuraTheme.accent)
            Text("Ebeveyn kilidi").font(.system(size: 23, weight: .light))
            SecureField("PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 180).onSubmit(verify)
            if failed { Text("PIN eşleşmedi.").font(.system(size: 12)).foregroundStyle(.orange) }
            HStack { Button("Vazgeç") { dismiss() }.buttonStyle(QuietButton()); Button("Kilidi aç", action: verify).buttonStyle(AccentButton()) }
        }.padding(40).frame(width: 390).background(AuraTheme.background).foregroundStyle(AuraTheme.text)
    }
    private func verify() { if store.verifyPIN(pin) { store.unlocked = true; dismiss() } else { failed = true } }
}

struct DownloadsView: View {
    @EnvironmentObject var store: LibraryStore
    @ObservedObject var manager: TransferManager
    var body: some View {
        if manager.jobs.isEmpty {
            EmptyState(icon: "arrow.down.circle", title: "Yanına alacağın hikâyeler.", message: "Filmleri ve bölümleri çevrimdışı indir veya canlı yayınlar için kayıt planla. Hepsi burada yerini alır.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Eyebrow(text: "ÇEVRİMDIŞI KİTAPLIĞIN"); Spacer(); Text("\(manager.activeCount) etkin işlem").font(.system(size: 11)).foregroundStyle(AuraTheme.muted) }
                    ForEach(manager.jobs) { job in
                        HStack(spacing: 20) {
                            Artwork(address: job.item.artwork).frame(width: 128, height: 78).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.title(job.item)).font(.system(size: 14, weight: .medium))
                                HStack(spacing: 8) { if job.state == .recording { Circle().fill(.red).frame(width: 5, height: 5) }; Text(status(job)).font(.system(size: 11)).foregroundStyle(AuraTheme.muted) }
                                if [.downloading, .recording].contains(job.state) { ProgressView(value: job.progress).tint(AuraTheme.accent).frame(maxWidth: 350) }
                                if let error = job.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
                            }
                            Spacer()
                            if job.state == .complete {
                                IconButton(icon: "folder", help: "Finder’da göster") { manager.reveal(job) }
                                Button { manager.play(job) } label: { Label("İzle", systemImage: "play.fill") }.buttonStyle(AccentButton(compact: true))
                            } else if [.downloading, .recording, .queued].contains(job.state) {
                                IconButton(icon: "stop.circle", help: "Durdur") { manager.cancel(job) }
                            } else { IconButton(icon: "arrow.clockwise", help: "Yeniden dene") { manager.retry(job) } }
                            IconButton(icon: "trash", help: "Dosyayı ve kaydı sil") { manager.remove(job) }
                        }.padding(18).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 13))
                    }
                }.padding(32)
            }.scrollIndicators(.hidden)
        }
    }
    private func status(_ job: TransferJob) -> String {
        switch job.state {
        case .queued: return "Planlandı · \(job.start?.formatted(date: .abbreviated, time: .shortened) ?? "")"
        case .downloading: return "İndiriliyor · %\(Int(job.progress * 100))"
        case .recording: return "Kaydediliyor · %\(Int(job.progress * 100))"
        case .complete: return job.isRecording ? "Kayıt hazır · MKV" : "Çevrimdışı izlemeye hazır"
        case .failed: return "Tamamlanamadı"
        case .cancelled: return "İptal edildi"
        }
    }
}

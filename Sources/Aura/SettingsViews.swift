import SwiftUI
import AuraCore

struct SourcesView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var deleting: PlaylistSource?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) { Text("Bütün yayınların, tek bir yerde.").font(.system(size: 23, weight: .light)).tracking(-0.4); Text("Kaynaklarını ekle, güncelle ve kitaplığının akışını yönet.").font(.system(size: 12)).foregroundStyle(AuraTheme.muted) }
                    Spacer(); Button { store.showAddSource = true } label: { Label("Kaynak ekle", systemImage: "plus") }.buttonStyle(AccentButton())
                }
                if store.selectedSource != nil { Button("Tüm kaynakları göster") { store.selectedSource = nil }.buttonStyle(QuietButton()) }
                ForEach(store.sources) { source in
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 15) {
                            Image(systemName: source.kind == .demo ? "sparkles" : "square.stack.3d.up").font(.system(size: 22, weight: .light)).foregroundStyle(AuraTheme.accent).frame(width: 52, height: 52).background(AuraTheme.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 7) { Text(source.name).font(.system(size: 17, weight: .medium)); Text(source.kind == .demo ? "Açık lisanslı örnek filmler ve HLS test akışı" : sanitized(source.server)).font(.system(size: 11)).foregroundStyle(AuraTheme.muted).lineLimit(1) }
                            Spacer()
                            Text(source.kind == .xtream ? "XTREAM" : source.kind == .m3u ? "M3U" : "ÖNİZLEME").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).foregroundStyle(AuraTheme.accent).padding(.horizontal, 10).padding(.vertical, 7).background(AuraTheme.accent.opacity(0.06), in: Capsule())
                            if store.loadingSources.contains(source.id) { ProgressView().controlSize(.small).frame(width: 30) }
                            else if source.kind != .demo { IconButton(icon: "arrow.clockwise", help: "Kaynağı yenile") { Task { await store.refresh(source) } } }
                            IconButton(icon: "trash", help: "Kaynağı kaldır") { deleting = source }
                        }
                        Rectangle().fill(AuraTheme.line).frame(height: 1)
                        HStack(spacing: 28) {
                            let content = store.items.filter { $0.sourceID == source.id }
                            sourceStat("CANLI", value: String(content.filter { $0.kind == .live }.count))
                            sourceStat("FİLM", value: String(content.filter { $0.kind == .movie }.count))
                            sourceStat("DİZİ", value: String(content.filter { $0.kind == .series }.count))
                            if let limit = source.connectionLimit { sourceStat("BAĞLANTI SINIRI", value: String(limit)) }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 6) {
                                if let date = source.lastSync { Text("Güncellendi: \(date.formatted(date: .abbreviated, time: .shortened))") }
                                if let expiry = source.expiresAt { Text("Hesap bitişi: \(expiry.formatted(date: .abbreviated, time: .omitted))").foregroundStyle(expiry < Date() ? .orange : AuraTheme.muted) }
                            }.font(.system(size: 10)).foregroundStyle(AuraTheme.muted)
                            Button("Kitaplığı göster") { store.selectedSource = source.id; store.destination = .home }.buttonStyle(QuietButton())
                        }
                    }.padding(24).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(AuraTheme.line))
                }
                Text("Aura bir oynatıcıdır; kendi yayın kaynağını bağlarsın. Örnek koleksiyondaki filmler Blender Studio’nun açık lisanslı yapımlarıdır.").font(.system(size: 11)).lineSpacing(5).foregroundStyle(AuraTheme.muted)
            }.padding(32)
        }.scrollIndicators(.hidden)
            .alert("Kaynak kaldırılsın mı?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Kaldır", role: .destructive) { if let deleting { store.removeSource(deleting) }; deleting = nil }
                Button("Vazgeç", role: .cancel) { deleting = nil }
            } message: { Text("Bu kaynağın kanalları ve katalog bilgileri Aura’dan kaldırılacak.") }
    }
    private func sourceStat(_ title: String, value: String) -> some View { VStack(alignment: .leading, spacing: 7) { Eyebrow(text: title); Text(value).font(.system(size: 21, weight: .light, design: .rounded)) } }
    private func sanitized(_ address: String) -> String { guard var c = URLComponents(string: address) else { return "" }; c.query = nil; c.user = nil; c.password = nil; return c.string ?? "" }
}

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var section = "Oynatma"
    @State private var apiKey = Vault.text("opensubtitles-api-key")
    @State private var username = ""
    @State private var password = ""
    @State private var subtitleStatus = Vault.text("opensubtitles-session").isEmpty ? "" : "OpenSubtitles hesabın bağlı."
    @State private var busy = false
    @State private var pin = ""
    @State private var oldPIN = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(spacing: 8) {
                ForEach(["Oynatma", "Altyazı", "Kitaplık", "Gizlilik", "Hakkında"], id: \.self) { name in
                    Button { section = name } label: { Text(name).font(.system(size: 12, weight: .medium)).padding(.horizontal, 17).padding(.vertical, 11).foregroundStyle(section == name ? AuraTheme.accent : AuraTheme.muted).background(section == name ? AuraTheme.elevated : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 32).padding(.top, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    switch section {
                    case "Oynatma": playback
                    case "Altyazı": subtitles
                    case "Kitaplık": library
                    case "Gizlilik": privacy
                    default: about
                    }
                }.frame(maxWidth: 750, alignment: .leading).padding(.horizontal, 32).padding(.bottom, 35).frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
        }.onChange(of: store.preferences) { _, _ in store.persist() }
    }
    private var playback: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsTitle("Her ayrıntı, senin kontrolünde.", description: "Donanım hızlandırmalı mpv oynatıcı. HLS, MPEG-TS, MP4, MKV ve daha fazlası.")
            settingsCard {
                settingRow("Canlı yayın biçimi", detail: "HLS başarısız olursa TS otomatik denenir.") { Picker("Biçim", selection: $store.preferences.liveFormat) { Text("HLS · m3u8").tag("m3u8"); Text("MPEG-TS").tag("ts") }.labelsHidden().frame(width: 150) }
                settingRow("Canlı yayın gecikmesi", detail: "Seçimin saklanır. Oynayan canlı yayın, değişikliği uygulamak için yeniden açılır.") {
                    Picker("Canlı yayın gecikmesi", selection: Binding(
                        get: { store.preferences.livePlaybackMode },
                        set: { store.preferences.livePlaybackMode = $0; store.persist(); store.player.applyLivePlaybackPreference() }
                    )) {
                        ForEach(LivePlaybackMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }.labelsHidden().frame(width: 190).accessibilityLabel("Canlı yayın gecikmesi")
                }
                Text(store.preferences.livePlaybackMode.detail).font(.system(size: 11)).foregroundStyle(AuraTheme.muted).fixedSize(horizontal: false, vertical: true)
                Text("Tampon hedefi, canlıya olan gecikme ölçümü değildir. Sağlayıcının gecikmesi ve HLS parça süresi azaltılamaz; gol bildiriminden önce görüntü garantisi vermez.").font(.system(size: 11)).foregroundStyle(AuraTheme.muted).fixedSize(horizontal: false, vertical: true)
                Divider().overlay(AuraTheme.line)
                Toggle("Bağlantı kesilince otomatik yeniden bağlan", isOn: $store.preferences.autoReconnect)
                Toggle("İzleme konumunu hatırla", isOn: $store.preferences.rememberPosition)
                Toggle("Sonraki bölümü otomatik oynat", isOn: $store.preferences.autoNext)
                settingRow("İleri / geri atlama", detail: "Oynatıcı düğmeleri ve klavye okları aynı süreyi kullanır.") {
                    Picker("Atlama süresi", selection: $store.preferences.seekStep) { Text("5 saniye").tag(5); Text("10 saniye").tag(10) }.labelsHidden().frame(width: 160)
                }
                Divider().overlay(AuraTheme.line)
                settingRow("Tercih edilen ses dili", detail: "Son seçimin sonraki film ve bölümlerde hatırlanır.") { preferredLanguagePicker(audio: true) }
                settingRow("Tercih edilen altyazı", detail: "Bu dil varsa otomatik seçilir; Kapalı tercihi de hatırlanır.") { preferredLanguagePicker(audio: false) }
                settingRow("Arşiv saat düzeltmesi", detail: "Sağlayıcı arşiv saatini dakika olarak kaydır.") { Stepper("\(store.preferences.catchupOffset) dk", value: $store.preferences.catchupOffset, in: -1440...1440, step: 30).frame(width: 160) }
            }
            settingsCard {
                Eyebrow(text: "KLAVYE KISAYOLLARI")
                shortcut("Oynat / duraklat", "Boşluk"); shortcut("\(store.preferences.seekStep) saniye ileri / geri", "←  →")
                shortcut("Ara", "⌘ F"); shortcut("Kaynak ekle", "⌘ N"); shortcut("Altyazılar", "⇧ ⌘ S")
                shortcut("Tam ekran", "⌃ ⌘ F"); shortcut("Mini oynatıcı", "⇧ ⌘ P")
            }
        }
    }
    private var subtitles: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsTitle("Her hikâyeyi kendi dilinde izle.", description: "Yayının içindeki altyazıları seç, dosya ekle veya OpenSubtitles’ta ara.")
            settingsCard {
                settingRow("Varsayılan altyazı dili", detail: "Oynatıcıda ve çevrimiçi aramada kullanılır.") { languagePicker }
                settingRow("Yazı boyutu", detail: "Oynatma başladığında uygulanır.") { Slider(value: $store.preferences.subtitleSize, in: 24...68, step: 2).frame(width: 140); Text(String(Int(store.preferences.subtitleSize))).monospacedDigit().frame(width: 25) }
            }
            settingsCard {
                HStack { Image(systemName: "captions.bubble").foregroundStyle(AuraTheme.accent); Text("OpenSubtitles.com").font(.system(size: 17, weight: .medium)); Spacer(); Link("API anahtarı al ↗", destination: URL(string: "https://www.opensubtitles.com/en/consumers")!).font(.system(size: 11)) }
                Text("Arama için kendi API anahtarını ekle. Hesabını bağladığında indirmeler hesabının kotasını kullanır.").font(.system(size: 12)).lineSpacing(5).foregroundStyle(AuraTheme.muted)
                LabeledInput(label: "API anahtarı", placeholder: "OpenSubtitles API key", value: $apiKey, secure: true)
                HStack { LabeledInput(label: "Kullanıcı adı", placeholder: "OpenSubtitles kullanıcı adı", value: $username); LabeledInput(label: "Şifre", placeholder: "Şifre", value: $password, secure: true) }
                if !subtitleStatus.isEmpty { Text(subtitleStatus).font(.system(size: 11)).foregroundStyle(AuraTheme.accent) }
                HStack {
                    Button("Anahtarı kaydet") { do { try Vault.saveText(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), "opensubtitles-api-key"); subtitleStatus = "API anahtarı kaydedildi." } catch { store.error = error.localizedDescription } }.buttonStyle(QuietButton())
                    Button(busy ? "Bağlanıyor…" : "Hesabı bağla") { loginSubtitles() }.buttonStyle(AccentButton(compact: true)).disabled(busy || username.isEmpty || password.isEmpty || apiKey.isEmpty)
                    Spacer()
                    Button("Bağlantıyı kaldır") { Vault.remove("opensubtitles-session"); subtitleStatus = "Hesap bağlantısı kaldırıldı." }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(AuraTheme.muted)
                }
            }
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsTitle("Kaldığın yer, seninle gelsin.", description: "Kişisel kitaplığını seçtiğin bir klasör üzerinden diğer Mac’lerinle eşitle.")
            settingsCard {
                Label("iCloud Drive / klasör eşitlemesi", systemImage: "icloud").font(.system(size: 16, weight: .medium))
                Text("Favoriler, görünen adlar, gizli kategoriler ve izleme ilerlemesi 30 saniyede bir birleştirilir. Diğer Mac’te de aynı kaynağı ekleyip aynı klasörü seç. Şifrelerin paylaşılmaz.").font(.system(size: 12)).lineSpacing(6).foregroundStyle(AuraTheme.muted)
                if let folder = store.syncFolder { Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(AuraTheme.accent).textSelection(.enabled) }
                HStack {
                    Button(store.syncFolder == nil ? "Klasör seç" : "Klasörü değiştir") { store.chooseSyncFolder() }.buttonStyle(AccentButton(compact: true))
                    if store.syncFolder != nil { Button("Şimdi eşitle") { store.syncPersonal() }.buttonStyle(QuietButton()); Button("Durdur") { store.stopSync() }.buttonStyle(QuietButton()) }
                    Spacer()
                }
                if let date = store.lastFolderSync { Text("Son eşitleme: \(date.formatted(date: .omitted, time: .standard))").font(.system(size: 10)).foregroundStyle(AuraTheme.muted) }
            }
            settingsCard {
                settingRow("Gizlenen kategoriler", detail: "\(store.personal.hiddenCategories.count) kategori gizlendi.") { Button("Tümünü göster") { store.personal.hiddenCategories = []; store.personal.updatedAt = Date(); store.persist() }.buttonStyle(QuietButton()) }
                settingRow("Yerel veriler", detail: "Katalog şifrelenir; izleme verileri bu Mac’te saklanır.") { Button("Finder’da aç") { NSWorkspace.shared.open(Disk.root) }.buttonStyle(QuietButton()) }
            }
            TraktSettings(manager: store.trakt)
        }
    }
    private var privacy: some View {
        VStack(alignment: .leading, spacing: 23) {
            settingsTitle("Kendine ait bir alan.", description: "Hesap bilgilerin Anahtar Zinciri’nde, katalog verilerin AES-GCM ile şifreli saklanır.")
            settingsCard {
                Toggle("Yetişkin içerikleri gizle", isOn: Binding(get: { store.preferences.hideAdult }, set: { value in
                    if !value && !Vault.text("parental-pin").isEmpty && !store.unlocked { store.showUnlock = true }
                    else { store.preferences.hideAdult = value }
                }))
                Text("İçerik işaretleri sağlayıcıdan gelir. Sınıflandırılmamış içerikler otomatik tanınamayabilir.").font(.system(size: 11)).foregroundStyle(AuraTheme.muted)
                if !Vault.text("parental-pin").isEmpty { LabeledInput(label: "Mevcut PIN", placeholder: "PIN’i değiştirmek için", value: $oldPIN, secure: true) }
                LabeledInput(label: "Yeni ebeveyn PIN’i", placeholder: "En az 4 rakam", value: $pin, secure: true)
                HStack {
                    Button("PIN’i kaydet") {
                        do {
                            guard Vault.text("parental-pin").isEmpty || store.verifyPIN(oldPIN) else { throw AuraError.message("Mevcut PIN doğru değil.") }
                            try store.setPIN(pin); pin = ""; oldPIN = ""; store.unlocked = false; store.notice = "PIN kaydedildi."
                        } catch { store.error = error.localizedDescription }
                    }.buttonStyle(AccentButton(compact: true))
                    if store.unlocked { Button("Yeniden kilitle") { store.unlocked = false }.buttonStyle(QuietButton()) }
                }
            }
            settingsCard {
                Label("Ağ bağlantısı", systemImage: "network").font(.system(size: 16, weight: .medium))
                Text("Aura, Mac’inin etkin ağ bağlantısını kullanır. Sistemindeki WireGuard veya başka bir VPN istemcisini açarak bağlantıyı yönetebilirsin.").font(.system(size: 12)).foregroundStyle(AuraTheme.muted).lineSpacing(5)
                Button("VPN ayarlarını aç") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension")!) }.buttonStyle(QuietButton())
            }
        }
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 23) {
            Text("aura").font(.system(size: 65, weight: .ultraLight, design: .rounded)).tracking(-3)
            Text("Sadece sen ve izlemek istediklerin.").font(.system(size: 22, weight: .light))
            Text("Mac için yerel bir IPTV oynatıcı. SwiftUI arayüzü, mpv oynatma altyapısı ve OpenSubtitles.com entegrasyonu.\n\nSürüm 1.0 · macOS 14 ve üzeri · Apple Silicon").font(.system(size: 12)).lineSpacing(7).foregroundStyle(AuraTheme.muted)
            settingsCard {
                Eyebrow(text: "AÇIK KAYNAK / KATKILAR")
                Link("mpv · Oynatma altyapısı", destination: URL(string: "https://mpv.io")!)
                Link("FFmpeg · Medya kitaplıkları", destination: URL(string: "https://ffmpeg.org")!)
                Link("IINA · macOS kitaplık derlemeleri", destination: URL(string: "https://github.com/iina/iina/releases/tag/v1.5.0")!)
                Link("Blender Studio · Örnek film koleksiyonu", destination: URL(string: "https://studio.blender.org/films/")!)
                Link("Unsplash · Açılış fotoğrafı", destination: URL(string: "https://unsplash.com/photos/photo-1464822759023-fed622ff2c3b")!)
            }
        }
    }
    private var languagePicker: some View { preferredLanguagePicker(audio: false) }
    private func preferredLanguagePicker(audio: Bool) -> some View {
        Picker(audio ? "Ses dili" : "Altyazı dili", selection: Binding<String>(
            get: { !audio && store.preferences.subtitlesEnabled == false ? "off" : MediaLanguage.canonical(audio ? store.preferences.audioLanguage : store.preferences.subtitleLanguage) },
            set: { value in
                if audio { store.preferences.audioLanguage = value; store.preferences.preferredAudioTitle = nil }
                else if value == "off" { store.preferences.subtitlesEnabled = false }
                else { store.preferences.subtitleLanguage = value; store.preferences.subtitlesEnabled = true; store.preferences.preferredSubtitleTitle = nil }
            }
        )) {
            if !audio { Text("Kapalı").tag("off") }
            ForEach(MediaLanguage.choices, id: \.code) { choice in Text(choice.name).tag(choice.code) }
        }.labelsHidden().frame(width: 160)
    }
    private func loginSubtitles() {
        busy = true
        Task {
            defer { busy = false }
            do {
                let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                let session = try await OpenSubtitlesClient(apiKey: key).login(username: username, password: password)
                try Vault.saveText(key, "opensubtitles-api-key"); try Vault.saveText(String(decoding: JSONEncoder().encode(session), as: UTF8.self), "opensubtitles-session")
                password = ""; subtitleStatus = "Hesabın bağlandı. Oynatıcıdaki altyazı menüsünden arama yapabilirsin."
            } catch { store.error = error.localizedDescription }
        }
    }
    private func settingsTitle(_ title: String, description: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 25, weight: .light)).tracking(-0.5); Text(description).font(.system(size: 12)).foregroundStyle(AuraTheme.muted).lineSpacing(5) } }
    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 20, content: content).font(.system(size: 12)).padding(23).frame(maxWidth: .infinity, alignment: .leading).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 13)) }
    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder control: () -> Content) -> some View { HStack { VStack(alignment: .leading, spacing: 6) { Text(title); Text(detail).font(.system(size: 10)).foregroundStyle(AuraTheme.muted) }; Spacer(); control() } }
    private func shortcut(_ action: String, _ keys: String) -> some View { HStack { Text(action).foregroundStyle(AuraTheme.muted); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)) } }
}

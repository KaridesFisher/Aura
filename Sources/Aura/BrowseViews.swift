import SwiftUI
import AuraCore

struct HomeView: View {
    @EnvironmentObject var store: LibraryStore
    private var featured: MediaItem? { store.visibleItems.first { $0.kind == .movie } ?? store.visibleItems.first }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 31) {
                hero
                if !store.continueWatching.isEmpty { shelf("Kaldığın yerden", caption: "Bir dokunuşla devam et", items: Array(store.continueWatching.prefix(8)), playbackHistory: true) }
                if !store.recentlyWatched.isEmpty { shelf("Son izlediklerin", caption: "Filmlerin ve bölümlerin, en yeniden geriye", items: store.recentlyWatched, playbackHistory: true) }
                if store.isDemoOnly { sourceInvitation }
                shelf(store.isDemoOnly ? "Açık sinemadan seçkiler" : "Film gecesi için", caption: store.isDemoOnly ? "Blender Studio · Ücretsiz örnek koleksiyon" : "Kitaplığından keşfet", items: Array(store.visibleItems.filter { $0.kind == .movie }.prefix(12)))
                let favorites = store.visibleItems.filter { store.personal.states[$0.id]?.favorite == true }
                if !favorites.isEmpty { shelf("Senin listen", caption: "Her zaman bir tık uzağında", items: Array(favorites.prefix(8))) }
                shelf("Şimdi yayında", caption: "Canlı akışa katıl", items: Array(store.visibleItems.filter { $0.kind == .live }.prefix(8)))
                if !store.visibleItems.filter({ $0.kind == .series }).isEmpty { shelf("Bir bölüm daha", caption: "Dizi kitaplığın", items: Array(store.visibleItems.filter { $0.kind == .series }.prefix(8))) }
                HStack(spacing: 8) { Image(systemName: "waveform"); Text("Sadece sen ve izlemek istediklerin.").tracking(0.4) }.font(.system(size: 10)).foregroundStyle(AuraTheme.muted.opacity(0.55)).frame(maxWidth: .infinity).padding(.top, 10)
            }.padding(32).padding(.bottom, 12)
        }.scrollIndicators(.hidden)
    }
    private var hero: some View {
        ZStack(alignment: .leading) {
            Artwork(address: store.isDemoOnly ? "bundle:mountains" : featured?.backdrop ?? featured?.artwork)
            LinearGradient(stops: [.init(color: Color(red: 0.055, green: 0.09, blue: 0.10).opacity(0.96), location: 0), .init(color: .black.opacity(0.55), location: 0.48), .init(color: .black.opacity(0.04), location: 1)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(colors: [.clear, .black.opacity(0.34)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) { Circle().fill(AuraTheme.accent).frame(width: 5, height: 5); Text(store.isDemoOnly ? "AURA’YA HOŞ GELDİN" : "KİTAPLIĞINDAN BİR HİKÂYE").tracking(2) }.font(.system(size: 9, weight: .semibold)).foregroundStyle(AuraTheme.accent)
                Text(store.isDemoOnly ? "İyi hikâyelere\nyer aç." : featured?.title ?? "Ekran senin.")
                    .font(.system(size: store.isDemoOnly ? 53 : 42, weight: .light)).tracking(-1.6).lineSpacing(-2).lineLimit(3).padding(.top, 23).frame(maxWidth: 520, alignment: .leading)
                Text(store.isDemoOnly ? "Canlı yayınlar, sevdiğin filmler ve bir bölüm daha.\nHepsi, sana ait sakin bir alanda." : featured?.overview ?? "Bir sonraki favorini kendi koleksiyonunda keşfet.")
                    .font(.system(size: 12)).lineSpacing(6).foregroundStyle(AuraTheme.text.opacity(0.63)).lineLimit(3).frame(maxWidth: 410, alignment: .leading).padding(.top, 16)
                HStack(spacing: 11) {
                    Button { if let featured { store.play(featured) } else { store.showAddSource = true } } label: { Label(store.isDemoOnly ? "Bir filmle başla" : "Şimdi izle", systemImage: "play.fill") }.buttonStyle(AccentButton())
                    Button { store.showAddSource = true } label: { Label("Kaynağını ekle", systemImage: "plus") }.buttonStyle(QuietButton())
                }.padding(.top, 25)
            }.padding(34)
            VStack { Spacer(); HStack { Spacer(); Text(store.isDemoOnly ? "AURA / COLLECTION 001" : "YOUR LIBRARY / YOUR WORLD").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.white.opacity(0.55)).padding(25) } }
        }.frame(height: 378).clipShape(RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.white.opacity(0.08)))
    }
    private var sourceInvitation: some View {
        HStack(spacing: 15) {
            Image(systemName: "square.stack.3d.up").font(.system(size: 20, weight: .light)).foregroundStyle(AuraTheme.accent).frame(width: 43, height: 43).background(AuraTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) { Text("Yayınlarınla tamamlanır.").font(.system(size: 13, weight: .medium)); Text("Xtream bağlantını veya M3U listeni ekle. Aura gerisini düzenlesin.").font(.system(size: 11)).foregroundStyle(AuraTheme.muted) }
            Spacer()
            Button { store.showAddSource = true } label: { HStack(spacing: 7) { Text("Bağlantı ekle"); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .medium)).foregroundStyle(AuraTheme.accent) }.buttonStyle(.plain)
        }.padding(18).background(AuraTheme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(AuraTheme.line))
    }
    private func shelf(_ title: String, caption: String, items: [MediaItem], playbackHistory: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            if !items.isEmpty {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 20, weight: .medium)).tracking(-0.4); Text(caption).font(.system(size: 11)).foregroundStyle(AuraTheme.muted) }
                    Spacer()
                    Text(String(format: "%02d", items.count)).font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted)
                }
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 17) { ForEach(items) { item in MediaCard(item: item, showPlaybackDetails: playbackHistory, playOnTap: playbackHistory).frame(width: 218) } }
                }.scrollIndicators(.hidden)
            }
        }
    }
}

struct CategoryStrip: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(store.categories, id: \.self) { category in
                    Button { store.selectedCategory = category } label: {
                        Text(category).font(.system(size: 11, weight: store.selectedCategory == category ? .semibold : .regular))
                            .foregroundStyle(store.selectedCategory == category ? AuraTheme.background : AuraTheme.muted)
                            .padding(.horizontal, 15).padding(.vertical, 9).background(store.selectedCategory == category ? AuraTheme.accent : AuraTheme.surface, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }.scrollIndicators(.hidden)
    }
}

struct LibraryGrid: View {
    @EnvironmentObject var store: LibraryStore
    @State private var sort = "Varsayılan"
    private var sorted: [MediaItem] {
        switch sort {
        case "Ada göre": return store.currentItems.sorted { store.title($0).localizedStandardCompare(store.title($1)) == .orderedAscending }
        case "En yeni": return store.currentItems.sorted { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        default: return store.currentItems
        }
    }
    var body: some View {
        let results = sorted
        return VStack(spacing: 22) {
            HStack(spacing: 24) {
                CategoryStrip()
                Menu { ForEach(["Varsayılan", "Ada göre", "En yeni"], id: \.self) { value in Button(value) { sort = value } } } label: { Label("Sırala", systemImage: "arrow.up.arrow.down").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(AuraTheme.muted)
            }.padding(.horizontal, 32).padding(.top, 25)
            if results.isEmpty {
                EmptyState(icon: store.destination.icon, title: store.query.isEmpty ? "Burası seninle dolacak." : "Bir eşleşme bulamadık.", message: store.destination == .favorites ? "Sevdiğin bir içeriği yer imine eklediğinde burada bulacaksın." : store.query.isEmpty ? "Bu bölüm için bir kaynak ekleyebilir veya seçili filtreyi değiştirebilirsin." : "Başka bir ad veya daha kısa bir arama dene.", action: store.query.isEmpty && store.destination != .favorites ? "Kaynak ekle" : nil, perform: { store.showAddSource = true })
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 22)], alignment: .leading, spacing: 27) {
                        ForEach(results) { item in MediaCard(item: item, landscape: store.destination == .home || store.destination == .favorites) }
                    }.padding(.horizontal, 32).padding(.bottom, 32)
                }.scrollIndicators(.hidden)
                HStack { Text("\(results.count.formatted()) içerik"); Spacer(); if let source = store.selectedSource, let name = store.sources.first(where: { $0.id == source })?.name { Text(name) } }.font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted).padding(.horizontal, 32).padding(.bottom, 16)
            }
        }
    }
}

struct LiveTVView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selection: MediaItem?
    var body: some View {
        VStack(spacing: 20) {
            CategoryStrip().padding(.horizontal, 32).padding(.top, 24)
            if store.currentItems.isEmpty { EmptyState(icon: "dot.radiowaves.left.and.right", title: "Canlı yayına bağlan.", message: "Xtream veya M3U kaynağını eklediğinde kanalların ve program bilgileri burada görünür.", action: "Kaynak ekle", perform: { store.showAddSource = true }) }
            else {
                HStack(alignment: .top, spacing: 25) {
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(Array(store.currentItems.enumerated()), id: \.element.id) { index, item in
                                Button { selection = item } label: {
                                    HStack(spacing: 12) {
                                        Text(String(format: "%02d", index + 1)).font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted).frame(width: 22)
                                        Artwork(address: item.artwork).frame(width: 42, height: 34).clipShape(RoundedRectangle(cornerRadius: 6))
                                        VStack(alignment: .leading, spacing: 5) { Text(store.title(item)).font(.system(size: 12, weight: .medium)).lineLimit(1); Text(item.category).font(.system(size: 10)).foregroundStyle(AuraTheme.muted).lineLimit(1) }
                                        Spacer(minLength: 4)
                                        if item.archiveDays > 0 { Image(systemName: "clock.arrow.circlepath").font(.system(size: 10)).foregroundStyle(AuraTheme.accent) }
                                    }.padding(12).background(selection?.id == item.id ? AuraTheme.elevated : AuraTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                                }.buttonStyle(.plain).contextMenu {
                                    Button("Oynat") { store.play(item) }; Button("Listeme ekle / çıkar") { store.toggleFavorite(item) }; Button("60 dakika kaydet") { store.transfers.schedule(item) }
                                }
                            }
                        }
                    }.frame(minWidth: 280, maxWidth: 340)
                    if let channel = selection ?? store.currentItems.first { ChannelPanel(channel: channel).id(channel.id) }
                }.padding(.horizontal, 32).padding(.bottom, 25)
            }
        }
    }
}

struct ChannelPanel: View {
    @EnvironmentObject var store: LibraryStore
    let channel: MediaItem
    @State private var recording = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack {
                    LinearGradient(colors: [AuraTheme.elevated, AuraTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                    VStack(spacing: 16) {
                        Artwork(address: channel.artwork).frame(width: 90, height: 64).clipShape(RoundedRectangle(cornerRadius: 10))
                        Text(store.title(channel)).font(.system(size: 22, weight: .medium))
                        Button { store.play(channel) } label: { Label("Canlı izle", systemImage: "play.fill") }.buttonStyle(AccentButton())
                    }
                }.frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
                HStack {
                    Eyebrow(text: "YAYIN AKIŞI"); Spacer()
                    IconButton(icon: "record.circle", help: "Kayıt planla") { recording = true }
                    IconButton(icon: store.personal.states[channel.id]?.favorite == true ? "bookmark.fill" : "bookmark", help: "Listeme ekle / çıkar") { store.toggleFavorite(channel) }
                }
                if let guide = store.guide[channel.id] {
                    if guide.isEmpty { Text("Bu kaynak program bilgisi sağlamıyor.").font(.system(size: 12)).foregroundStyle(AuraTheme.muted).padding(.vertical, 15) }
                    ForEach(guide.filter { $0.end > Date().addingTimeInterval(-86400) }.prefix(80)) { programme in ProgrammeRow(programme: programme, channel: channel) }
                } else { ProgressView().frame(maxWidth: .infinity).padding(25) }
            }
        }.frame(maxWidth: .infinity).task { await store.loadGuide(channel) }
            .sheet(isPresented: $recording) { RecordingSheet(item: channel).environmentObject(store) }
    }
}

struct ProgrammeRow: View {
    @EnvironmentObject var store: LibraryStore
    let programme: GuideProgramme
    let channel: MediaItem
    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text(programme.start, style: .time).font(.system(size: 11, design: .monospaced)).foregroundStyle(programme.isNow ? AuraTheme.accent : AuraTheme.muted).frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(programme.title).font(.system(size: 12, weight: programme.isNow ? .semibold : .regular))
                if !programme.summary.isEmpty { Text(programme.summary).font(.system(size: 10)).foregroundStyle(AuraTheme.muted).lineLimit(2) }
                if programme.isNow { ProgressView(value: programme.progress()).tint(AuraTheme.accent).padding(.top, 2) }
            }
            Spacer(minLength: 4)
            if programme.start > Date() { IconButton(icon: "bell.badge", help: "Hatırlat") { Task { await store.remind(programme) } } }
            else if programme.end < Date() && channel.archiveDays > 0 { IconButton(icon: "play.circle", help: "Arşivden izle") { store.catchup(programme, channel: channel) } }
        }.padding(14).background(programme.isNow ? AuraTheme.accent.opacity(0.045) : AuraTheme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            .contextMenu {
                if programme.start > Date() {
                    Button("Hatırlatıcı ekle") { Task { await store.remind(programme) } }
                    Button("Bu programı kaydet") { store.transfers.schedule(channel, start: programme.start, minutes: max(1, Int(programme.end.timeIntervalSince(programme.start) / 60))) }
                } else if programme.isNow { Button("Canlı izle") { store.play(channel) } }
                else if channel.archiveDays > 0 { Button("Arşivden izle") { store.catchup(programme, channel: channel) } }
            }
    }
}

struct GuideView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var date = Date()
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                CategoryStrip()
                DatePicker("Tarih", selection: $date, displayedComponents: .date).labelsHidden().datePickerStyle(.field).fixedSize()
                Button("Bugün") { date = Date() }.buttonStyle(QuietButton())
                Button("Rehberi yenile") { Task { await store.refreshGuideSources(force: true) } }.buttonStyle(QuietButton()).disabled(!store.guideRefreshingSources.isEmpty)
            }.padding(.horizontal, 32).padding(.top, 23)
            HStack(spacing: 8) {
                if !store.guideRefreshingSources.isEmpty { ProgressView().controlSize(.small); Text("Rehber yenileniyor…") }
                else { Text(store.guideRefreshStatus.isEmpty ? "Her açılışta otomatik yenilenir" : store.guideRefreshStatus) }
                Spacer()
            }.font(.system(size: 10)).foregroundStyle(AuraTheme.muted).padding(.horizontal, 32)
            if store.currentItems.isEmpty { EmptyState(icon: "calendar", title: "Yayınların, bir arada.", message: "Rehberi görmek için canlı TV içeren bir kaynak ekle.", action: "Kaynak ekle", perform: { store.showAddSource = true }) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(store.currentItems) { channel in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack { Artwork(address: channel.artwork).frame(width: 34, height: 26).clipShape(RoundedRectangle(cornerRadius: 4)); Text(store.title(channel)).font(.system(size: 13, weight: .semibold)); if channel.archiveDays > 0 { Label("\(channel.archiveDays) gün arşiv", systemImage: "clock.arrow.circlepath").font(.system(size: 9)).foregroundStyle(AuraTheme.accent) }; Spacer(); Button("İzle") { store.play(channel) }.buttonStyle(QuietButton()) }
                                if let programmes = store.guide[channel.id] {
                                    let filtered = programmes.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }
                                    if filtered.isEmpty { Text("Bu tarih için program bilgisi yok.").font(.system(size: 11)).foregroundStyle(AuraTheme.muted).padding(.vertical, 10) }
                                    else {
                                        ScrollView(.horizontal) {
                                            LazyHStack(spacing: 10) { ForEach(filtered) { programme in ProgrammeRow(programme: programme, channel: channel).frame(width: 320) } }
                                        }.scrollIndicators(.hidden)
                                    }
                                } else { ProgressView().controlSize(.small).padding(10) }
                            }.padding(18).background(AuraTheme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 12)).task { await store.loadGuide(channel) }
                        }
                    }.padding(.horizontal, 32).padding(.bottom, 30)
                }.scrollIndicators(.hidden)
            }
        }
    }
}

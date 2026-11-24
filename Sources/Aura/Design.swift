import SwiftUI
import AuraCore

enum AuraTheme {
    static let background = Color(red: 0.043, green: 0.055, blue: 0.063)
    static let sidebar = Color(red: 0.055, green: 0.069, blue: 0.078)
    static let surface = Color(red: 0.080, green: 0.098, blue: 0.110)
    static let elevated = Color(red: 0.110, green: 0.137, blue: 0.145)
    static let accent = Color(red: 0.62, green: 0.91, blue: 0.79)
    static let text = Color(red: 0.94, green: 0.95, blue: 0.93)
    static let muted = Color(red: 0.53, green: 0.59, blue: 0.61)
    static let line = Color.white.opacity(0.065)
}

struct AccentButton: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 14 : 20).padding(.vertical, compact ? 10 : 13)
            .foregroundStyle(AuraTheme.background).background(AuraTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(AuraTheme.text)
            .padding(.horizontal, 15).padding(.vertical, 11)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.055), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(AuraTheme.line))
    }
}
struct IconButton: View {
    let icon: String
    let help: String
    var size: CGFloat = 16
    let action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size, weight: .medium)).frame(width: 34, height: 34).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(AuraTheme.muted).help(help).accessibilityLabel(help)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(AuraTheme.muted) }
}
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var action: String? = nil
    var perform: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 32, weight: .ultraLight)).foregroundStyle(AuraTheme.accent).frame(width: 76, height: 76)
                .background(AuraTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 24))
            Text(title).font(.system(size: 23, weight: .medium))
            Text(message).font(.system(size: 13)).foregroundStyle(AuraTheme.muted).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 420)
            if let action, let perform { Button(action, action: perform).buttonStyle(AccentButton()).padding(.top, 5) }
        }.padding(50).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct Artwork: View {
    var address: String?
    var title = ""
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [AuraTheme.elevated, AuraTheme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let address, address.hasPrefix("bundle:"), let image = bundled(String(address.dropFirst(7))) {
                    Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else if let address, let url = URL(string: address), ["https", "http"].contains(url.scheme ?? "") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                        else { placeholder }
                    }
                } else { placeholder }
            }
        }.clipped().accessibilityHidden(true)
    }
    private var placeholder: some View {
        VStack(spacing: 10) { Image(systemName: "play.rectangle").font(.system(size: 28, weight: .ultraLight)); if !title.isEmpty { Text(String(title.prefix(1))).font(.system(size: 24, weight: .light, design: .serif)) } }
            .foregroundStyle(AuraTheme.muted.opacity(0.55)).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func bundled(_ name: String) -> NSImage? {
        guard let url = AuraResources.bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/Artwork") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct MediaCard: View {
    @EnvironmentObject var store: LibraryStore
    let item: MediaItem
    var landscape = true
    var showPlaybackDetails = false
    var playOnTap = false
    @State private var hovered = false
    @State private var renaming = false
    @State private var newName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            ZStack(alignment: .bottomLeading) {
                Artwork(address: item.artwork, title: item.title).aspectRatio(landscape ? 1.72 : 0.68, contentMode: .fit)
                LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                if item.kind == .live {
                    Label("CANLI", systemImage: "circle.fill").font(.system(size: 8, weight: .bold)).tracking(1).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 6).background(.black.opacity(0.45), in: Capsule()).padding(12)
                }
                if let state = store.personal.states[item.id], state.displayProgress > 0, item.kind != .live {
                    GeometryReader { g in Rectangle().fill(AuraTheme.accent).frame(width: g.size.width * state.displayProgress, height: 3).frame(maxHeight: .infinity, alignment: .bottom) }
                }
                if hovered {
                    Color.black.opacity(0.15)
                    Image(systemName: "play.fill").font(.system(size: 17)).foregroundStyle(AuraTheme.background)
                        .frame(width: 46, height: 46).background(AuraTheme.accent, in: Circle()).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if hovered || store.personal.states[item.id]?.favorite == true {
                        Button { store.toggleFavorite(item) } label: {
                            Image(systemName: store.personal.states[item.id]?.favorite == true ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 12)).foregroundStyle(.white).frame(width: 30, height: 30).background(.black.opacity(0.55), in: Circle())
                        }.buttonStyle(.plain).padding(9).help("Listeme ekle / çıkar")
                    }
                }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.title(item)).font(.system(size: 13, weight: .medium)).lineLimit(1).foregroundStyle(AuraTheme.text)
                    Text([item.year, item.category].compactMap { $0 }.joined(separator: "  ·  ")).font(.system(size: 11)).foregroundStyle(AuraTheme.muted).lineLimit(1)
                    if showPlaybackDetails, let state = store.personal.states[item.id] {
                        Text(playbackCaption(state)).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(AuraTheme.accent).lineLimit(1)
                    }
                }
                Spacer(minLength: 2)
                if store.personal.states[item.id]?.watched == true { Image(systemName: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(AuraTheme.accent) }
            }
        }.contentShape(Rectangle()).onTapGesture { if playOnTap { store.play(item) } else { store.selectedItem = item } }
            .onHover { hovered = $0 }.animation(.easeOut(duration: 0.15), value: hovered)
            .contextMenu {
                Button("Oynat", systemImage: "play") { store.play(item) }
                Button(store.personal.states[item.id]?.favorite == true ? "Listemden çıkar" : "Listeme ekle", systemImage: "bookmark") { store.toggleFavorite(item) }
                Button("Bilgiler", systemImage: "info.circle") { store.selectedItem = item }
                if item.kind == .episode, let series = store.parentSeries(item) {
                    Button("Dizi sayfası", systemImage: "rectangle.stack") { store.selectedItem = series }
                }
                if item.kind != .live && item.kind != .series {
                    Button("Baştan oynat", systemImage: "backward.end") { store.play(item, fromBeginning: true) }
                    Button("Çevrimdışı indir", systemImage: "arrow.down.circle") { store.transfers.download(item) }
                    Button("İzlendi durumunu değiştir", systemImage: "checkmark.circle") { store.markWatched(item) }
                }
                Divider()
                Button("Yeniden adlandır") { newName = store.title(item); renaming = true }
                Button("Bu kategoriyi gizle") { store.hideCategory(item) }
            }
            .alert("Görünen adı değiştir", isPresented: $renaming) {
                TextField("Ad", text: $newName)
                Button("Kaydet") { if !newName.isEmpty { store.rename(item, to: newName) } }
                Button("Vazgeç", role: .cancel) {}
            }
    }
    private func playbackCaption(_ state: WatchState) -> String {
        let episode = item.kind == .episode ? "S\(item.season ?? 1) B\(item.episode ?? 1) · " : ""
        if state.watched { return episode + "İzlendi" }
        return episode + clockText(state.position) + (state.duration > 0 ? " / " + clockText(state.duration) : " · Devam et")
    }
}

struct WatchProgress: View {
    let state: WatchState
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geometry in
                Capsule().fill(AuraTheme.line)
                Capsule().fill(AuraTheme.accent).frame(width: geometry.size.width * state.displayProgress)
            }.frame(height: 3)
            HStack {
                Text(state.watched ? "İzlendi" : "Kaldığın yer: \(clockText(state.position))")
                Spacer()
                if state.duration > 0 { Text(state.watched ? clockText(state.duration) : "\(clockText(state.position)) / \(clockText(state.duration))") }
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted)
        }.accessibilityElement(children: .combine).accessibilityValue("Yüzde \(Int(state.displayProgress * 100)) izlendi")
    }
}

func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "00:00" }
    let value = Int(seconds)
    return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
}

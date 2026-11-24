import SwiftUI
import AuraCore

@main struct AuraApp: App {
    @NSApplicationDelegateAdaptor(AuraAppDelegate.self) var delegate
    @StateObject private var store: LibraryStore
    init() {
        AuraInstance.acquireOrActivateExisting()
        NSWindow.allowsAutomaticWindowTabbing = false
        _store = StateObject(wrappedValue: LibraryStore())
    }
    var body: some Scene {
        Window("Aura", id: "main") {
            RootView().environmentObject(store).preferredColorScheme(.dark)
                .onAppear { delegate.store = store }
        }
        .defaultSize(width: 1280, height: 800).windowStyle(.hiddenTitleBar).windowResizability(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Kaynak ekle…") { store.showAddSource = true }.keyboardShortcut("n") }
            CommandGroup(replacing: .appSettings) { Button("Ayarlar…") { store.destination = .settings }.keyboardShortcut(",") }
            CommandMenu("Oynatma") {
                Button("Oynat / duraklat") { store.player.togglePause() }.keyboardShortcut(.space, modifiers: [])
                Button("\(store.preferences.seekStep) saniye ileri") { store.player.skip(forward: true) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("\(store.preferences.seekStep) saniye geri") { store.player.skip(forward: false) }.keyboardShortcut(.leftArrow, modifiers: [])
                Divider()
                Button("Altyazılar…") { store.player.showSubtitles = true }.keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Tam ekran") {
                    if let window = NSApp.keyWindow, window.identifier?.rawValue == "main" { window.toggleFullScreen(nil) }
                    else { store.player.toggleFullscreen() }
                }.keyboardShortcut("f", modifiers: [.command, .control])
                Button(store.player.showStats ? "Yayın bilgilerini gizle" : "Yayın bilgileri") { store.player.showStats.toggle() }.keyboardShortcut("i", modifiers: [.command])
                Button("Mini oynatıcı") { store.player.toggleMini() }.keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }

    }
}

@MainActor final class AuraAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    func applicationWillTerminate(_ notification: Notification) {
        store?.player.close(); store?.transfers.shutdown(); store?.flush()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { await store?.refreshGuideSources(force: true) }
        if !flag { NSApp.windows.first(where: { $0.title == "Aura" })?.makeKeyAndOrderFront(nil) }; return true
    }
}

struct RootView: View {
    @EnvironmentObject var store: LibraryStore
        @FocusState private var searchFocused: Bool
    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Rectangle().fill(AuraTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                header
                Rectangle().fill(AuraTheme.line).frame(height: 1)
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
                NowPlayingBar(player: store.player)
            }.background(AuraTheme.background)
        }.foregroundStyle(AuraTheme.text).frame(minWidth: store.playerPresented ? 500 : 960, minHeight: store.playerPresented ? 340 : 640)
            .background(AuraTheme.background).tint(AuraTheme.accent)
            .background(WindowReader { window in
                window.tabbingMode = .disallowed
                window.styleMask.insert(.resizable)
                window.collectionBehavior.remove(.fullScreenNone)
                window.collectionBehavior.insert(.fullScreenPrimary)
                guard !window.styleMask.contains(.fullScreen), let visible = window.screen?.visibleFrame else { return }
                var frame = window.frame
                frame.size.width = min(frame.width, visible.width); frame.size.height = min(frame.height, visible.height)
                frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
                frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))
                if frame != window.frame { window.setFrame(frame, display: true) }
            })
            .sheet(isPresented: $store.showAddSource) { AddSourceSheet().environmentObject(store) }
            .sheet(item: $store.selectedItem) { item in DetailSheet(item: item).environmentObject(store) }
            .sheet(isPresented: $store.showUnlock) { UnlockSheet().environmentObject(store) }
            .alert("Bir sorun oluştu", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("Tamam", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
            .overlay(alignment: .bottom) {
                if let notice = store.notice {
                    HStack(spacing: 10) { Image(systemName: "checkmark.circle.fill").foregroundStyle(AuraTheme.accent); Text(notice).font(.system(size: 12)); Button { store.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
                        .padding(16).background(AuraTheme.elevated, in: RoundedRectangle(cornerRadius: 12)).shadow(color: .black.opacity(0.25), radius: 20).padding(28)
                        .task(id: notice) { try? await Task.sleep(for: .seconds(6)); if store.notice == notice { store.notice = nil } }
                }
            }
            .onChange(of: store.destination) { _, _ in store.selectedCategory = "Tümü"; store.query = "" }
            .overlay {
                if store.playerPresented { PlayerScreen(player: store.player).environmentObject(store) }
            }
            .onReceive(store.player.$current) { if $0 == nil { store.playerPresented = false } }
            .onReceive(store.player.$openSequence.dropFirst()) { _ in searchFocused = false; store.playerPresented = true }
            .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
    }
    private var header: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Eyebrow(text: "KENDİ RİTMİNDE")
                Text(store.destination.title).font(.system(size: 24, weight: .semibold)).tracking(-0.6)
            }
            Spacer()
            if [.home, .live, .movies, .series, .favorites, .guide].contains(store.destination) {
                SearchField(focus: $searchFocused)
            }
            IconButton(icon: "plus", help: "Kaynak ekle") { store.showAddSource = true }
        }.padding(.horizontal, 36).padding(.top, 30).padding(.bottom, 24)
    }
    @ViewBuilder private var content: some View {
        if !store.query.isEmpty && store.destination == .home { LibraryGrid() }
        else {
            switch store.destination {
            case .home: HomeView()
            case .live: LiveTVView()
            case .movies, .series, .favorites: LibraryGrid()
            case .guide: GuideView()
            case .downloads: DownloadsView(manager: store.transfers)
            case .multiview: MultiviewScreen()
            case .sources: SourcesView()
            case .settings: SettingsView()
            }
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("aura").font(.system(size: 34, weight: .light, design: .rounded)).tracking(-1.6)
                Circle().fill(AuraTheme.accent).frame(width: 6, height: 6)
            }.padding(.top, 34).padding(.bottom, 24).padding(.leading, 30)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "KEŞFET").padding(.leading, 30).padding(.bottom, 12)
                    ForEach([Destination.home, .live, .movies, .series, .guide]) { row($0) }
                    Eyebrow(text: "SANA AİT").padding(.leading, 30).padding(.top, 25).padding(.bottom, 12)
                    ForEach([Destination.favorites, .downloads, .multiview]) { row($0) }
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 7) { Circle().fill(AuraTheme.accent).frame(width: 5, height: 5); Text(store.isDemoOnly ? "Önizleme koleksiyonu" : "Kitaplığın hazır").font(.system(size: 11, weight: .medium)) }
                        Text(store.isDemoOnly ? "Kendi yayınlarını ekle, Aura’yı kendine ait kıl." : "\(store.sources.count) kaynak · \(store.items.count.formatted()) içerik").font(.system(size: 11)).lineSpacing(4).foregroundStyle(AuraTheme.muted).fixedSize(horizontal: false, vertical: true)
                        Button { store.showAddSource = true } label: { HStack { Text("Kaynak ekle"); Spacer(); Image(systemName: "plus") } }.buttonStyle(QuietButton())
                    }.padding(16).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 16)
                }
            }.scrollIndicators(.hidden)
            Rectangle().fill(AuraTheme.line).frame(height: 1).padding(.horizontal, 20).padding(.bottom, 10)
            row(.sources); row(.settings)
            HStack { Text("AURA PLAYER"); Spacer(); Text("1.0") }.font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.6).foregroundStyle(AuraTheme.muted.opacity(0.6)).padding(.horizontal, 30).padding(.top, 18).padding(.bottom, 20)
        }.frame(width: 218).background(AuraTheme.sidebar)
    }
    private func row(_ destination: Destination) -> some View {
        let selected = store.destination == destination
        return Button { store.destination = destination } label: {
            HStack(spacing: 12) {
                Image(systemName: selected && destination == .home ? "square.grid.2x2.fill" : destination.icon).font(.system(size: 15, weight: .regular)).frame(width: 20)
                Text(destination.title).font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
                if selected { RoundedRectangle(cornerRadius: 2).fill(AuraTheme.accent).frame(width: 3, height: 14) }
                if destination == .favorites { let count = store.personal.states.values.filter(\.favorite).count; if count > 0 { Text(String(count)).font(.system(size: 10, design: .monospaced)) } }
            }.foregroundStyle(selected ? AuraTheme.accent : AuraTheme.muted)
                .padding(.horizontal, 13).frame(height: 40).background(selected ? AuraTheme.accent.opacity(0.065) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).padding(.horizontal, 17).padding(.vertical, 2)
    }
}

struct NowPlayingBar: View {
    @EnvironmentObject var store: LibraryStore
        @ObservedObject var player: PlaybackController
    var body: some View {
        if let item = player.current {
            HStack(spacing: 14) {
                Artwork(address: item.artwork).frame(width: 62, height: 38).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 4) { Text(store.title(item)).font(.system(size: 12, weight: .medium)); Text(item.kind == .live ? "Canlı yayın" : "\(clockText(player.position)) / \(clockText(player.duration))").font(.system(size: 10)).foregroundStyle(AuraTheme.muted) }
                Spacer()
                IconButton(icon: player.isPlaying ? "pause.fill" : "play.fill", help: "Oynat / duraklat") { player.togglePause() }
                IconButton(icon: "arrow.up.right.square", help: "Oynatıcıyı göster") { store.playerPresented = true }
                IconButton(icon: "xmark", help: "Oynatmayı bitir", size: 12) { player.close() }
            }.padding(.horizontal, 30).padding(.vertical, 12).background(AuraTheme.surface).overlay(alignment: .top) { Rectangle().fill(AuraTheme.line).frame(height: 1) }
        }
    }
}


private struct SearchField: View {
    @EnvironmentObject var store: LibraryStore
    var focus: FocusState<Bool>.Binding
    @State private var draft = ""
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(AuraTheme.muted)
            TextField("Kanal, film veya dizi ara", text: $draft).textFieldStyle(.plain).font(.system(size: 12)).focused(focus)
            if !draft.isEmpty {
                Button { draft = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(AuraTheme.muted)
            } else { Text("⌘ F").font(.system(size: 10, design: .monospaced)).foregroundStyle(AuraTheme.muted) }
        }.padding(.horizontal, 13).frame(width: 278, height: 39).background(AuraTheme.surface, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(AuraTheme.line))
            .onAppear { draft = store.query }
            .onChange(of: store.query) { _, text in if text != draft.trimmingCharacters(in: .whitespacesAndNewlines) { draft = text } }
            .task(id: draft) {
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { await store.search(""); return }
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                await store.search(draft)
            }
    }
}

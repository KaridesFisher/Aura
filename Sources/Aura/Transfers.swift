import SwiftUI
import AuraCore
import CMPV

enum TransferState: String, Codable { case queued, downloading, recording, complete, failed, cancelled }
struct TransferJob: Identifiable, Codable {
    var id = UUID()
    var item: MediaItem
    var state: TransferState
    var progress = 0.0
    var filename: String
    var start: Date?
    var end: Date?
    var error: String?
    var isRecording: Bool
    var createdAt = Date()
}

@MainActor final class TransferManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    weak var store: LibraryStore?
    @Published var jobs: [TransferJob] = []
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var recorders: [UUID: MPVSession] = [:]
    private var timer: Timer?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    override init() {
        super.init()
        do {
            jobs = try Disk.load("transfers.aura", as: [TransferJob].self) ?? []
            for index in jobs.indices where [.downloading, .recording].contains(jobs[index].state) {
                jobs[index].state = .failed; jobs[index].error = "Uygulama kapatıldığı için işlem kesildi. Yeniden başlatabilirsin."
            }
        } catch { jobs = [] }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.updateRecordings() } }
    }
    var activeCount: Int { jobs.filter { [.downloading, .recording, .queued].contains($0.state) }.count }
    private func save() { do { try Disk.save(jobs, name: "transfers.aura") } catch { store?.error = error.localizedDescription } }
    func download(_ item: MediaItem) {
        guard let store else { return }
        do {
            let url = try store.url(item)
            guard !["m3u8", "m3u"].contains(url.pathExtension.lowercased()), item.kind != .live, item.kind != .series else {
                throw AuraError.message("Çevrimdışı indirme doğrudan video dosyalarında kullanılabilir. Canlı yayın için kayıt seçeneğini kullan.")
            }
            let job = TransferJob(item: item, state: .downloading, filename: UUID().uuidString + "." + (url.pathExtension.isEmpty ? "mp4" : url.pathExtension), isRecording: false)
            var request = URLRequest(url: url); request.setValue(store.preferences.userAgent, forHTTPHeaderField: "User-Agent")
            let task = session.downloadTask(with: request); task.taskDescription = job.id.uuidString
            jobs.insert(job, at: 0); tasks[job.id] = task; task.resume(); save()
            store.notice = "İndirme başladı. İndirilenler bölümünden takip edebilirsin."
        } catch { store.error = error.localizedDescription }
    }
    func schedule(_ item: MediaItem, start: Date = Date(), minutes: Int = 60) {
        guard item.kind == .live else { return }
        let job = TransferJob(item: item, state: .queued, filename: UUID().uuidString + ".mkv",
                              start: start, end: start.addingTimeInterval(Double(minutes * 60)), isRecording: true)
        jobs.insert(job, at: 0); save(); updateRecordings()
        store?.notice = start <= Date() ? "Kayıt başladı. Kayıt sürerken Aura’yı açık tut." : "Kayıt planlandı. O saatte Mac’in uyanık ve Aura’nın açık olması gerekiyor."
    }
    func cancel(_ job: TransferJob) {
        tasks[job.id]?.cancel(); tasks[job.id] = nil
        recorders[job.id]?.command("stop"); recorders[job.id] = nil
        guard let i = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        if job.state == .recording {
            let url = fileURL(job)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            jobs[i].state = size > 0 ? .complete : .cancelled
        } else { jobs[i].state = .cancelled }
        save()
    }
    func remove(_ job: TransferJob) { cancel(job); try? FileManager.default.removeItem(at: fileURL(job)); jobs.removeAll { $0.id == job.id }; save() }
    func retry(_ job: TransferJob) { job.isRecording ? schedule(job.item, minutes: 60) : download(job.item) }
    func fileURL(_ job: TransferJob) -> URL { Disk.folder("Downloads").appendingPathComponent(job.filename) }
    func play(_ job: TransferJob) { store?.play(job.item, overrideURL: fileURL(job)) }
    func reveal(_ job: TransferJob) { NSWorkspace.shared.activateFileViewerSelecting([fileURL(job)]) }

    private func updateRecordings() {
        guard let store else { return }
        let now = Date()
        for index in jobs.indices where jobs[index].isRecording {
            let job = jobs[index]
            if job.state == .queued, let start = job.start, now >= start {
                if let end = job.end, now >= end { jobs[index].state = .failed; jobs[index].error = "Planlanan kayıt saati kaçırıldı."; save(); continue }
                do {
                    let url = try store.url(job.item), recorder = try MPVSession(recorder: true)
                    recorder.set("user-agent", store.preferences.userAgent)
                    recorder.set("stream-record", fileURL(job).path)
                    recorder.command("loadfile", url.absoluteString, "replace")
                    recorders[job.id] = recorder; jobs[index].state = .recording; save()
                } catch { jobs[index].state = .failed; jobs[index].error = error.localizedDescription; save() }
            }
            if jobs[index].state == .recording, let start = job.start, let end = job.end {
                jobs[index].progress = min(1, max(0, now.timeIntervalSince(start) / end.timeIntervalSince(start)))
                let event = recorders[job.id].map { aura_mpv_poll($0.handle) } ?? -1
                if event == -1 {
                    recorders[job.id] = nil; jobs[index].state = .failed; jobs[index].error = "Yayın kaydı kesildi. Sağlayıcının eşzamanlı bağlantı sınırını kontrol et."; save()
                } else if event == 1 {
                    recorders[job.id]?.command("stop"); recorders[job.id] = nil
                    let size = (try? fileURL(job).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    jobs[index].state = size > 0 ? .complete : .failed
                    jobs[index].error = "Yayın planlanan süreden önce sona erdi."; save()
                } else if now >= end {
                    recorders[job.id]?.command("stop"); recorders[job.id] = nil
                    let size = (try? fileURL(job).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    jobs[index].state = size > 0 ? .complete : .failed
                    jobs[index].error = size > 0 ? nil : "Kayıt dosyası oluşturulamadı."
                    jobs[index].progress = 1; save()
                }
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let description = downloadTask.taskDescription, let id = UUID(uuidString: description) else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor [weak self] in
            guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { return }
            self.jobs[i].progress = progress
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let description = downloadTask.taskDescription, let id = UUID(uuidString: description) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        // Download delegate temporary files are deleted when this callback returns.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent("aura-download-" + id.uuidString)
        do {
            guard (200..<300).contains(status) else { throw AuraError.message("Sunucu indirmeyi reddetti (\(status)).") }
            try FileManager.default.moveItem(at: location, to: staged)
            Task { @MainActor [weak self] in
                guard let self, let i = self.jobs.firstIndex(where: { $0.id == id }) else { try? FileManager.default.removeItem(at: staged); return }
                guard self.jobs[i].state == .downloading else { try? FileManager.default.removeItem(at: staged); return }
                do { try FileManager.default.moveItem(at: staged, to: self.fileURL(self.jobs[i])); self.jobs[i].state = .complete; self.jobs[i].progress = 1 }
                catch { self.jobs[i].state = .failed; self.jobs[i].error = error.localizedDescription }
                self.tasks[id] = nil; self.save()
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor [weak self] in self?.fail(id, message: message) }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let description = task.taskDescription, let id = UUID(uuidString: description) else { return }
        let message = (error as NSError).code == NSURLErrorCancelled ? "İndirme iptal edildi." : "İndirme kesildi. Bağlantını kontrol edip yeniden dene."
        Task { @MainActor [weak self] in self?.fail(id, message: message) }
    }
    private func fail(_ id: UUID, message: String) {
        guard let i = jobs.firstIndex(where: { $0.id == id }), jobs[i].state != .cancelled else { return }
        jobs[i].state = .failed; jobs[i].error = message; tasks[id] = nil; save()
    }
    func shutdown() { for job in jobs where [.recording, .downloading].contains(job.state) { cancel(job) }; save() }
}

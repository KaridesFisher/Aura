import AppKit
import Darwin

// Acquire before creating LibraryStore: a rejected second process must never
// read/write the shared account or playback files.
enum AuraInstance {
    private static var descriptor: Int32 = -1
    static func acquireOrActivateExisting() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aura", isDirectory: true)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        catch { fail(); return }
        descriptor = open(folder.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { fail(); return }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            if errno == EWOULDBLOCK {
                let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "dev.aura.player")
                    .first { $0.processIdentifier != getpid() }
                existing?.activate(options: [.activateIgnoringOtherApps])
                exit(EXIT_SUCCESS)
            }
            fail(); return
        }
        // The OS releases the lock even after a crash; never unlink this file.
    }
    private static func fail() {
        let alert = NSAlert(); alert.messageText = "Aura başlatılamadı"
        alert.informativeText = "Tek uygulama koruması başlatılamadı. Hesap ve izleme kayıtlarına dokunulmadı."
        alert.runModal(); exit(EXIT_FAILURE)
    }
}

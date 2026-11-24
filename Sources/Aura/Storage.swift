import Foundation
import Security
import CryptoKit
import AuraCore

enum AuraResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Aura_Aura", withExtension: "bundle"), let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()
}

enum Vault {
    // UI automation uses generated demo data and a process-only vault. Production
    // launches always use Keychain; no fallback writes real credentials to disk.
    private static let ephemeral = ProcessInfo.processInfo.environment["AURA_EPHEMERAL"] == "1"
    private static var ephemeralValues: [String: Data] = [:]
    static func read(_ account: String) throws -> Data? {
        if ephemeral { return ephemeralValues[account] }
        var result: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "dev.aura.player.v1", kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AuraError.message("Anahtar Zinciri okunamadı (\(status)).") }
        return result as? Data
    }
    static func save(_ data: Data, account: String) throws {
        if ephemeral { ephemeralValues[account] = data; return }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: "dev.aura.player.v1", kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query; item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let add = SecItemAdd(item as CFDictionary, nil)
            guard add == errSecSuccess else { throw AuraError.message("Bilgiler Anahtar Zinciri’ne kaydedilemedi (\(add)).") }
        } else if status != errSecSuccess { throw AuraError.message("Anahtar Zinciri güncellenemedi (\(status)).") }
    }
    static func remove(_ account: String) {
        if ephemeral { ephemeralValues[account] = nil; return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "dev.aura.player.v1", kSecAttrAccount as String: account] as CFDictionary)
    }
    static func text(_ account: String) -> String { (try? read(account)).flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    static func saveText(_ value: String, _ account: String) throws { try save(Data(value.utf8), account: account) }
}

enum Disk {
    static let root: URL = {
        let url: URL
        if let path = ProcessInfo.processInfo.environment["AURA_DATA_DIR"] { url = URL(fileURLWithPath: path) }
        else { url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aura/v1", isDirectory: true) }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    static func key() throws -> SymmetricKey {
        if let data = try Vault.read("storage-key") { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        try Vault.save(key.withUnsafeBytes { Data($0) }, account: "storage-key"); return key
    }
    static func load<T: Decodable>(_ name: String, as: T.Type) throws -> T? {
        let url = root.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: url))
        let data = try AES.GCM.open(sealed, using: key())
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func save<T: Encodable>(_ value: T, name: String) throws {
        let data = try JSONEncoder().encode(value)
        let sealed = try AES.GCM.seal(data, using: key())
        try sealed.combined!.write(to: root.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
    }
}

struct SavedLibrary: Codable {
    var sources: [PlaylistSource] = []
    var items: [MediaItem] = []
    var personal = PersonalLibrary()
}

struct SavedGuide: Codable {
    var channels: [String: GuideCacheEntry] = [:]
    var refreshedSources: [UUID: Date] = [:]
}

struct PlayerPreferences: Codable, Equatable {
    // Optional additions preserve decoding of existing preference files.
    var subtitlesEnabled: Bool?
    var preferredAudioTitle: String?
    var preferredSubtitleTitle: String?
    var liveLatencyMode: String?
    var livePlaybackMode: LivePlaybackMode {
        get { liveLatencyMode.flatMap(LivePlaybackMode.init(rawValue:)) ?? .lowLatency }
        set { liveLatencyMode = newValue.rawValue }
    }
    var seekSeconds: Int?
    var seekStep: Int {
        get { seekSeconds == 5 ? 5 : 10 }
        set { seekSeconds = newValue == 5 ? 5 : 10 }
    }
    var subtitleLanguage = "tr"
    var audioLanguage = "tr,tur,en,eng"
    var liveFormat = "m3u8"
    var autoReconnect = true
    var autoNext = true
    var rememberPosition = true
    var subtitleSize = 42.0
    var catchupOffset = 0
    var hideAdult = true
    var userAgent = "Aura/1.0"
}

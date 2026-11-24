import Foundation

public enum LivePlaybackMode: String, CaseIterable, Identifiable, Codable {
    case lowLatency, balanced, stable
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .lowLatency: return "En düşük gecikme"
        case .balanced: return "Dengeli"
        case .stable: return "Akıcılık öncelikli"
        }
    }
    public var detail: String {
        switch self {
        case .lowLatency: return "Canlıya en yakın oynatma. Tampon hedefi 3 sn; bağlantı dalgalanırsa takılma artabilir."
        case .balanced: return "Gecikme ve akıcılık arasında denge. Tampon hedefi 8 sn."
        case .stable: return "Bağlantı dalgalanmalarına karşı daha fazla pay. Tampon hedefi 30 sn; canlıdan daha geride başlayabilir."
        }
    }
    public var bufferSeconds: Double {
        switch self { case .lowLatency: return 3; case .balanced: return 8; case .stable: return 30 }
    }
    public var refillSeconds: Double {
        switch self { case .lowLatency: return 1; case .balanced: return 1; case .stable: return 3 }
    }
    public var hlsStartIndex: Int {
        switch self { case .lowLatency: return -1; case .balanced: return -2; case .stable: return -3 }
    }
    /// Apply before opening a file; HLS position and packet cache are independent.
    public var mpvOptions: [String: String] {
        ["cache": "yes", "cache-secs": String(bufferSeconds),
         "demuxer-readahead-secs": String(bufferSeconds), "cache-pause": "yes",
         "cache-pause-wait": String(refillSeconds), "cache-pause-initial": "yes",
         "demuxer-lavf-o": "live_start_index=\(hlsStartIndex)"]
    }
    public static var onDemandOptions: [String: String] {
        ["cache": "yes", "cache-secs": "30", "demuxer-readahead-secs": "30",
         "cache-pause": "yes", "cache-pause-wait": "3", "cache-pause-initial": "no",
         "demuxer-lavf-o": ""]
    }
}

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

public enum M3UParser {
    public static func parse(_ text: String, sourceID: UUID, baseURL: URL? = nil) -> [MediaItem] {
        var attributes: [String: String] = [:], title = "", group = "Genel", result: [MediaItem] = []
        let regex = try! NSRegularExpression(pattern: #"([\w-]+)="([^"]*)""#)
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                attributes = [:]
                let ns = line as NSString
                for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    attributes[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2))
                }
                // Commas inside quoted attribute values are not title delimiters.
                var quoted = false; var delimiter: String.Index?
                for i in line.indices { if line[i] == "\"" { quoted.toggle() }; if line[i] == "," && !quoted { delimiter = i; break } }
                title = delimiter.map { String(line[line.index(after: $0)...]) } ?? attributes["tvg-name"] ?? "Kanal"
                group = attributes["group-title"] ?? "Genel"
            } else if line.hasPrefix("#EXTGRP:") {
                group = String(line.dropFirst(8))
            } else if !line.isEmpty && !line.hasPrefix("#"), let url = URL(string: line, relativeTo: baseURL)?.absoluteURL,
                      ["http", "https", "file"].contains(url.scheme ?? "") {
                let ext = url.pathExtension.lowercased()
                let kind: MediaKind = ["mp4", "mkv", "avi", "mov", "webm"].contains(ext) ? .movie : .live
                // Stable identity across playlist refreshes without storing randomized Swift hash values.
                let hash = line.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
                result.append(MediaItem(sourceID: sourceID, streamID: String(hash), kind: kind,
                                        title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                                        categoryID: group, category: group, artwork: attributes["tvg-logo"],
                                        fileExtension: ext, directURL: url.absoluteString, epgID: attributes["tvg-id"],
                                        isAdult: group.localizedCaseInsensitiveContains("adult")))
                title = ""; attributes = [:]; group = "Genel"
            }
        }
        return result
    }
}

public final class XMLTVParser: NSObject, XMLParserDelegate {
    public private(set) var programmes: [GuideProgramme] = []
    private var channel = "", start: Date?, end: Date?, title = "", summary = "", current = "", text = ""
    private static let formatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMddHHmmss Z"; return f }()
    public static func parse(_ data: Data) throws -> [GuideProgramme] {
        let delegate = XMLTVParser(), parser = XMLParser(data: data)
        parser.delegate = delegate; parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw AuraError.message("XMLTV rehberi okunamadı.") }
        return delegate.programmes.sorted { $0.start < $1.start }
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        current = name; text = ""
        if name == "programme" {
            channel = attributes["channel"] ?? ""; title = ""; summary = ""
            start = Self.formatter.date(from: attributes["start"] ?? ""); end = Self.formatter.date(from: attributes["stop"] ?? "")
        }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "title", title.isEmpty { title = text }
        if name == "desc", summary.isEmpty { summary = text }
        if name == "programme", let start, let end, end > start {
            programmes.append(GuideProgramme(channelID: channel, title: title, summary: summary, start: start, end: end))
        }
        text = ""
    }
}

public struct SubtitleCue: Equatable, Sendable {
    public var start: Double
    public var end: Double
    public var text: String
}

public enum SubtitleParser {
    public static func parse(_ input: String) -> [SubtitleCue] {
        let normalized = input.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let stamps = lines[index].components(separatedBy: "-->")
            guard stamps.count == 2, let start = time(stamps[0]), let end = time(stamps[1].trimmingCharacters(in: .whitespaces).components(separatedBy: " ")[0]), end > start else { return nil }
            let text = lines.dropFirst(index + 1).joined(separator: "\n").replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            return SubtitleCue(start: start, end: end, text: text)
        }.sorted { $0.start < $1.start }
    }
    public static func time(_ input: String) -> Double? {
        let components = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").components(separatedBy: ":")
        guard (2...3).contains(components.count) else { return nil }
        var value = 0.0
        for part in components { guard let number = Double(part), number >= 0 else { return nil }; value = value * 60 + number }
        return value
    }
}

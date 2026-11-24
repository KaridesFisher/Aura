import Foundation

public enum MediaLanguage {
    public static let choices: [(code: String, name: String)] = [("tr", "Türkçe"), ("en", "İngilizce"), ("de", "Almanca"), ("fr", "Fransızca"), ("es", "İspanyolca"), ("it", "İtalyanca"), ("pt", "Portekizce"), ("ar", "Arapça"), ("ru", "Rusça"), ("ja", "Japonca"), ("ko", "Korece"), ("zh", "Çince")]
    public static func canonical(_ value: String) -> String {
        let first = value.lowercased().split(separator: ",").first.map(String.init) ?? ""
        let code = first.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
        return ["tur":"tr", "eng":"en", "deu":"de", "ger":"de", "fra":"fr", "fre":"fr", "spa":"es", "ita":"it", "por":"pt", "ara":"ar", "rus":"ru", "jpn":"ja", "kor":"ko", "zho":"zh", "chi":"zh"][code] ?? code
    }
    public static func name(_ value: String) -> String {
        choices.first { $0.code == canonical(value) }?.name ?? "Bilinmeyen dil"
    }
    public static func mpvCodes(_ value: String) -> String {
        let code = canonical(value)
        return ["tr":"tr,tur", "en":"en,eng", "de":"de,deu,ger", "fr":"fr,fra,fre", "es":"es,spa", "it":"it,ita", "pt":"pt,por", "ar":"ar,ara", "ru":"ru,rus", "ja":"ja,jpn", "ko":"ko,kor", "zh":"zh,zho,chi"][code] ?? code
    }
    public static func preferredIndex(languages: [String], titles: [String], language: String, title: String?) -> Int? {
        let matches = languages.indices.filter { canonical(languages[$0]) == canonical(language) }
        if let title, !title.isEmpty, let exact = matches.first(where: { titles.indices.contains($0) && titles[$0] == title }) { return exact }
        return matches.first
    }
}

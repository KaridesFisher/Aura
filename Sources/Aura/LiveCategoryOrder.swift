import Foundation

/// Turkish groups first; keep provider labels and RAW/HD alternatives intact.
enum LiveCategoryOrder {
    private static let locale = Locale(identifier: "tr_TR")
    private static let countryCodes: Set<String> = [
        "al", "az", "be", "bg", "ca", "ch", "cy", "cz", "de", "dk", "es", "fi", "fr",
        "gr", "hk", "hr", "hu", "il", "it", "kr", "nl", "no", "pl", "pt", "ro", "ru",
        "se", "ua", "uk", "us", "gb", "at", "ba", "rs", "mk", "me", "si", "sk", "ge",
        "am", "ir", "iq", "sa", "ae", "eg", "ma", "tn", "dz", "in", "pk", "cn", "jp", "au"
    ]
    static func sorted(_ categories: [String]) -> [String] {
        categories.sorted { lhs, rhs in
            let a = priority(lhs), b = priority(rhs)
            if a != b { return a < b }
            let order = lhs.compare(rhs, options: [.caseInsensitive, .numeric], locale: locale)
            return order == .orderedSame ? lhs < rhs : order == .orderedAscending
        }
    }
    private static func priority(_ category: String) -> Int {
        let name = category.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .replacingOccurrences(of: "ı", with: "i")
        let prefix = String(name.prefix(2))
        let suffix = name.dropFirst(2)
        if countryCodes.contains(prefix), let first = suffix.first, !first.isLetter { return 200 }
        if name.hasPrefix("ex-yu") { return 200 }
        if name.hasPrefix("ulusal") { return 0 }
        if name.hasPrefix("haber") { return 10 }
        if ["spor ulusal", "s sport", "tivibu spor", "tabii spor", "exxen spor", "bein", "ssein"].contains(where: name.hasPrefix) { return 20 }
        if name.hasPrefix("4k") { return 30 }
        if name.hasPrefix("film / dizi") { return 40 }
        if name.hasPrefix("belgesel") { return 50 }
        if name.hasPrefix("cocuk") { return 60 }
        if name.hasPrefix("muzik") || name.hasPrefix("radyo") { return 70 }
        if name.hasPrefix("dini") || name.hasPrefix("yerel") { return 80 }
        if name.hasPrefix("7/24") || name.hasPrefix("m original") { return 90 }
        return 100
    }
}

import Foundation

public enum MediaSearch {
    public static func matchingIDs(in items: [MediaItem], renamed: [String: String], query: String) -> Set<String> {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var matches = Set<String>()
        for item in items {
            if Task.isCancelled { return [] }
            if (renamed[item.id] ?? item.title).localizedStandardContains(term) || item.category.localizedStandardContains(term) {
                matches.insert(item.id)
            }
        }
        return matches
    }
}

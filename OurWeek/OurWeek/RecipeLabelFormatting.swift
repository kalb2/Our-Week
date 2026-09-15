import Foundation

/// Shared encode/decode for `Recipe.categories` and `Recipe.tags`.
/// Both fields are comma-separated strings (see AddRecipeView / RecipeDetailView).
enum RecipeLabelFormatting {
    static func encodeCategories(_ categories: Set<String>) -> String? {
        let cleaned = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = Set(cleaned).sorted().joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    static func decodeCategories(_ raw: String?) -> Set<String> {
        Set(decodeList(raw))
    }

    static func encodeTags(_ raw: String) -> String? {
        let tags = decodeList(raw)
        return tags.isEmpty ? nil : tags.joined(separator: ", ")
    }

    static func decodeTags(_ raw: String?) -> [String] {
        decodeList(raw)
    }

    static func mergedTags(existing: String?, adding: String) -> String? {
        var seen = Set<String>()
        var result: [String] = []
        for tag in decodeList(existing) + decodeList(adding) {
            let key = tag.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(tag)
        }
        return result.isEmpty ? nil : result.joined(separator: ", ")
    }

    private static func decodeList(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var seen = Set<String>()
        var result: [String] = []
        for part in raw.components(separatedBy: ",") {
            let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = item.lowercased()
            guard !item.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(item)
        }
        return result
    }
}

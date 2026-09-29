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

    static func labelSet(categories: String?, tags: String?) -> Set<String> {
        Set((decodeCategories(categories).union(decodeTags(tags))).map { $0.lowercased() })
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

/// Which recipes can stand in for dinner in the week planner.
/// Uses category and tag text already stored on `Recipe` — not recipe names.
enum RecipePlannerMeals {
    /// Explicit “this is the dinner” marks. `Main` and `Full meal` are category chips;
    /// the other tokens are accepted from tags or imported category text.
    static let qualifyingRoles: Set<String> = [
        "main", "mains", "entree", "entrée", "entrees", "entrées",
        "main entree", "main entrée", "main course", "main dish",
        "full meal", "full meals", "complete meal", "complete dinner"
    ]

    /// Course labels that are not a dinner on their own, even if the recipe is also Dinner.
    static let excludedCourses: Set<String> = [
        "side", "sides", "side dish",
        "dessert", "desserts",
        "snack", "snacks",
        "appetizer", "appetizers", "starter", "starters",
        "drink", "drinks", "beverage", "beverages"
    ]

    /// Existing meal-occasion categories. They count only when the recipe is not an excluded course.
    static let mealOccasions: Set<String> = ["dinner", "lunch"]

    static func includes(categories: String?, tags: String?) -> Bool {
        let labels = RecipeLabelFormatting.labelSet(categories: categories, tags: tags)
        if labels.contains(where: { qualifyingRoles.contains($0) }) { return true }
        if labels.contains(where: { excludedCourses.contains($0) }) { return false }
        return labels.contains(where: { mealOccasions.contains($0) })
    }
}

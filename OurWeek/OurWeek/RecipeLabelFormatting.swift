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

/// Maps imported category text onto the library chips, then suggests Dinner or Main
/// when the recipe would otherwise be missing from Plan week.
enum RecipeImportCategories {
    static func chips(categories: String, tags: String) -> Set<String> {
        var chips = mappedChips(categories)
        chips.formUnion(mappedChips(tags))

        let selected = RecipeLabelFormatting.encodeCategories(chips)
        if RecipePlannerMeals.includes(categories: selected, tags: tags) {
            return chips
        }

        let labels = RecipeLabelFormatting.labelSet(categories: categories, tags: tags)
        if labels.contains(where: { RecipePlannerMeals.excludedCourses.contains($0) }) {
            return chips
        }

        let blob = (categories + " " + tags).lowercased()
        if blob.contains("full meal") || blob.contains("complete meal") || blob.contains("complete dinner") {
            chips.insert("Full meal")
        } else if blob.contains("main") || blob.contains("entree") || blob.contains("entrée") {
            chips.insert("Main")
        } else {
            chips.insert("Dinner")
        }
        return chips
    }

    private static func mappedChips(_ raw: String) -> Set<String> {
        var result: Set<String> = []
        for token in RecipeLabelFormatting.decodeCategories(raw) {
            let lower = token.lowercased()
            if let exact = RecipeConstants.categories.first(where: { $0.lowercased() == lower }) {
                result.insert(exact)
                continue
            }
            if lower.contains("full meal") || lower.contains("complete meal") || lower.contains("complete dinner") {
                result.insert("Full meal")
            } else if lower.contains("main") || lower.contains("entree") || lower.contains("entrée") {
                result.insert("Main")
            } else if lower.contains("breakfast") {
                result.insert("Breakfast")
            } else if lower.contains("lunch") {
                result.insert("Lunch")
            } else if lower.contains("dinner") || lower.contains("supper") {
                result.insert("Dinner")
            } else if lower.contains("dessert") {
                result.insert("Dessert")
            } else if lower.contains("snack") {
                result.insert("Snack")
            } else if lower.contains("side") {
                result.insert("Side")
            } else if lower.contains("appetizer") || lower.contains("starter") {
                result.insert("Appetizer")
            } else if lower.contains("drink") || lower.contains("beverage") {
                result.insert("Drink")
            }
        }
        return result
    }
}

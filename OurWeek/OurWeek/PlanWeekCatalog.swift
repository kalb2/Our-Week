import Foundation

struct PlanCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var emoji: String
    var keywords: [String]
    /// Calendar weekday. Sunday is 1. Nil means no default day.
    var defaultWeekday: Int?

    static let builtIn: [PlanCategory] = [
        PlanCategory(id: "taco", name: "Taco Tuesday", emoji: "🌮", keywords: ["taco", "tacos"], defaultWeekday: 3),
        PlanCategory(id: "crockpot", name: "Crock-Pot", emoji: "🍲", keywords: ["crock", "crockpot", "crock-pot", "slow cooker"], defaultWeekday: nil),
        PlanCategory(id: "movie", name: "Movie / Theme Night", emoji: "🎬", keywords: ["movie", "nacho", "slider", "popcorn"], defaultWeekday: nil),
        PlanCategory(id: "cozy", name: "Cozy", emoji: "🕯️", keywords: ["cozy", "comfort", "casserole", "pot pie", "mac and cheese"], defaultWeekday: nil),
        PlanCategory(id: "sunday", name: "Sunday Dinner", emoji: "🍽️", keywords: ["sunday", "roast", "pot roast", "baked ham"], defaultWeekday: 1),
        PlanCategory(id: "pasta", name: "Pasta Night", emoji: "🍝", keywords: ["pasta", "spaghetti", "noodle", "lasagna", "penne", "rigatoni", "fettuccine"], defaultWeekday: nil),
        PlanCategory(id: "grill", name: "Grill", emoji: "🔥", keywords: ["grill", "grilled", "bbq", "barbecue", "burger"], defaultWeekday: nil),
        PlanCategory(id: "breakfast", name: "Breakfast for Dinner", emoji: "🥞", keywords: ["breakfast", "pancake", "waffle", "omelet", "omelette", "frittata", "french toast"], defaultWeekday: nil),
        PlanCategory(id: "sheetpan", name: "Sheet Pan", emoji: "🥘", keywords: ["sheet pan", "sheet-pan", "tray bake"], defaultWeekday: nil),
        PlanCategory(id: "soup", name: "Soup", emoji: "🥣", keywords: ["soup", "chili", "chowder", "stew", "broth"], defaultWeekday: nil),
        PlanCategory(id: "pizza", name: "Pizza Night", emoji: "🍕", keywords: ["pizza", "flatbread"], defaultWeekday: nil),
        PlanCategory(id: "quick", name: "Quick 30-min", emoji: "⏱️", keywords: ["quick", "30-min", "30 min", "weeknight"], defaultWeekday: nil),
        PlanCategory(id: "leftovers", name: "Leftovers / Eat Out", emoji: "🥡", keywords: ["leftover", "takeout", "take-out", "eat out"], defaultWeekday: nil)
    ]

    static func custom(name: String) -> PlanCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let keywords = words.filter { $0.count >= 3 }
        return PlanCategory(
            id: "custom-\(UUID().uuidString)",
            name: trimmed,
            emoji: "✦",
            keywords: keywords.isEmpty ? [trimmed.lowercased()] : keywords,
            defaultWeekday: nil
        )
    }
}

struct PlanSuggestion: Decodable, Hashable {
    var title: String
    var detail: String
    var emoji: String
}

enum PlanWeekCatalog {
    private struct File: Decodable {
        var suggestions: [String: [PlanSuggestion]]
        var general: [PlanSuggestion]
    }

    private static let loaded: File? = {
        guard let url = Bundle.main.url(forResource: "PlanWeekSuggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static var suggestions: [String: [PlanSuggestion]] { loaded?.suggestions ?? [:] }
    static var general: [PlanSuggestion] { loaded?.general ?? [] }

    static func rows(for category: PlanCategory) -> [PlanSuggestion] {
        if let rows = suggestions[category.id], !rows.isEmpty {
            return rows
        }
        return general
    }

    /// Quick 30-min also matches a recipe whose prep and cook time is 1–30 minutes.
    static func matches(blob: String, minutes: Int, category: PlanCategory) -> Bool {
        if category.id == "quick", minutes > 0, minutes <= 30 {
            return true
        }
        let haystack = blob.lowercased()
        return category.keywords.contains { haystack.contains($0.lowercased()) }
    }
}

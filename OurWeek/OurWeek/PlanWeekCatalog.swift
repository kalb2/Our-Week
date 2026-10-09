import Foundation

struct PlanCategory: Identifiable, Hashable {
    var id: String
    var name: String
    var emoji: String
    var keywords: [String]
    /// Calendar weekday. Sunday is 1. Nil means no default day.
    var defaultWeekday: Int?

    /// Takeout and leftovers are one choice, not a recipe list.
    var usesSingleChoice: Bool {
        id == "takeout" || id == "leftovers"
    }

    static let builtIn: [PlanCategory] = [
        PlanCategory(id: "taco", name: "Taco Tuesday", emoji: "🌮", keywords: ["taco", "tacos", "burrito", "enchilada", "quesadilla", "fajita", "mexican"], defaultWeekday: 3),
        PlanCategory(id: "crockpot", name: "Crock-Pot", emoji: "🍲", keywords: ["crock", "crockpot", "crock-pot", "slow cooker", "braise", "braised"], defaultWeekday: nil),
        PlanCategory(id: "movie", name: "Movie / Theme Night", emoji: "🎬", keywords: ["movie", "nacho", "nachos", "slider", "popcorn"], defaultWeekday: nil),
        PlanCategory(id: "cozy", name: "Cozy", emoji: "🕯️", keywords: ["cozy", "comfort", "casserole", "pot pie", "mac and cheese"], defaultWeekday: nil),
        PlanCategory(id: "sunday", name: "Sunday Dinner", emoji: "🍽️", keywords: ["sunday", "roast", "pot roast", "baked ham"], defaultWeekday: 1),
        PlanCategory(id: "pasta", name: "Pasta Night", emoji: "🍝", keywords: ["pasta", "spaghetti", "noodle", "lasagna", "penne", "rigatoni", "fettuccine"], defaultWeekday: nil),
        PlanCategory(id: "grill", name: "Grill", emoji: "🔥", keywords: ["grill", "grilled", "bbq", "barbecue", "burger"], defaultWeekday: nil),
        PlanCategory(id: "breakfast", name: "Breakfast for Dinner", emoji: "🥞", keywords: ["breakfast", "pancake", "waffle", "omelet", "omelette", "frittata", "french toast"], defaultWeekday: nil),
        PlanCategory(id: "sheetpan", name: "Sheet Pan", emoji: "🥘", keywords: ["sheet pan", "sheet-pan", "tray bake"], defaultWeekday: nil),
        PlanCategory(id: "soup", name: "Soup", emoji: "🥣", keywords: ["soup", "chili", "chowder", "stew"], defaultWeekday: nil),
        PlanCategory(id: "pizza", name: "Pizza Night", emoji: "🍕", keywords: ["pizza", "flatbread"], defaultWeekday: nil),
        PlanCategory(id: "quick", name: "Quick 30-min", emoji: "⏱️", keywords: ["quick", "30-min", "30 min", "weeknight"], defaultWeekday: nil),
        PlanCategory(id: "takeout", name: "Takeout / Eat Out", emoji: "🥡", keywords: ["takeout", "take-out", "eat out"], defaultWeekday: nil),
        PlanCategory(id: "leftovers", name: "Leftovers", emoji: "🍱", keywords: ["leftover", "leftovers"], defaultWeekday: nil)
    ]

    static func custom(name: String) -> PlanCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let stops: Set<String> = ["and", "the", "for", "with", "from", "your"]
        let words = trimmed.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let keywords = words.filter { $0.count >= 3 && !stops.contains($0) }
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
    /// Asset catalog name, such as meal52819. Nil means the row keeps its emoji.
    var image: String?
    var ingredients: [String]

    enum CodingKeys: String, CodingKey {
        case title, detail, emoji, image, ingredients
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        detail = try container.decode(String.self, forKey: .detail)
        emoji = try container.decode(String.self, forKey: .emoji)
        image = try container.decodeIfPresent(String.self, forKey: .image)
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
    }
}

enum PlanWeekCatalog {
    private struct File: Decodable {
        var suggestions: [String: [PlanSuggestion]]
        var general: [PlanSuggestion]
    }

    /// 0 means no match. 1 is a weak ingredient-only hit. 10 or more is a real category match.
    static func score(
        name: String,
        categories: String?,
        tags: String?,
        details: String?,
        ingredients: String,
        minutes: Int,
        category: PlanCategory
    ) -> Int {
        guard isDinnerMain(name: name, categories: categories, tags: tags, categoryID: category.id) else { return 0 }
        if category.usesSingleChoice { return 0 }
        let terms = terms(for: category)
        let identity = [name, categories, tags]
            .compactMap { $0 }
            .joined(separator: " ")
        let hits = terms.filter { containsTerm(identity, $0) }.count
        if hits > 0 { return 10 + hits }
        if category.id == "quick", minutes > 0, minutes <= 30 { return 10 }
        let loose = [details, ingredients].compactMap { $0 }.joined(separator: " ")
        let looseHits = terms.filter { containsTerm(loose, $0) }.count
        return looseHits > 0 ? 1 : 0
    }

    /// Mains can be dinner. Sides, sauces, desserts, drinks, snacks, and breakfast stay out
    /// unless this night is Breakfast for Dinner.
    static func isDinnerMain(name: String, categories: String?, tags: String?, categoryID: String) -> Bool {
        let labels = RecipeLabelFormatting.labelSet(categories: categories, tags: tags)
        if labels.contains(where: { hardExcludedLabels.contains($0) }) { return false }
        if (labels.contains("salad") || labels.contains("salads")) && !titleHasMainForm(name) {
            return false
        }
        let breakfastNight = categoryID == "breakfast"
        if !breakfastNight, labels.contains(where: { breakfastLabels.contains($0) }) { return false }
        if titleIsSide(name) { return false }
        if !breakfastNight, titleIsBreakfast(name) { return false }
        return true
    }

    static func rows(for category: PlanCategory) -> [PlanSuggestion] {
        if category.usesSingleChoice { return [] }
        if let rows = suggestions[category.id], !rows.isEmpty {
            return rows
        }
        return general
    }

    static var suggestions: [String: [PlanSuggestion]] { loaded?.suggestions ?? [:] }
    static var general: [PlanSuggestion] { loaded?.general ?? [] }

    private static let loaded: File? = {
        guard let url = Bundle.main.url(forResource: "PlanWeekSuggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    private static func terms(for category: PlanCategory) -> [String] {
        if let builtIn = strongTerms[category.id] { return builtIn }
        return category.keywords
    }

    /// Whole words and phrases. "bread" does not match "breaded", and "taco" does not match inside another word.
    private static func containsTerm(_ haystack: String, _ term: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term.lowercased())
        return haystack.lowercased().range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil
    }

    private static func titleIsSide(_ name: String) -> Bool {
        let title = name.lowercased()
        if title.hasSuffix(" sauce") || title.hasSuffix(" dressing") || title.hasSuffix(" dip") || title.hasSuffix(" dips") {
            return true
        }
        if titleHasMainForm(title) { return false }
        if sideTerms.contains(where: { containsTerm(title, $0) }) { return true }
        if title.hasPrefix("roasted ") && !containsProtein(title) { return true }
        if starchTerms.contains(where: { containsTerm(title, $0) }) && !containsProtein(title) { return true }
        return false
    }

    private static func titleHasMainForm(_ name: String) -> Bool {
        let title = name.lowercased()
        return mainForms.contains { containsTerm(title, $0) }
    }

    private static func titleIsBreakfast(_ name: String) -> Bool {
        breakfastTitles.contains { containsTerm(name, $0) }
    }

    private static func containsProtein(_ title: String) -> Bool {
        proteinTerms.contains { containsTerm(title, $0) }
    }

    /// Salad is handled separately so a salad sandwich or taco salad can stay.
    private static let hardExcludedLabels: Set<String> = [
        "side", "sides", "side dish", "side dishes",
        "dessert", "desserts",
        "snack", "snacks",
        "appetizer", "appetizers", "starter", "starters",
        "drink", "drinks", "beverage", "beverages",
        "sauce", "sauces", "dressing", "dressings", "dip", "dips",
        "bread", "breads", "baked good", "baked goods", "pastry", "pastries",
        "condiment", "condiments"
    ]

    private static let breakfastLabels: Set<String> = ["breakfast", "brunch"]

    private static let breakfastTitles = [
        "breakfast", "pancake", "pancakes", "waffle", "waffles", "french toast",
        "oatmeal", "overnight oats", "omelet", "omelette", "frittata"
    ]

    /// A title that is a meal even if it also says salad, potato, or rice.
    private static let mainForms = [
        "sandwich", "burger", "soup", "stew", "chili", "casserole",
        "enchilada", "quesadilla", "taco", "tacos", "burrito", "fajita",
        "pizza", "pasta", "lasagna", "lasagne", "curry",
        "stir-fry", "stir fry", "skillet", "pot pie", "shepherd",
        "meatloaf", "meatball", "fried rice", "rice bowl", "wrap", "melt"
    ]

    private static let sideTerms = [
        "side", "salad", "slaw", "coleslaw", "sauce", "dressing", "dip", "dips", "salsa",
        "street corn", "elote",
        "roasted vegetables", "roasted veggies", "roasted potatoes", "mashed potatoes",
        "baked potatoes", "potato wedges", "french fries", "home fries",
        "garlic bread", "dinner rolls", "bread", "roll", "rolls", "biscuit", "biscuits",
        "cornbread", "cookie", "cookies", "cake", "cheesecake", "muffin", "muffins",
        "brownie", "brownies", "cupcake", "cupcakes", "scone", "scones",
        "smoothie", "milkshake", "lemonade", "refried beans"
    ]

    private static let starchTerms = ["rice", "potato", "potatoes"]

    private static let proteinTerms = [
        "chicken", "beef", "pork", "shrimp", "salmon", "tofu", "turkey", "steak",
        "sausage", "lamb", "fish", "tuna", "bean", "beans", "lentil", "chickpea",
        "chorizo", "carnitas"
    ]

    private static let strongTerms: [String: [String]] = [
        "taco": ["taco", "tacos", "burrito", "burritos", "enchilada", "enchiladas", "quesadilla", "quesadillas", "fajita", "fajitas", "mexican", "tamale", "tamales", "tostada", "tostadas"],
        "crockpot": ["slow cooker", "crockpot", "crock pot", "crock-pot", "crock", "braise", "braised"],
        "movie": ["movie", "nacho", "nachos", "slider", "sliders", "popcorn", "theme night"],
        "cozy": ["cozy", "comfort", "casserole", "pot pie", "potpie", "mac and cheese", "macaroni and cheese"],
        "sunday": ["sunday dinner", "pot roast", "baked ham", "prime rib", "roast chicken", "roast beef", "roast", "roasted"],
        "pasta": ["pasta", "spaghetti", "noodle", "noodles", "lasagna", "lasagne", "penne", "rigatoni", "fettuccine", "alfredo", "bolognese", "carbonara"],
        "grill": ["grill", "grilled", "bbq", "barbecue", "burger", "burgers"],
        "breakfast": ["breakfast", "pancake", "pancakes", "waffle", "waffles", "omelet", "omelette", "frittata", "french toast"],
        "sheetpan": ["sheet pan", "sheet-pan", "sheetpan", "tray bake"],
        "soup": ["soup", "chili", "chowder", "stew", "bisque"],
        "pizza": ["pizza", "flatbread"],
        "quick": ["quick", "30-min", "30 min", "30 minute", "weeknight"]
    ]
}

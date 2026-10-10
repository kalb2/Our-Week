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

    var isCustom: Bool { id.hasPrefix("custom-") }

    /// Nights a recipe can be tagged with, including saved custom nights.
    /// Takeout and leftovers are not recipe tags.
    static var recipeNights: [PlanCategory] {
        builtIn.filter { !$0.usesSingleChoice } + CustomNightStore.categories
    }

    static let builtIn: [PlanCategory] = [
        PlanCategory(id: "taco", name: "Taco Tuesday", emoji: "🌮", keywords: ["taco", "tacos", "burrito", "enchilada", "quesadilla", "fajita", "mexican"], defaultWeekday: 3),
        PlanCategory(id: "crockpot", name: "Crock-Pot", emoji: "🍲", keywords: ["crock", "crockpot", "crock-pot", "slow cooker", "braise", "braised"], defaultWeekday: nil),
        PlanCategory(id: "movie", name: "Movie / Theme Night", emoji: "🎬", keywords: ["movie", "nacho", "nachos", "slider", "popcorn"], defaultWeekday: nil),
        PlanCategory(id: "cozy", name: "Cozy", emoji: "🍲", keywords: ["cozy", "comfort", "casserole", "pot pie", "mac and cheese"], defaultWeekday: nil),
        PlanCategory(id: "sunday", name: "Sunday Dinner", emoji: "🍽️", keywords: ["sunday", "roast", "pot roast", "baked ham"], defaultWeekday: 1),
        PlanCategory(id: "pasta", name: "Pasta Night", emoji: "🍝", keywords: ["pasta", "spaghetti", "noodle", "lasagna", "penne", "rigatoni", "fettuccine"], defaultWeekday: nil),
        PlanCategory(id: "grill", name: "Grill", emoji: "🔥", keywords: ["grill", "grilled", "bbq", "barbecue", "burger"], defaultWeekday: nil),
        PlanCategory(id: "breakfast", name: "Breakfast for Dinner", emoji: "🥞", keywords: ["breakfast", "pancake", "waffle", "omelet", "omelette", "frittata", "french toast"], defaultWeekday: nil),
        PlanCategory(id: "sheetpan", name: "Sheet Pan", emoji: "🥘", keywords: ["sheet pan", "sheet-pan", "tray bake"], defaultWeekday: nil),
        PlanCategory(id: "soup", name: "Soup", emoji: "🥣", keywords: ["soup", "chili", "chowder", "stew"], defaultWeekday: nil),
        PlanCategory(id: "pizza", name: "Pizza Night", emoji: "🍕", keywords: ["pizza", "flatbread"], defaultWeekday: nil),
        PlanCategory(id: "quick", name: "Quick 30-min", emoji: "⏱️", keywords: ["quick", "30-min", "30 min", "weeknight"], defaultWeekday: nil),
        PlanCategory(id: "wings", name: "Wings", emoji: "🍗", keywords: ["wing", "wings", "buffalo"], defaultWeekday: nil),
        PlanCategory(id: "asian", name: "Asian", emoji: "🥢", keywords: ["stir fry", "teriyaki", "fried rice", "ramen", "curry"], defaultWeekday: nil),
        PlanCategory(id: "italian", name: "Italian", emoji: "🇮🇹", keywords: ["lasagna", "parmesan", "risotto", "gnocchi"], defaultWeekday: nil),
        PlanCategory(id: "burgers", name: "Burgers & Sandwiches", emoji: "🍔", keywords: ["burger", "sandwich", "wrap", "panini"], defaultWeekday: nil),
        PlanCategory(id: "seafood", name: "Seafood", emoji: "🦐", keywords: ["salmon", "shrimp", "fish"], defaultWeekday: nil),
        PlanCategory(id: "salads", name: "Salads", emoji: "🥗", keywords: ["salad"], defaultWeekday: nil),
        PlanCategory(id: "casserole", name: "Casserole", emoji: "🫕", keywords: ["casserole", "bake", "hotdish"], defaultWeekday: nil),
        PlanCategory(id: "takeout", name: "Takeout / Eat Out", emoji: "🥡", keywords: ["takeout", "take-out", "eat out"], defaultWeekday: nil),
        PlanCategory(id: "leftovers", name: "Leftovers", emoji: "🍱", keywords: ["leftover", "leftovers"], defaultWeekday: nil)
    ]

    /// Custom nights match only by an explicit tag with their name, so they carry no keywords.
    static func custom(name: String) -> PlanCategory {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanCategory(
            id: "custom-\(trimmed.lowercased())",
            name: trimmed,
            emoji: "✦",
            keywords: [],
            defaultWeekday: nil
        )
    }
}

/// Custom week nights the user added, saved so they appear as chips everywhere.
enum CustomNightStore {
    private static let key = "planWeek.customNights"

    static var names: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static var categories: [PlanCategory] {
        names.map { PlanCategory.custom(name: $0) }
    }

    /// Adds a name unless it matches a built-in or saved night. Returns the category to use.
    @discardableResult
    static func add(_ name: String) -> PlanCategory? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = PlanCategory.builtIn.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        var list = names
        if let saved = list.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return PlanCategory.custom(name: saved)
        }
        list.append(trimmed)
        UserDefaults.standard.set(list, forKey: key)
        return PlanCategory.custom(name: trimmed)
    }

    static func remove(_ name: String) {
        let list = names.filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        UserDefaults.standard.set(list, forKey: key)
    }
}

enum PlanWeekCatalog {
    /// 0 means this recipe is not a match for the night.
    /// 30 or more means the recipe's category or tags name the night.
    /// 10 or more means the title uses a strong keyword for the night, or Quick is 30 minutes or under.
    static func score(
        name: String,
        categories: String?,
        tags: String?,
        minutes: Int,
        category: PlanCategory
    ) -> Int {
        guard isDinnerMain(name: name, categories: categories, tags: tags, categoryID: category.id) else { return 0 }
        if category.usesSingleChoice { return 0 }
        let labels = [categories, tags].compactMap { $0 }.joined(separator: " ")
        let explicitHits = explicitTerms(for: category).filter { containsTerm(labels, $0) }.count
        if explicitHits > 0 { return 30 + explicitHits }
        if category.id == "salads" {
            return isMainSalad(name: name, categories: categories, tags: tags) ? 11 : 0
        }
        let titleHits = terms(for: category).filter { containsTerm(name, $0) }.count
        if titleHits > 0 { return 10 + titleHits }
        if category.id == "quick", minutes > 0, minutes <= 30 { return 10 }
        return 0
    }

    /// Mains can be dinner. Sides, sauces, desserts, drinks, snacks, and breakfast stay out
    /// unless this night is Breakfast for Dinner.
    static func isDinnerMain(name: String, categories: String?, tags: String?, categoryID: String) -> Bool {
        let labels = RecipeLabelFormatting.labelSet(categories: categories, tags: tags)
        if labels.contains(where: { hardExcludedLabels.contains($0) }) { return false }
        if categoryID == "salads", isMainSalad(name: name, categories: categories, tags: tags) { return true }
        if (labels.contains("salad") || labels.contains("salads")) && !titleHasMainForm(name) {
            return false
        }
        let breakfastNight = categoryID == "breakfast"
        if !breakfastNight, labels.contains(where: { breakfastLabels.contains($0) }) { return false }
        if titleIsSide(name) { return false }
        if !breakfastNight, titleIsBreakfast(name) { return false }
        return true
    }

    /// A salad counts as dinner only when it is marked Main or names a protein.
    static func isMainSalad(name: String, categories: String?, tags: String?) -> Bool {
        guard containsTerm(name, "salad") || containsTerm(name, "salads") else { return false }
        let labels = RecipeLabelFormatting.labelSet(categories: categories, tags: tags)
        if labels.contains("main") { return true }
        return containsProtein(name) || containsTerm(name, "taco")
    }

    /// The same title check that keeps sides out of dinner picks.
    static func looksLikeSide(_ name: String) -> Bool {
        titleIsSide(name)
    }

    private static func explicitTerms(for category: PlanCategory) -> [String] {
        var terms = [category.name]
        terms.append(contentsOf: Self.terms(for: category))
        return terms
    }

    private static func terms(for category: PlanCategory) -> [String] {
        if let builtIn = strongTerms[category.id] { return builtIn }
        if category.isCustom { return [] }
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
        "condiment", "condiments",
        "other"
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
        "quick": ["quick", "30-min", "30 min", "30 minute", "weeknight"],
        "wings": ["wing", "wings", "buffalo"],
        "asian": ["stir fry", "stir-fry", "teriyaki", "fried rice", "lo mein", "orange chicken", "kung pao", "ramen", "pho", "curry", "thai", "korean", "bulgogi", "sesame", "general tso", "pad thai", "dumpling", "dumplings", "sushi"],
        "italian": ["lasagna", "parmesan", "parm", "risotto", "gnocchi", "marsala", "piccata"],
        "burgers": ["burger", "burgers", "sandwich", "sandwiches", "sliders", "wrap", "wraps", "panini", "sub", "grilled cheese"],
        "seafood": ["salmon", "shrimp", "fish", "tilapia", "cod", "crab", "scallop", "scallops"],
        "salads": [],
        "casserole": ["casserole", "bake", "hotdish"]
    ]
}

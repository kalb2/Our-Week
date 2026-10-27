import Foundation

/// Display-only agreement between a scaled count and the ingredient name:
/// "1 Onion", "½ Onion", "2 Onions". Measured amounts ("2 cups onions") and the
/// stored name are never changed.
enum CountNoun {
    /// Name to show beside `amount` when the unit is a plain count ("" or "whole").
    static func name(_ name: String, amount: Double, unit: String) -> String {
        guard amount > 0, isCount(unit) else { return name }
        let label = CookingAmount.commonFractionText(amount)
        // "½" reads singular; "1" singular; "1½", "2" plural.
        let plural = label != "1" && label.contains(where: { $0.isASCII && $0.isNumber })
        return agreed(name, plural: plural)
    }

    static func isCount(_ unit: String) -> Bool {
        let canonical = CookingAmount.canonicalUnit(unit).lowercased()
        return canonical.isEmpty || ["whole", "each", "count", "ct"].contains(canonical)
    }

    /// Changes only the head noun: the last word before any comma or parenthesis.
    static func agreed(_ name: String, plural: Bool) -> String {
        let cut = name.firstIndex(where: { $0 == "," || $0 == "(" }) ?? name.endIndex
        let head = String(name[..<cut])
        let tail = String(name[cut...])
        let core = head.trimmingCharacters(in: .whitespaces)
        let gap = String(head.reversed().prefix(while: { $0 == " " }))
        var words = core.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        guard let word = words.last, word.count > 2, word.allSatisfy({ $0.isLetter }) else { return name }
        let lower = word.lowercased()
        let base = singular(lower)
        if uncountable.contains(base) || uncountable.contains(lower) { return name }
        let changed = plural ? pluralWord(base) : base
        guard changed != lower else { return name }
        words[words.count - 1] = matchCase(changed, like: word)
        let leading = String(head.prefix(while: { $0 == " " }))
        return leading + words.joined(separator: " ") + gap + tail
    }

    private static let uncountable: Set<String> = [
        "garlic", "salt", "rice", "flour", "sugar", "water", "butter", "oil", "milk",
        "cheese", "parsley", "cilantro", "basil", "ginger", "spinach", "lettuce", "celery", "broth",
        "stock", "cream", "juice", "zest", "honey", "yogurt", "bread", "kale", "meat", "beef", "pork",
        "chicken", "turkey", "salmon", "tuna", "fish", "shrimp", "tofu", "corn", "cumin", "paprika",
        "cinnamon", "vanilla", "mint", "dill", "thyme", "oregano", "rosemary", "sage", "broccoli",
        "cauliflower", "mozzarella", "parmesan", "feta", "cheddar", "ice", "seasoning", "sauce",
        "mayo", "mayonnaise", "mustard", "ketchup", "vinegar", "wine", "beer", "coffee", "tea",
        "cocoa", "chocolate", "salsa", "pesto", "pasta", "spaghetti", "quinoa", "couscous", "oats",
        "chive", "chives", "greens", "grits", "asparagus", "hummus", "lemongrass", "arugula", "foil",
        "bacon", "ham", "sausage", "jam", "syrup", "dough", "spice", "spices", "seed", "seeds"
    ]

    private static let irregularSingular: [String: String] = [
        "leaves": "leaf", "loaves": "loaf", "halves": "half", "knives": "knife"
    ]

    private static func singular(_ word: String) -> String {
        if let irregular = irregularSingular[word] { return irregular }
        if word.hasSuffix("oes"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") || word.hasSuffix("zes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is"), word.count > 3 {
            return String(word.dropLast())
        }
        return word
    }

    private static func pluralWord(_ word: String) -> String {
        if let irregular = irregularSingular.first(where: { $0.value == word })?.key { return irregular }
        if ["tomato", "potato"].contains(word) { return word + "es" }
        if word.hasSuffix("y"), let previous = word.dropLast().last, !"aeiou".contains(previous) {
            return String(word.dropLast()) + "ies"
        }
        if word.hasSuffix("ch") || word.hasSuffix("sh") || word.hasSuffix("x") || word.hasSuffix("z") || word.hasSuffix("ss") {
            return word + "es"
        }
        if word.hasSuffix("s") { return word }
        return word + "s"
    }

    private static func matchCase(_ word: String, like original: String) -> String {
        if original == original.uppercased() { return word.uppercased() }
        if original.first?.isUppercase == true { return word.prefix(1).uppercased() + word.dropFirst() }
        return word
    }
}

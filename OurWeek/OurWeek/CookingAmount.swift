import Foundation

/// Cooking amounts: kitchen measures as fractions, metric and ounce weights as decimals.
enum CookingAmount {
    private static let decimalUnits: Set<String> = [
        "g", "gram", "grams",
        "kg", "kilogram", "kilograms",
        "mg", "milligram", "milligrams",
        "ml", "milliliter", "milliliters", "millilitre", "millilitres",
        "l", "liter", "liters", "litre", "litres",
        "oz", "ounce", "ounces",
        "lb", "lbs", "pound", "pounds",
        "fl oz", "floz", "fluid ounce", "fluid ounces"
    ]

    /// Nearest common cooking fractions, in order.
    private static let steps: [(value: Double, glyph: String)] = [
        (1.0 / 8.0, "⅛"),
        (1.0 / 4.0, "¼"),
        (1.0 / 3.0, "⅓"),
        (3.0 / 8.0, "⅜"),
        (1.0 / 2.0, "½"),
        (5.0 / 8.0, "⅝"),
        (2.0 / 3.0, "⅔"),
        (3.0 / 4.0, "¾"),
        (7.0 / 8.0, "⅞")
    ]

    /// App unit spellings. Long forms such as "teaspoons" become the chip label "tsp".
    static func canonicalUnit(_ unit: String) -> String {
        let trimmed = unit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let lower = trimmed.lowercased()
        if lower.isEmpty { return "" }
        if let alias = unitAliases[lower] { return alias }
        if let match = RecipeConstants.units.first(where: { $0.lowercased() == lower }) {
            return match
        }
        return trimmed
    }

    static func usesFractions(unit: String) -> Bool {
        let normalized = canonicalUnit(unit).lowercased()
        if normalized.isEmpty { return true }
        return !decimalUnits.contains(normalized)
    }

    /// Text for a stored amount. Kitchen units snap to ⅛, ¼, ⅓, ½, ⅔, ¾, and the eighths between them.
    static func format(_ amount: Double, unit: String, fractionsOnly: Bool = false) -> String {
        guard amount > 0 else { return "" }
        if fractionsOnly || usesFractions(unit: unit) {
            return fractionText(snapped(amount))
        }
        return decimalText(amount)
    }

    /// Amount and unit together, e.g. "½ tsp" or "2 cups". Empty when there is no amount.
    /// The unit is plural when the amount is greater than 1. Abbreviations such as tsp stay as they are.
    static func labeled(_ amount: Double, unit: String, fractionsOnly: Bool = false) -> String {
        let amountText = format(amount, unit: unit, fractionsOnly: fractionsOnly)
        let unitText = displayUnit(for: amount, unit: unit)
        return [amountText, unitText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Unit shown next to an amount. Stored units stay singular (`cup`); reading text uses `cups` above 1.
    static func displayUnit(for amount: Double, unit: String) -> String {
        let canonical = canonicalUnit(unit)
        guard !canonical.isEmpty else { return "" }
        let reading = canonical == "pkg" ? "package" : canonical
        guard amount > 1.001 else { return reading }
        switch reading {
        case "cup": return "cups"
        case "can": return "cans"
        case "lb": return "lbs"
        case "slice": return "slices"
        case "clove": return "cloves"
        case "pinch": return "pinches"
        case "dash": return "dashes"
        case "bunch": return "bunches"
        case "sprig": return "sprigs"
        case "stalk": return "stalks"
        case "head": return "heads"
        case "piece": return "pieces"
        case "package": return "packages"
        default: return reading
        }
    }

    /// Amount to store from the editor. The preview already has `fallback`; the text field
    /// only replaces it when the person typed a new number. An empty field keeps `fallback`,
    /// so a fraction glyph is not dropped if the decimal keypad clears it.
    static func amountFromEditor(display: String, fallback: Double, unit: String) -> Double {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return max(0, fallback) }
        if fallback > 0, trimmed == format(fallback, unit: unit) {
            return fallback
        }
        if trimmed == "0" || trimmed == "0.0" { return 0 }
        let parsed = RecipeScraperService.parseAmount(trimmed)
        if parsed > 0 { return parsed }
        return max(0, fallback)
    }

    /// Display line for fields the editor already settled. Does not re-read the name.
    static func plainLine(amount: Double, unit: String, name: String, notes: String = "") -> String {
        let unit = canonicalUnit(unit)
        let label = labeled(amount, unit: unit)
        var fullName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty, !fullName.localizedCaseInsensitiveContains(extra) {
            fullName = fullName.isEmpty ? extra : "\(fullName), \(extra)"
        }
        return [label, fullName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Value to persist. Kitchen units round to the same fraction used for display.
    static func storedValue(_ amount: Double, unit: String) -> Double {
        guard amount > 0 else { return 0 }
        if usesFractions(unit: unit) {
            return snapped(amount)
        }
        return (amount * 100).rounded() / 100
    }

    static func line(amount: Double, unit: String, name: String, notes: String = "") -> String {
        let fixed = RecipeScraperService.normalizedIngredient(
            amount: amount,
            unit: unit,
            name: name,
            notes: notes
        )
        let amountText = fixed.amount > 0 ? format(fixed.amount, unit: fixed.unit) : ""
        let unitText = fixed.amount > 0 ? displayUnit(for: fixed.amount, unit: fixed.unit) : ""
        return [amountText, unitText, fixed.name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Turns a saved line such as "0.5 tsp salt", "1 /2 cup corn", or "2 cup stock" into one kitchen line.
    /// Grams, milliliters, and ounces stay decimal. Lines with no amount are left as written.
    static func reformatLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        // Combined units are already formatted, e.g. "1 can + 2 cups".
        if trimmed.contains(" + ") { return trimmed }
        let parsed = RecipeScraperService.parseIngredientString(trimmed)
        guard parsed.amount > 0 else { return trimmed }
        if parsed.name.hasPrefix("-") || parsed.name.hasPrefix("–") || parsed.name.hasPrefix("%") {
            return trimmed
        }
        return line(amount: parsed.amount, unit: parsed.unit, name: parsed.name, notes: parsed.notes)
    }

    /// Nearest mixed number on the cooking-fraction grid.
    private static func snapped(_ amount: Double) -> Double {
        let whole = floor(amount)
        let remainder = amount - whole
        var bestValue = 0.0
        var bestDistance = abs(remainder)
        for step in steps {
            let distance = abs(remainder - step.value)
            if distance < bestDistance {
                bestValue = step.value
                bestDistance = distance
            }
        }
        if abs(remainder - 1) < bestDistance {
            return whole + 1
        }
        let snapped = whole + bestValue
        if snapped <= 0, amount > 0 {
            return steps[0].value
        }
        return snapped
    }

    /// Kitchen amounts always use a fraction glyph. A near miss still picks the nearest step.
    private static func fractionText(_ amount: Double) -> String {
        let absolute = abs(amount)
        let whole = Int(absolute.rounded(.towardZero))
        let remainder = absolute - Double(whole)
        if remainder < 0.02 {
            return "\(whole)"
        }
        if remainder > 0.94 {
            return "\(whole + 1)"
        }
        let glyph = steps.min(by: { abs($0.value - remainder) < abs($1.value - remainder) })?.glyph ?? "½"
        if whole > 0 {
            return "\(whole)\(glyph)"
        }
        return glyph
    }

    private static let unitAliases: [String: String] = [
        "teaspoon": "tsp", "teaspoons": "tsp", "tsps": "tsp",
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tbs": "tbsp", "tbsps": "tbsp",
        "cups": "cup",
        "ounce": "oz", "ounces": "oz",
        "pound": "lb", "pounds": "lb", "lbs": "lb",
        "gram": "g", "grams": "g",
        "kilogram": "kg", "kilograms": "kg",
        "milligram": "mg", "milligrams": "mg",
        "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
        "liter": "L", "liters": "L", "litre": "L", "litres": "L",
        "fluid ounce": "fl oz", "fluid ounces": "fl oz", "floz": "fl oz",
        "package": "pkg", "packages": "pkg",
        "slices": "slice",
        "cloves": "clove",
        "cans": "can",
        "bunches": "bunch",
        "heads": "head"
    ]

    private static func decimalText(_ amount: Double) -> String {
        if abs(amount - amount.rounded()) < 0.001 {
            return "\(Int(amount.rounded()))"
        }
        let rounded = (amount * 100).rounded() / 100
        var text = String(format: "%.2f", rounded)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) {
            text.removeLast()
        }
        return text
    }
}

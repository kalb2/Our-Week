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
    static func format(_ amount: Double, unit: String) -> String {
        guard amount > 0 else { return "" }
        if usesFractions(unit: unit) {
            return fractionText(snapped(amount))
        }
        return decimalText(amount)
    }

    /// Amount and unit together, e.g. "½ tsp". Empty when there is no amount.
    static func labeled(_ amount: Double, unit: String) -> String {
        let unit = canonicalUnit(unit)
        let amountText = format(amount, unit: unit)
        return [amountText, unit]
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

    static func line(amount: Double, unit: String, name: String) -> String {
        let unit = canonicalUnit(unit)
        let amountText = amount > 0 ? format(amount, unit: unit) : ""
        return [amountText, unit, name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Turns a saved line such as "0.5 tsp salt" back into "½ tsp salt".
    /// Grams, milliliters, and ounces stay decimal.
    static func reformatLine(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, let amount = leadingAmount(parts[0]) else { return trimmed }
        let unit = canonicalUnit(parts[1])
        guard usesFractions(unit: unit) else { return trimmed }
        let amountText = format(amount, unit: unit)
        guard !amountText.isEmpty else { return trimmed }
        let rest = parts.count > 2 ? parts[2] : ""
        return [amountText, unit, rest]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
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
        "cans": "can"
    ]

    private static func leadingAmount(_ token: String) -> Double? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let looksNumeric = trimmed.range(
            of: #"^(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?|[½⅓⅔¼¾⅛⅜⅝⅞]|[0-9]+[½⅓⅔¼¾⅛⅜⅝⅞])$"#,
            options: .regularExpression
        ) != nil
        guard looksNumeric else { return nil }
        let value = RecipeScraperService.parseAmount(trimmed)
        return value > 0 ? value : nil
    }

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

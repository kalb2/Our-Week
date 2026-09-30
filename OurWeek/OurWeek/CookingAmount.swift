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

    static func usesFractions(unit: String) -> Bool {
        let normalized = unit
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
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

    /// Value to persist. Kitchen units round to the same fraction used for display.
    static func storedValue(_ amount: Double, unit: String) -> Double {
        guard amount > 0 else { return 0 }
        if usesFractions(unit: unit) {
            return snapped(amount)
        }
        return (amount * 100).rounded() / 100
    }

    static func line(amount: Double, unit: String, name: String) -> String {
        let amountText = amount > 0 ? format(amount, unit: unit) : ""
        return [amountText, unit, name]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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

    private static func fractionText(_ amount: Double) -> String {
        let whole = Int(amount.rounded(.towardZero))
        let remainder = amount - Double(whole)
        if remainder < 0.001 {
            return "\(whole)"
        }
        guard let glyph = steps.first(where: { abs($0.value - remainder) < 0.001 })?.glyph else {
            return decimalText(amount)
        }
        if whole > 0 {
            return "\(whole)\(glyph)"
        }
        return glyph
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

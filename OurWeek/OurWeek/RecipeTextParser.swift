import Foundation

// MARK: - Recipe Text Parser

/// Parses raw recipe text (pasted from any source) into a structured ScrapedRecipe.
/// Uses heuristics to identify recipe name, ingredients, instructions, servings,
/// prep/cook times, and description — all offline with no API calls.
final class RecipeTextParser {

    /// Parse raw recipe text into a ScrapedRecipe
    static func parse(_ text: String) -> ScrapedRecipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Identify section boundaries
        let sections = identifySections(lines: lines)

        // Extract recipe name
        let title = extractTitle(lines: lines, sections: sections)

        // Extract servings
        let servings = extractServings(from: text, lines: lines)

        // Extract times
        let (prepTime, cookTime) = extractTimes(from: text, lines: lines)

        // Extract ingredients
        let ingredients = extractIngredients(lines: lines, sections: sections)

        // Extract instructions
        let instructions = extractInstructions(lines: lines, sections: sections)

        // Extract description
        let description = extractDescription(lines: lines, sections: sections)

        return ScrapedRecipe(
            title: title,
            description: description,
            ingredients: ingredients,
            instructions: instructions,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            servings: servings,
            imageURL: nil,
            sourceURL: "",
            sourceDomain: "Pasted Text"
        )
    }

    // MARK: - Section Detection

    enum SectionType {
        case title
        case description
        case ingredients
        case instructions
        case notes
        case servings
        case time
        case unknown
    }

    struct Section {
        let type: SectionType
        let headerLineIndex: Int
        let startLineIndex: Int  // first content line (after header)
        var endLineIndex: Int    // last content line (exclusive)
    }

    private static let ingredientHeaders: Set<String> = [
        "ingredients", "ingredient", "ingredient list", "what you need",
        "what you'll need", "you will need", "you'll need", "shopping list"
    ]

    private static let instructionHeaders: Set<String> = [
        "instructions", "instruction", "directions", "direction", "method",
        "steps", "preparation", "how to make", "how to cook", "procedure",
        "how to prepare", "cooking instructions", "cooking directions"
    ]

    private static let notesHeaders: Set<String> = [
        "notes", "note", "tips", "tip", "chef's notes", "cook's notes",
        "recipe notes", "additional notes"
    ]

    private static func identifySections(lines: [String]) -> [Section] {
        var sections: [Section] = []

        for (index, line) in lines.enumerated() {
            let normalized = normalizeHeader(line)

            if ingredientHeaders.contains(normalized) {
                sections.append(Section(
                    type: .ingredients,
                    headerLineIndex: index,
                    startLineIndex: index + 1,
                    endLineIndex: lines.count
                ))
            } else if instructionHeaders.contains(normalized) {
                sections.append(Section(
                    type: .instructions,
                    headerLineIndex: index,
                    startLineIndex: index + 1,
                    endLineIndex: lines.count
                ))
            } else if notesHeaders.contains(normalized) {
                sections.append(Section(
                    type: .notes,
                    headerLineIndex: index,
                    startLineIndex: index + 1,
                    endLineIndex: lines.count
                ))
            }
        }

        // Set end boundaries: each section ends where the next begins
        for i in 0..<sections.count {
            if i + 1 < sections.count {
                sections[i].endLineIndex = sections[i + 1].headerLineIndex
            }
        }

        return sections
    }

    private static func normalizeHeader(_ line: String) -> String {
        var normalized = line.lowercased()
            .trimmingCharacters(in: .whitespaces)
        // Remove trailing colons, dashes, asterisks, hashes
        normalized = normalized.replacingOccurrences(of: "^[#*]+\\s*", with: "", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "[:：\\-–—]+$", with: "", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespaces)
        return normalized
    }

    // MARK: - Title Extraction

    private static func extractTitle(lines: [String], sections: [Section]) -> String {
        // Skip blank lines at the top, take the first non-blank, non-header line
        let sectionHeaderIndices = Set(sections.map { $0.headerLineIndex })

        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else { continue }
            guard !sectionHeaderIndices.contains(index) else { continue }

            // Skip lines that look like metadata (servings, time, etc.)
            if isMetadataLine(line) { continue }

            // Skip lines that look like ingredients (start with numbers + units)
            if looksLikeIngredient(line) { continue }

            // Skip numbered instruction steps
            if looksLikeInstructionStep(line) { continue }

            return line
        }

        return "Pasted Recipe"
    }

    // MARK: - Servings Extraction

    private static func extractServings(from text: String, lines: [String]) -> Int {
        let patterns = [
            "(?:serves?|servings?|yield|makes|portions?)\\s*:?\\s*(\\d+)",
            "(\\d+)\\s+(?:servings?|portions?)"
        ]

        for pattern in patterns {
            if let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let matchStr = String(text[match])
                if let numRange = matchStr.range(of: "\\d+", options: .regularExpression) {
                    if let num = Int(matchStr[numRange]) {
                        return max(1, num)
                    }
                }
            }
        }

        return 1
    }

    // MARK: - Time Extraction

    private static func extractTimes(from text: String, lines: [String]) -> (prep: Int, cook: Int) {
        var prepTime = 0
        var cookTime = 0

        // Prep time patterns
        let prepPatterns = [
            "prep\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)",
            "preparation\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)"
        ]

        for pattern in prepPatterns {
            if let time = extractTimeValue(from: text, pattern: pattern) {
                prepTime = time
                break
            }
        }

        // Cook time patterns
        let cookPatterns = [
            "cook\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)",
            "cooking\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)",
            "bake\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)"
        ]

        for pattern in cookPatterns {
            if let time = extractTimeValue(from: text, pattern: pattern) {
                cookTime = time
                break
            }
        }

        // Total time (if no prep/cook found separately)
        if prepTime == 0 && cookTime == 0 {
            let totalPatterns = [
                "total\\s*(?:time)?\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)",
                "time\\s*:?\\s*(\\d+)\\s*(?:min|minute|hours?|hr)"
            ]
            for pattern in totalPatterns {
                if let time = extractTimeValue(from: text, pattern: pattern) {
                    cookTime = time
                    break
                }
            }
        }

        return (prepTime, cookTime)
    }

    private static func extractTimeValue(from text: String, pattern: String) -> Int? {
        guard let match = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let matchStr = String(text[match])

        // Extract the number
        guard let numRange = matchStr.range(of: "\\d+", options: .regularExpression) else {
            return nil
        }
        guard let value = Int(matchStr[numRange]) else { return nil }

        // Check if it's hours
        let lower = matchStr.lowercased()
        if lower.contains("hour") || lower.contains("hr") {
            return value * 60
        }

        return value
    }

    // MARK: - Ingredient Extraction

    private static func extractIngredients(lines: [String], sections: [Section]) -> [ScrapedIngredient] {
        // If we found an ingredients section header, use that range
        if let ingredientSection = sections.first(where: { $0.type == .ingredients }) {
            let sectionLines = Array(lines[ingredientSection.startLineIndex..<ingredientSection.endLineIndex])
            return parseIngredientLines(sectionLines)
        }

        // Fallback: scan all lines for ingredient-like patterns (before any instruction section)
        let instructionStart = sections.first(where: { $0.type == .instructions })?.headerLineIndex ?? lines.count
        var ingredientLines: [String] = []
        var foundIngredientBlock = false

        for (index, line) in lines.enumerated() {
            guard index < instructionStart else { break }
            guard !line.isEmpty else {
                // A blank line after we've found ingredients might end the block
                if foundIngredientBlock && !ingredientLines.isEmpty {
                    // Check if the next non-blank line is also an ingredient
                    let remaining = lines[(index + 1)...]
                    if let nextNonBlank = remaining.first(where: { !$0.isEmpty }) {
                        if !looksLikeIngredient(nextNonBlank) {
                            break
                        }
                    }
                }
                continue
            }

            if looksLikeIngredient(line) {
                ingredientLines.append(line)
                foundIngredientBlock = true
            }
        }

        return parseIngredientLines(ingredientLines)
    }

    private static func parseIngredientLines(_ lines: [String]) -> [ScrapedIngredient] {
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            // Skip sub-headers within ingredient sections
            let normalized = normalizeHeader(trimmed)
            if ingredientHeaders.contains(normalized) { return false }
            return true
        }

        return filtered.map { line in
            // Remove leading bullet points, dashes, asterisks
            let cleaned = line.replacingOccurrences(
                of: "^[\\-•·*▪▸►◆○●]\\s*",
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespaces)

            // Reuse the existing ingredient parser
            return RecipeScraperService.parseIngredientString(cleaned)
        }
    }

    // MARK: - Instruction Extraction

    private static func extractInstructions(lines: [String], sections: [Section]) -> [String] {
        // If we found an instructions section header, use that range
        if let instructionSection = sections.first(where: { $0.type == .instructions }) {
            let sectionLines = Array(lines[instructionSection.startLineIndex..<instructionSection.endLineIndex])
            return parseInstructionLines(sectionLines)
        }

        // Fallback: look for numbered steps anywhere
        var instructionLines: [String] = []

        for line in lines {
            guard !line.isEmpty else { continue }
            if looksLikeInstructionStep(line) {
                instructionLines.append(line)
            }
        }

        return parseInstructionLines(instructionLines)
    }

    private static func parseInstructionLines(_ lines: [String]) -> [String] {
        let filtered = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            let normalized = normalizeHeader(trimmed)
            if instructionHeaders.contains(normalized) { return false }
            return true
        }

        return filtered.map { line in
            // Remove leading step numbers like "1.", "1)", "Step 1:", "Step 1."
            var cleaned = line.replacingOccurrences(
                of: "^(?:step\\s*)?\\d+[.):\\-]?\\s*",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            // Remove leading bullet points
            cleaned = cleaned.replacingOccurrences(
                of: "^[\\-•·*▪▸►◆○●]\\s*",
                with: "",
                options: .regularExpression
            )
            return cleaned.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: - Description Extraction

    private static func extractDescription(lines: [String], sections: [Section]) -> String {
        // Description is usually between the title and the first section header
        guard !lines.isEmpty else { return "" }

        let firstSectionStart = sections.first?.headerLineIndex ?? lines.count

        // Skip the title (first non-blank line) and collect text until the first section
        var foundTitle = false
        var descriptionLines: [String] = []

        for (index, line) in lines.enumerated() {
            guard index < firstSectionStart else { break }
            guard !line.isEmpty else {
                if foundTitle && !descriptionLines.isEmpty {
                    // Preserve paragraph breaks
                    descriptionLines.append("")
                }
                continue
            }

            if !foundTitle {
                // Skip the title line
                if !isMetadataLine(line) && !looksLikeIngredient(line) && !looksLikeInstructionStep(line) {
                    foundTitle = true
                    continue
                }
            }

            // Skip metadata lines (servings, time, etc.)
            if isMetadataLine(line) { continue }

            // Skip lines that look like ingredients
            if looksLikeIngredient(line) { continue }

            // Accumulate description
            if foundTitle {
                descriptionLines.append(line)
            }
        }

        // Trim trailing blank lines
        while descriptionLines.last?.isEmpty == true {
            descriptionLines.removeLast()
        }

        return descriptionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Line Classification Helpers

    private static func isMetadataLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        let metadataPatterns = [
            "^(?:serves?|servings?|yield|makes|portions?)\\s*:?\\s*\\d+",
            "^(?:prep|cook|total|bake|baking)\\s*(?:time)?\\s*:?\\s*\\d+",
            "^(?:calories|cal|kcal)\\s*:?\\s*\\d+",
            "^(?:course|cuisine|category|diet)\\s*:",
            "^(?:author|source|from|adapted|recipe by)\\s*:"
        ]

        for pattern in metadataPatterns {
            if lower.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }

    static func looksLikeIngredient(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Remove leading bullet/dash
        let cleaned = trimmed.replacingOccurrences(
            of: "^[\\-•·*▪▸►◆○●]\\s*",
            with: "",
            options: .regularExpression
        )

        // Check for unicode fractions at the start
        let unicodeFractions: [Character] = ["½", "⅓", "⅔", "¼", "¾", "⅛", "⅜", "⅝", "⅞", "⅕", "⅖", "⅗", "⅘", "⅙", "⅚"]
        if let first = cleaned.first, unicodeFractions.contains(first) {
            return true
        }

        // Starts with a number followed by common units or ingredient text
        let ingredientPattern = "^\\d+[/\\d]*\\s*(?:tsp|tbsp|tablespoon|teaspoon|cup|oz|ounce|lb|pound|g|gram|kg|ml|liter|litre|pinch|dash|clove|can|pkg|package|slice|whole|bunch|sprig|stalk|head|piece|quart|pint|gallon|small|medium|large|extra)?"
        if cleaned.range(of: ingredientPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            // Make sure it's not a numbered instruction step
            // Instructions typically have more words and form sentences
            let wordCount = cleaned.components(separatedBy: .whitespaces).count
            if wordCount <= 8 {
                return true
            }
            // If it has a unit keyword right after the number, it's likely an ingredient
            let unitCheck = "^\\d+[/\\d]*\\s*(?:tsp|tbsp|tablespoon|teaspoon|cup|oz|ounce|lb|pound|g|gram|kg|ml|liter|litre|pinch|dash|clove|can|pkg|package|slice)"
            if cleaned.range(of: unitCheck, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }

        return false
    }

    private static func looksLikeInstructionStep(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        // Numbered step patterns: "1.", "1)", "Step 1:", "Step 1."
        let stepPattern = "^(?:step\\s+)?\\d+[.):]\\s+"
        if trimmed.range(of: stepPattern, options: [.regularExpression, .caseInsensitive]) != nil {
            // Make sure it's long enough to be an instruction (not just "1. salt")
            let wordCount = trimmed.components(separatedBy: .whitespaces).count
            if wordCount >= 4 {
                return true
            }
        }

        return false
    }
}

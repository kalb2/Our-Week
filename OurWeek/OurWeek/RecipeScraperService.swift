import Foundation

// MARK: - Scraped Recipe Models

struct ScrapedRecipe: Identifiable {
    let id = UUID()
    var title: String
    var description: String
    var ingredients: [ScrapedIngredient]
    var instructions: [String]
    var prepTimeMinutes: Int
    var cookTimeMinutes: Int
    var servings: Int
    var imageURL: String?
    var sourceURL: String
    var sourceDomain: String
}

struct ScrapedIngredient: Identifiable {
    let id = UUID()
    var amount: Double
    var unit: String
    var name: String
    var notes: String
}

// MARK: - Scraper Errors

enum ScraperError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case timeout
    case noRecipeFound(html: String)
    case paywallDetected
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Please enter a valid URL"
        case .networkError(let detail):
            return "Couldn't connect. \(detail)"
        case .timeout:
            return "This is taking too long. The website might be slow or blocking us."
        case .noRecipeFound:
            return "This website doesn't support automatic import. You can add the recipe manually instead."
        case .paywallDetected:
            return "This recipe may require a subscription. Try copying the recipe text manually."
        case .parsingFailed(let detail):
            return "Couldn't read the recipe data. \(detail)"
        }
    }
}

// MARK: - Recipe Scraper Service

final class RecipeScraperService {

    /// Import a recipe from a URL by fetching the page and parsing Schema.org JSON-LD data.
    static func importRecipe(from urlString: String) async throws -> ScrapedRecipe {
        // 1. Validate URL
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            throw ScraperError.invalidURL
        }

        // 2. Fetch HTML
        let html = try await fetchHTML(from: url)

        // 3. Check for paywall indicators
        if html.contains("subscribe to continue") || html.contains("paywall") ||
           html.contains("subscription required") {
            throw ScraperError.paywallDetected
        }

        // 4. Extract JSON-LD blocks
        let jsonLDBlocks = extractJSONLD(from: html)

        // 5. Find Recipe object
        guard let recipeJSON = findRecipeJSON(in: jsonLDBlocks) else {
            throw ScraperError.noRecipeFound(html: html)
        }

        // 6. Parse into ScrapedRecipe
        let domain = url.host?.replacingOccurrences(of: "www.", with: "") ?? ""

        return parseRecipe(from: recipeJSON, sourceURL: trimmed, sourceDomain: domain, html: html)
    }

    // MARK: - HTML Fetching

    private static func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                         forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw ScraperError.timeout
            }
            throw ScraperError.networkError("Check your internet connection.")
        } catch {
            throw ScraperError.networkError("Check your internet connection.")
        }

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200...299: break
            case 401, 403:
                throw ScraperError.paywallDetected
            case 404:
                throw ScraperError.noRecipeFound(html: "")
            default:
                throw ScraperError.networkError("Server returned status \(httpResponse.statusCode).")
            }
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
            throw ScraperError.parsingFailed("Could not read page content.")
        }

        return html
    }

    // MARK: - JSON-LD Extraction

    private static func extractJSONLD(from html: String) -> [Any] {
        var results: [Any] = []
        let endTag = "</script>"
        var searchRange = html.startIndex..<html.endIndex

        // Search for "application/ld+json" anywhere in a script tag
        // This handles <script type="application/ld+json">,
        // <script type="application/ld+json" class="yoast-schema-graph">,
        // <script type='application/ld+json'>, etc.
        while let ldJsonRange = html.range(of: "application/ld+json", options: .caseInsensitive, range: searchRange) {
            // Find the closing > of the script tag after the ld+json marker
            guard let tagClose = html.range(of: ">", range: ldJsonRange.upperBound..<html.endIndex) else {
                break
            }
            let contentStart = tagClose.upperBound

            guard let endRange = html.range(of: endTag, options: .caseInsensitive, range: contentStart..<html.endIndex) else {
                break
            }

            let jsonString = String(html[contentStart..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
                results.append(json)
            }

            searchRange = endRange.upperBound..<html.endIndex
        }

        return results
    }


    // MARK: - Find Recipe in JSON-LD

    private static func findRecipeJSON(in blocks: [Any]) -> [String: Any]? {
        for block in blocks {
            if let dict = block as? [String: Any] {
                if let found = findRecipeInDict(dict) {
                    return found
                }
            } else if let array = block as? [[String: Any]] {
                for dict in array {
                    if let found = findRecipeInDict(dict) {
                        return found
                    }
                }
            }
        }
        return nil
    }

    private static func findRecipeInDict(_ dict: [String: Any]) -> [String: Any]? {
        // Direct match
        if let type = dict["@type"] as? String, type == "Recipe" {
            return dict
        }
        // Array of types (e.g. ["Recipe", "Thing"])
        if let types = dict["@type"] as? [String], types.contains("Recipe") {
            return dict
        }
        // Check @graph
        if let graph = dict["@graph"] as? [[String: Any]] {
            for item in graph {
                if let found = findRecipeInDict(item) {
                    return found
                }
            }
        }
        return nil
    }

    // MARK: - Parse Recipe JSON

    private static func parseRecipe(from json: [String: Any], sourceURL: String, sourceDomain: String, html: String) -> ScrapedRecipe {
        let title = json["name"] as? String ?? "Imported Recipe"
        let description = json["description"] as? String ?? ""

        // Ingredients
        let rawIngredients = json["recipeIngredient"] as? [String] ?? []
        let ingredients = rawIngredients.map { parseIngredientString($0) }

        // Instructions
        let instructions = parseInstructions(from: json)

        // Times
        let prepTime = parseISO8601Duration(json["prepTime"] as? String)
        let cookTime = parseISO8601Duration(json["cookTime"] as? String)

        // Servings
        let servings = parseServings(json["recipeYield"])

        // Image
        let imageURL = parseImageURL(from: json, html: html)

        return ScrapedRecipe(
            title: title,
            description: cleanHTML(description),
            ingredients: ingredients,
            instructions: instructions,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            servings: servings,
            imageURL: imageURL,
            sourceURL: sourceURL,
            sourceDomain: sourceDomain
        )
    }

    // MARK: - Instruction Parsing

    private static func parseInstructions(from json: [String: Any]) -> [String] {
        // Could be array of HowToStep, array of strings, or a single string
        if let stepsArray = json["recipeInstructions"] as? [[String: Any]] {
            return stepsArray.compactMap { step in
                // HowToStep or HowToSection
                if let text = step["text"] as? String {
                    return cleanHTML(text).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // HowToSection with itemListElement
                if let items = step["itemListElement"] as? [[String: Any]] {
                    return items.compactMap { $0["text"] as? String }
                        .map { cleanHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .joined(separator: "\n")
                }
                return nil
            }.filter { !$0.isEmpty }
        }

        if let stepsStrings = json["recipeInstructions"] as? [String] {
            return stepsStrings.map { cleanHTML($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        if let singleString = json["recipeInstructions"] as? String {
            // Split by numbered steps, double newlines, or periods followed by capital letters
            let cleaned = cleanHTML(singleString)
            let lines = cleaned.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if lines.count > 1 {
                return lines.map { line in
                    // Remove leading step numbers like "1." or "1)"
                    line.replacingOccurrences(of: "^\\d+[.)\\s]+", with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return [cleaned]
        }

        return []
    }

    // MARK: - ISO 8601 Duration Parsing

    static func parseISO8601Duration(_ duration: String?) -> Int {
        guard let duration = duration, duration.hasPrefix("PT") || duration.hasPrefix("P") else { return 0 }

        var totalMinutes = 0
        let str = duration.uppercased()

        // Handle days
        if let dMatch = str.range(of: "\\d+D", options: .regularExpression) {
            let num = str[dMatch].dropLast()
            totalMinutes += (Int(num) ?? 0) * 1440
        }

        // Handle hours
        if let hMatch = str.range(of: "\\d+H", options: .regularExpression) {
            let num = str[hMatch].dropLast()
            totalMinutes += (Int(num) ?? 0) * 60
        }

        // Handle minutes
        if let mMatch = str.range(of: "\\d+M", options: .regularExpression) {
            let num = str[mMatch].dropLast()
            totalMinutes += Int(num) ?? 0
        }

        return totalMinutes
    }

    // MARK: - Servings Parsing

    private static func parseServings(_ value: Any?) -> Int {
        if let intVal = value as? Int { return max(1, intVal) }
        if let strVal = value as? String {
            // Extract first number from string like "4 servings" or "4-6"
            if let match = strVal.range(of: "\\d+", options: .regularExpression) {
                return max(1, Int(strVal[match]) ?? 1)
            }
        }
        if let arr = value as? [Any], let first = arr.first {
            return parseServings(first)
        }
        return 1
    }

    // MARK: - Image URL Extraction

    private static func parseImageURL(from json: [String: Any], html: String) -> String? {
        // 1. From JSON-LD image field
        if let imageStr = json["image"] as? String, !imageStr.isEmpty {
            return imageStr
        }
        if let imageDict = json["image"] as? [String: Any], let url = imageDict["url"] as? String {
            return url
        }
        if let imageArray = json["image"] as? [Any] {
            if let first = imageArray.first as? String {
                return first
            }
            if let firstDict = imageArray.first as? [String: Any], let url = firstDict["url"] as? String {
                return url
            }
        }

        // 2. Fallback: og:image meta tag
        if let ogMatch = html.range(of: "og:image[^>]*content=\"([^\"]+)\"", options: .regularExpression) {
            let matched = String(html[ogMatch])
            if let contentRange = matched.range(of: "content=\"([^\"]+)\"", options: .regularExpression) {
                let content = String(matched[contentRange])
                    .replacingOccurrences(of: "content=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                return content
            }
        }

        return nil
    }

    // MARK: - Ingredient String Parsing

    static func parseIngredientString(_ raw: String) -> ScrapedIngredient {
        let cleaned = cleanHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for "to taste" type ingredients
        let lowerCleaned = cleaned.lowercased()
        if lowerCleaned.hasSuffix("to taste") || lowerCleaned == "to taste" {
            let name = cleaned.replacingOccurrences(of: ",?\\s*to taste", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ScrapedIngredient(amount: 0, unit: "", name: name.isEmpty ? cleaned : name, notes: "to taste")
        }

        var remaining = cleaned
        var amount: Double = 0
        var unit: String = ""
        var notes: String = ""

        // Extract amount (fractions, decimals, mixed numbers)
        let (parsedAmount, afterAmount) = extractAmount(from: remaining)
        amount = parsedAmount
        remaining = afterAmount

        // Extract unit
        let unitPatterns = [
            "tablespoons", "tablespoon", "tbsp", "tbs",
            "teaspoons", "teaspoon", "tsp",
            "cups", "cup",
            "ounces", "ounce", "oz",
            "pounds", "pound", "lbs", "lb",
            "grams", "gram", "g",
            "kilograms", "kilogram", "kg",
            "milliliters", "milliliter", "ml",
            "liters", "liter", "l",
            "pinch", "pinches",
            "dash", "dashes",
            "cloves", "clove",
            "cans", "can",
            "packages", "package", "pkg",
            "slices", "slice",
            "whole",
            "bunch", "bunches",
            "sprigs", "sprig",
            "stalks", "stalk",
            "heads", "head",
            "pieces", "piece",
            "quarts", "quart", "qt",
            "pints", "pint", "pt",
            "gallons", "gallon", "gal"
        ]

        let trimmedRemaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        for pattern in unitPatterns {
            if trimmedRemaining.lowercased().hasPrefix(pattern) {
                let afterUnit = trimmedRemaining.dropFirst(pattern.count)
                // Make sure the unit isn't part of a longer word
                if afterUnit.isEmpty || afterUnit.first == " " || afterUnit.first == "." {
                    unit = normalizeUnit(pattern)
                    remaining = String(afterUnit).trimmingCharacters(in: .whitespacesAndNewlines)
                    // Remove leading "of" if present
                    if remaining.lowercased().hasPrefix("of ") {
                        remaining = String(remaining.dropFirst(3))
                    }
                    break
                }
            }
        }

        // Extract notes (stuff in parentheses or after comma)
        if let parenRange = remaining.range(of: "\\(([^)]+)\\)", options: .regularExpression) {
            notes = String(remaining[parenRange])
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            remaining = remaining.replacingCharacters(in: parenRange, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let commaIndex = remaining.firstIndex(of: ",") {
            let afterComma = String(remaining[remaining.index(after: commaIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !afterComma.isEmpty {
                notes = notes.isEmpty ? afterComma : "\(notes), \(afterComma)"
            }
            remaining = String(remaining[..<commaIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let name = remaining.trimmingCharacters(in: .whitespacesAndNewlines)

        return ScrapedIngredient(
            amount: amount,
            unit: unit,
            name: name.isEmpty ? cleaned : name,
            notes: notes
        )
    }

    // MARK: - Amount Extraction

    /// Parses a string containing numbers or fractions (e.g. "1 1/2", "0.25", "1/4") into a decimal amount
    static func parseAmount(_ text: String) -> Double {
        return extractAmount(from: text).0
    }

    private static func extractAmount(from text: String) -> (Double, String) {
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var total: Double = 0

        // Unicode fractions map
        let unicodeFractions: [Character: Double] = [
            "½": 0.5, "⅓": 1.0/3.0, "⅔": 2.0/3.0,
            "¼": 0.25, "¾": 0.75, "⅛": 0.125,
            "⅜": 3.0/8.0, "⅝": 5.0/8.0, "⅞": 7.0/8.0,
            "⅕": 0.2, "⅖": 0.4, "⅗": 0.6, "⅘": 0.8,
            "⅙": 1.0/6.0, "⅚": 5.0/6.0
        ]

        // Try whole number first
        if let match = remaining.range(of: "^\\d+", options: .regularExpression) {
            let numStr = String(remaining[match])
            let wholeNum = Double(numStr) ?? 0
            remaining = String(remaining[match.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)

            // Check for fraction after whole number (e.g., "1 1/2" or "1½")
            if let firstChar = remaining.first, let frac = unicodeFractions[firstChar] {
                total = wholeNum + frac
                remaining = String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let fracMatch = remaining.range(of: "^(\\d+)/(\\d+)", options: .regularExpression) {
                let fracStr = String(remaining[fracMatch])
                let parts = fracStr.components(separatedBy: "/")
                if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), den > 0 {
                    total = wholeNum + num / den
                }
                remaining = String(remaining[fracMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if remaining.hasPrefix("/") {
                // "1/2" case where we already consumed "1"
                let afterSlash = String(remaining.dropFirst())
                if let denMatch = afterSlash.range(of: "^\\d+", options: .regularExpression) {
                    let den = Double(afterSlash[denMatch]) ?? 1
                    if den > 0 {
                        total = wholeNum / den
                    }
                    remaining = String(afterSlash[denMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    total = wholeNum
                }
            } else if remaining.hasPrefix("-") || remaining.hasPrefix("–") {
                // Range like "2-3" — use first value
                total = wholeNum
                if let rangeMatch = remaining.range(of: "^[-–]\\d+", options: .regularExpression) {
                    remaining = String(remaining[rangeMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else {
                total = wholeNum
            }
        } else if let firstChar = remaining.first, let frac = unicodeFractions[firstChar] {
            // Standalone unicode fraction
            total = frac
            remaining = String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (total, remaining)
    }

    // MARK: - Unit Normalization

    private static func normalizeUnit(_ raw: String) -> String {
        let lower = raw.lowercased()
        switch lower {
        case "tablespoons", "tablespoon", "tbs": return "tbsp"
        case "teaspoons", "teaspoon": return "tsp"
        case "cups": return "cup"
        case "ounces", "ounce": return "oz"
        case "pounds", "pound", "lbs": return "lb"
        case "grams", "gram": return "g"
        case "kilograms", "kilogram": return "kg"
        case "milliliters", "milliliter": return "ml"
        case "liters", "liter": return "L"
        case "pinches": return "pinch"
        case "dashes": return "dash"
        case "cloves": return "clove"
        case "cans": return "can"
        case "packages", "package": return "pkg"
        case "slices": return "slice"
        case "bunches": return "bunch"
        case "sprigs": return "sprig"
        case "stalks": return "stalk"
        case "heads": return "head"
        case "pieces": return "piece"
        case "quarts", "quart": return "qt"
        case "pints", "pint": return "pt"
        case "gallons", "gallon": return "gal"
        default: return lower
        }
    }

    // MARK: - HTML Cleaning

    private static func cleanHTML(_ text: String) -> String {
        var result = text
        // Remove HTML tags
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // Decode common HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "&#x27;", with: "'")
        return result
    }

    // MARK: - Image Download

    static func downloadImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                return data
            }
        } catch {
            print("Image download failed: \(error)")
        }
        return nil
    }
}

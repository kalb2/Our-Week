import Foundation
import UIKit

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
    /// Comma-separated labels from the page or the model. Empty when unknown.
    var categories: String = ""
    var tags: String = ""
    /// Easy, Medium, or Hard when the source says so. Empty when unknown.
    var difficulty: String = ""
    /// Photo the user attached. Preview uses this when there is no remote image.
    var inlineImageData: Data? = nil
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
    case paywallDetected(html: String)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Enter a full link"
        case .networkError(_), .timeout:
            return "Couldn't open that page"
        case .noRecipeFound(_), .paywallDetected(_):
            return "Couldn't read a recipe from this page"
        case .parsingFailed(_):
            return "Couldn't read that page"
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
            throw ScraperError.paywallDetected(html: html)
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
                let page = String(data: data, encoding: .utf8) ?? ""
                throw ScraperError.paywallDetected(html: page)
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

    /// Page title from common meta tags, for a manual add after import fails.
    static func suggestedTitle(from html: String) -> String? {
        let sample = String(html.prefix(120_000))
        let patterns = [
            #"(?i)<meta[^>]*property\s*=\s*["']og:title["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"(?i)<meta[^>]*content\s*=\s*["']([^"']+)["'][^>]*property\s*=\s*["']og:title["']"#,
            #"(?i)<meta[^>]*name\s*=\s*["']twitter:title["'][^>]*content\s*=\s*["']([^"']+)["']"#,
            #"(?i)<title[^>]*>([^<]+)</title>"#
        ]
        for pattern in patterns {
            guard let raw = firstMatch(pattern, in: sample) else { continue }
            let cleaned = decodeHTML(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }

    /// Text to drop into paste import. Uses the page body when it looks like a recipe, otherwise the title.
    static func pasteSeed(from html: String, title: String) -> String {
        let plain = plainText(from: html)
        if plain.range(of: "ingredient", options: .caseInsensitive) != nil, plain.count >= 80 {
            return String(plain.prefix(8_000))
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle + "\n\n"
        }
        return ""
    }

    private static func plainText(from html: String) -> String {
        var text = String(html.prefix(200_000))
        text = replacing(text, pattern: "(?is)<script\\b[^>]*>.*?</script>", with: " ")
        text = replacing(text, pattern: "(?is)<style\\b[^>]*>.*?</style>", with: " ")
        text = replacing(text, pattern: "(?is)<[^>]+>", with: " ")
        text = decodeHTML(text)
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return words.joined(separator: " ")
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func replacing(_ text: String, pattern: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func decodeHTML(_ text: String) -> String {
        var decoded = text
        let entities = [
            "&amp;": "&",
            "&quot;": "\"",
            "&#39;": "'",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&nbsp;": " "
        ]
        for (entity, value) in entities {
            decoded = decoded.replacingOccurrences(of: entity, with: value)
        }
        return decoded
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
        let title = (json["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let description = json["description"] as? String ?? ""

        let ingredients = scrapedIngredients(from: json["recipeIngredient"])
        let instructions = instructionTexts(from: json["recipeInstructions"])

        var prepTime = flexibleMinutes(json["prepTime"])
        var cookTime = flexibleMinutes(json["cookTime"])
        if cookTime == 0 {
            cookTime = flexibleMinutes(json["performTime"])
        }
        if prepTime == 0 && cookTime == 0 {
            cookTime = flexibleMinutes(json["totalTime"])
        }

        let servings = flexibleServings(json["recipeYield"], fallback: 1)
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
            sourceDomain: sourceDomain,
            categories: joinedLabels(json["recipeCategory"]),
            tags: joinedLabels(json["keywords"])
        )
    }

    static func joinedLabels(_ value: Any?) -> String {
        if value is NSNull { return "" }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dict = value as? [String: Any] {
            return joinedLabels(dict["name"] ?? dict["text"])
        }
        if let list = value as? [Any] {
            return list
                .map { joinedLabels($0) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        return ""
    }

    /// Ingredients from a string, a list of strings, or objects (`name`/`amount`/`text`).
    static func scrapedIngredients(from value: Any?) -> [ScrapedIngredient] {
        guard let value, !(value is NSNull) else { return [] }
        if let text = value as? String {
            return text
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { parseIngredientString($0) }
        }
        if let dict = value as? [String: Any] {
            return scrapedIngredients(from: [dict])
        }
        guard let list = value as? [Any] else { return [] }
        return list.compactMap { item -> ScrapedIngredient? in
            if let text = item as? String {
                let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return line.isEmpty ? nil : parseIngredientString(line)
            }
            if let dict = item as? [String: Any] {
                return ingredient(from: dict)
            }
            return nil
        }
    }

    private static func ingredient(from dict: [String: Any]) -> ScrapedIngredient? {
        let explicitName = firstString(dict, keys: ["name", "item", "ingredient"])
        let line = firstString(dict, keys: ["text", "raw", "description", "name", "item", "ingredient"])
        let hasAmount = dict["amount"] != nil || dict["quantity"] != nil || dict["qty"] != nil
        let unit = firstString(dict, keys: ["unit", "units"]) ?? ""
        let notes = firstString(dict, keys: ["notes", "note", "comment"]) ?? ""

        var resolvedUnit = unit
        var resolvedAmount = dict["amount"] ?? dict["quantity"] ?? dict["qty"]
        if let quantity = dict["requiredQuantity"] as? [String: Any] {
            if resolvedAmount == nil {
                resolvedAmount = quantity["value"] ?? quantity["amount"]
            }
            if resolvedUnit.isEmpty {
                resolvedUnit = firstString(quantity, keys: ["unitText", "unit", "unitCode"]) ?? ""
            }
        }
        if resolvedUnit.isEmpty {
            resolvedUnit = firstString(dict, keys: ["unitText"]) ?? ""
        }

        if hasAmount || !resolvedUnit.isEmpty || resolvedAmount != nil, let explicitName, !explicitName.isEmpty {
            let fixed = normalizedIngredient(
                amount: flexibleAmount(resolvedAmount),
                unit: resolvedUnit,
                name: explicitName,
                notes: notes
            )
            return ScrapedIngredient(
                amount: fixed.amount,
                unit: fixed.unit,
                name: fixed.name,
                notes: fixed.notes
            )
        }

        guard let line, !line.isEmpty else { return nil }
        var parsed = parseIngredientString(line)
        if parsed.notes.isEmpty, !notes.isEmpty {
            parsed.notes = notes
        }
        return parsed
    }

    private static func firstString(_ dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = dict[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    /// Steps from a string, a list of strings, or HowToStep / `{text|step}` objects.
    static func instructionTexts(from value: Any?) -> [String] {
        guard let value, !(value is NSNull) else { return [] }
        if let text = value as? String {
            return splitInstructionBlob(text)
        }
        if let dict = value as? [String: Any] {
            if let items = dict["itemListElement"] {
                let nested = instructionTexts(from: items)
                if !nested.isEmpty { return nested }
            }
            let line = firstString(dict, keys: ["text", "step", "name", "instruction"])
            guard let line, !line.isEmpty else { return [] }
            let cleaned = stripStepPrefix(cleanHTML(line))
            return cleaned.isEmpty ? [] : [cleaned]
        }
        guard let list = value as? [Any] else { return [] }
        return list.flatMap { instructionTexts(from: $0) }
    }

    private static func splitInstructionBlob(_ raw: String) -> [String] {
        let cleaned = cleanHTML(raw)
        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { stripStepPrefix($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        if !lines.isEmpty { return lines }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : [trimmed]
    }

    private static func stripStepPrefix(_ line: String) -> String {
        line.replacingOccurrences(
            of: "^\\s*(?:\\d+[.)]|[•\\-–—*])\\s+",
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Minutes from an ISO duration, a number, a loose phrase, or a Duration object.
    static func flexibleMinutes(_ value: Any?) -> Int {
        if value is NSNull || value == nil { return 0 }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return 0 }
            if trimmed.uppercased().hasPrefix("P") {
                return parseISO8601Duration(trimmed)
            }
            return parseLooseDuration(trimmed)
        }
        if let number = jsonNumber(value) {
            return max(0, Int(number.rounded()))
        }
        if let dict = value as? [String: Any] {
            return flexibleMinutes(dict["value"] ?? dict["name"] ?? dict["text"])
        }
        return 0
    }

    /// Numeric amount, including integer JSON numbers and fraction strings like "1/2".
    static func flexibleAmount(_ value: Any?) -> Double {
        if value is NSNull || value == nil { return 0 }
        if let text = value as? String {
            return parseAmount(text)
        }
        if let number = jsonNumber(value) {
            return number
        }
        return 0
    }

    /// JSON integers and decimals. Excludes JSON booleans, which bridge as NSNumber 0/1.
    private static func jsonNumber(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.doubleValue
    }

    static func flexibleServings(_ value: Any?, fallback: Int = 1) -> Int {
        if value is NSNull || value == nil { return fallback }
        if let text = value as? String {
            if let match = text.range(of: "\\d+", options: .regularExpression),
               let number = Int(text[match]), number > 0 {
                return number
            }
            return fallback
        }
        if let number = jsonNumber(value) {
            let parsed = Int(number.rounded())
            return parsed > 0 ? parsed : fallback
        }
        if let list = value as? [Any], let first = list.first {
            return flexibleServings(first, fallback: fallback)
        }
        if let dict = value as? [String: Any] {
            return flexibleServings(dict["value"] ?? dict["name"], fallback: fallback)
        }
        return fallback
    }

    private static func parseLooseDuration(_ text: String) -> Int {
        let lower = text.lowercased()
        var minutes = 0
        var matched = false
        if let hours = firstInt(in: lower, pattern: "(\\d+)\\s*(?:hours?|hrs?)\\b") {
            minutes += hours * 60
            matched = true
        }
        if let mins = firstInt(in: lower, pattern: "(\\d+)\\s*(?:minutes?|mins?)\\b") {
            minutes += mins
            matched = true
        }
        if matched { return minutes }
        return firstInt(in: lower, pattern: "(\\d+)") ?? 0
    }

    private static func firstInt(in text: String, pattern: String) -> Int? {
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        let slice = String(text[match])
        guard let digits = slice.range(of: "\\d+", options: .regularExpression) else { return nil }
        return Int(slice[digits])
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

    /// Join a split fraction and peel a unit left in the name. Does not erase a name or amount already present.
    static func normalizedIngredient(amount: Double, unit: String, name: String, notes: String) -> (amount: Double, unit: String, name: String, notes: String) {
        let originalAmount = amount
        let originalUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var amount = amount
        var unit = originalUnit
        var name = normalizeFractionText(name).trimmingCharacters(in: .whitespacesAndNewlines)
        var notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if unit.isEmpty {
            let candidate = quantityCandidate(amount: amount, name: name)
            if !candidate.isEmpty {
                let parsed = parseIngredientString(candidate)
                if parsed.amount > 0,
                   !parsed.name.hasPrefix("-"),
                   !parsed.name.hasPrefix("–"),
                   !parsed.name.hasPrefix("%") {
                    amount = parsed.amount
                    unit = parsed.unit
                    name = parsed.name
                    if notes.isEmpty { notes = parsed.notes }
                }
            }
            if unit.isEmpty, let peeled = peelLeadingUnit(from: name) {
                unit = peeled.unit
                name = peeled.rest
            }
        }

        // Detail and the editor only show `name`. A comma used to hide the rest in notes.
        if !notes.isEmpty, !name.localizedCaseInsensitiveContains(notes) {
            name = name.isEmpty ? notes : "\(name), \(notes)"
            notes = ""
        }

        // A repair must not erase an ingredient that already had a name or an amount.
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = originalName
        }
        if amount <= 0, originalAmount > 0 {
            amount = originalAmount
            if unit.isEmpty { unit = originalUnit }
        }

        return (amount, CookingAmount.canonicalUnit(unit), name, notes)
    }

    /// `1` + `/2 cups corn`, or a name that still starts with `1/2`, becomes one line to parse.
    private static func quantityCandidate(amount: Double, name: String) -> String {
        if amount > 0, abs(amount - amount.rounded()) < 0.001,
           name.range(of: #"^/\d+"#, options: .regularExpression) != nil {
            return "\(Int(amount.rounded()))\(name)"
        }
        if name.range(of: #"^(?:\d|[½⅓⅔¼¾⅛⅜⅝⅞⅕⅖⅗⅘⅙⅚])"#, options: .regularExpression) != nil {
            return name
        }
        return ""
    }

    static func parseIngredientString(_ raw: String) -> ScrapedIngredient {
        let cleaned = normalizeFractionText(cleanHTML(raw)).trimmingCharacters(in: .whitespacesAndNewlines)

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

        if let peeled = peelLeadingUnit(from: remaining) {
            unit = peeled.unit
            remaining = peeled.rest
        }

        let name = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = (name.isEmpty && amount <= 0 && unit.isEmpty) ? cleaned : name

        return ScrapedIngredient(
            amount: amount,
            unit: unit,
            name: resolvedName,
            notes: notes
        )
    }

    // MARK: - Amount Extraction

    /// Parses a string containing numbers or fractions (e.g. "1 1/2", "0.25", "1/4") into a decimal amount
    static func parseAmount(_ text: String) -> Double {
        return extractAmount(from: text).0
    }

    /// Fraction slashes and spaced `1 / 2` become `1/2` before the amount is read.
    static func normalizeFractionText(_ text: String) -> String {
        var result = text
        for slash in ["⁄", "∕", "／", "⧸"] {
            result = result.replacingOccurrences(of: slash, with: "/")
        }
        let entities = [
            "&frac12;": "½", "&frac14;": "¼", "&frac34;": "¾",
            "&frac13;": "⅓", "&frac23;": "⅔", "&frasl;": "/"
        ]
        for (entity, glyph) in entities {
            result = result.replacingOccurrences(of: entity, with: glyph, options: .caseInsensitive)
        }
        result = result.replacingOccurrences(
            of: #"(\d)\s*/\s*(\d)"#,
            with: "$1/$2",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"/\s+(\d)"#,
            with: "/$1",
            options: .regularExpression
        )
        let numericEntities = [
            "&#189;": "½", "&#188;": "¼", "&#190;": "¾",
            "&#8531;": "⅓", "&#8532;": "⅔"
        ]
        for (entity, glyph) in numericEntities {
            result = result.replacingOccurrences(of: entity, with: glyph, options: .caseInsensitive)
        }
        return result
    }

    /// Longest unit words first so "cups" is not read as something shorter.
    private static let unitWords = [
        "tablespoons", "tablespoon", "tbsp", "tbs",
        "teaspoons", "teaspoon", "tsp",
        "cups", "cup",
        "ounces", "ounce", "oz",
        "pounds", "pound", "lbs", "lb",
        "kilograms", "kilogram", "kg",
        "grams", "gram",
        "milliliters", "milliliter", "ml",
        "liters", "liter",
        "pinches", "pinch",
        "dashes", "dash",
        "cloves", "clove",
        "packages", "package", "pkg",
        "slices", "slice",
        "bunches", "bunch",
        "sprigs", "sprig",
        "stalks", "stalk",
        "heads", "head",
        "pieces", "piece",
        "quarts", "quart", "qt",
        "pints", "pint", "pt",
        "gallons", "gallon", "gal",
        "cans", "can",
        "g", "l"
    ]

    private static func peelLeadingUnit(from text: String) -> (unit: String, rest: String)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for pattern in unitWords {
            guard lower.hasPrefix(pattern) else { continue }
            let after = trimmed.dropFirst(pattern.count)
            if after.isEmpty || after.first == " " || after.first == "." || after.first == "," {
                var rest = after.trimmingCharacters(in: .whitespacesAndNewlines)
                if rest.lowercased().hasPrefix("of ") {
                    rest = String(rest.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return (normalizeUnit(pattern), rest)
            }
        }
        return nil
    }

    private static func extractAmount(from text: String) -> (Double, String) {
        var remaining = normalizeFractionText(text).trimmingCharacters(in: .whitespacesAndNewlines)
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
            } else if let decMatch = remaining.range(of: #"^\.\d+"#, options: .regularExpression) {
                let decStr = "0" + remaining[decMatch]
                total = wholeNum + (Double(decStr) ?? 0)
                remaining = String(remaining[decMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if remaining.hasPrefix("/") {
                // "1/2" case where we already consumed "1"
                let afterSlash = String(remaining.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                if let denMatch = afterSlash.range(of: "^\\d+", options: .regularExpression) {
                    let den = Double(afterSlash[denMatch]) ?? 1
                    if den > 0 {
                        total = wholeNum / den
                    }
                    remaining = String(afterSlash[denMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    total = wholeNum
                }
            } else if let rangeMatch = remaining.range(of: "^[-–]\\d+", options: .regularExpression) {
                // Range like "2-3" — use the first value
                total = wholeNum
                remaining = String(remaining[rangeMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if remaining.hasPrefix("-") || remaining.hasPrefix("–") {
                // "15-oz" stays in the ingredient name
                return (0, normalizeFractionText(text).trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                total = wholeNum
            }
        } else if let decMatch = remaining.range(of: #"^\.\d+"#, options: .regularExpression) {
            let decStr = "0" + remaining[decMatch]
            total = Double(decStr) ?? 0
            remaining = String(remaining[decMatch.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Skip payloads larger than this so a single import can't balloon memory.
    private static let maxDownloadBytes = 8 * 1024 * 1024
    /// After decode/downscale, don't persist more than this in Core Data.
    private static let maxStoredBytes = 1_200_000
    private static let maxPixelDimension: CGFloat = 1600

    /// Downloads a recipe hero image. Returns JPEG/original bytes suitable for `Recipe.imageData`,
    /// or `nil` if the URL is empty/invalid, the request fails, or the payload is too large.
    static func downloadImage(from urlString: String) async -> Data? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("Image download failed: HTTP \(httpResponse.statusCode)")
                return nil
            }
            if data.count > maxDownloadBytes {
                print("Image download skipped: payload too large (\(data.count) bytes)")
                return nil
            }
            return preparedHeroImageData(from: data)
        } catch {
            print("Image download failed: \(error)")
        }
        return nil
    }

    /// Decodes a downloaded payload and downscales/compresses huge photos so imports stay light.
    private static func preparedHeroImageData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        let alreadySmall = data.count <= maxStoredBytes && longest <= maxPixelDimension
        if alreadySmall {
            return data
        }

        let scaled = resizeIfNeeded(image, maxDimension: maxPixelDimension)
        var quality: CGFloat = 0.82
        guard var jpeg = scaled.jpegData(compressionQuality: quality) else { return nil }
        while jpeg.count > maxStoredBytes, quality > 0.45 {
            quality -= 0.12
            guard let next = scaled.jpegData(compressionQuality: quality) else { break }
            jpeg = next
        }
        if jpeg.count > maxStoredBytes * 2 {
            print("Image skipped after compress: still \(jpeg.count) bytes")
            return nil
        }
        return jpeg
    }

    private static func resizeIfNeeded(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let newSize = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

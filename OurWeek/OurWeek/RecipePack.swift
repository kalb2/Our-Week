import Foundation

// MARK: - Recipe Pack Models

/// On-disk format for bulk-importing pre-extracted recipes.
///
/// ```
/// {
///   "format": "ourweek-recipe-pack",
///   "version": 1,
///   "recipes": [ /* ScrapedRecipe-shaped objects, plus optional "categories" */ ]
/// }
/// ```
struct RecipePack {
    let format: String
    let version: Int
    let recipes: [RecipePackEntry]
}

/// One recipe in a pack. Same fields as `ScrapedRecipe`, plus optional `categories`.
struct RecipePackEntry: Identifiable {
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
    var categories: String?

    var ingredientCount: Int { ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }.count }
    var stepCount: Int { instructions.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }

    var displaySource: String {
        let domain = sourceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        if !domain.isEmpty { return domain }
        if let host = URL(string: sourceURL)?.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "No source URL"
    }
}

struct LoadedRecipePack: Identifiable {
    let id = UUID()
    let pack: RecipePack
    let fileName: String
}

// MARK: - Errors

enum RecipePackError: Error, LocalizedError {
    case unreadableFile
    case invalidJSON
    case unsupportedFormat(String)
    case unsupportedVersion(Int)
    case emptyPack

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Couldn't read that file. Make sure it's a recipe pack JSON."
        case .invalidJSON:
            return "That file isn't valid JSON."
        case .unsupportedFormat(let format):
            return "This file isn't an Our Week recipe pack (found \"\(format)\"). Expected format \"ourweek-recipe-pack\"."
        case .unsupportedVersion(let version):
            return "This recipe pack uses version \(version), which isn't supported. This app reads version 1."
        case .emptyPack:
            return "This recipe pack doesn't contain any recipes."
        }
    }
}

// MARK: - Parser

enum RecipePackParser {
    static let expectedFormat = "ourweek-recipe-pack"
    static let supportedVersion = 1

    static func parse(url: URL) throws -> RecipePack {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RecipePackError.unreadableFile
        }
        return try parse(data: data)
    }

    static func parse(data: Data) throws -> RecipePack {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw RecipePackError.invalidJSON
        }

        guard let json = object as? [String: Any] else {
            throw RecipePackError.invalidJSON
        }

        let format = json["format"] as? String ?? ""
        guard format == expectedFormat else {
            throw RecipePackError.unsupportedFormat(format.isEmpty ? "missing" : format)
        }

        let version: Int
        if let intVersion = json["version"] as? Int {
            version = intVersion
        } else if let num = json["version"] as? NSNumber {
            version = num.intValue
        } else {
            version = 0
        }
        guard version == supportedVersion else {
            throw RecipePackError.unsupportedVersion(version)
        }

        guard let rawRecipes = json["recipes"] as? [[String: Any]] else {
            throw RecipePackError.invalidJSON
        }
        guard !rawRecipes.isEmpty else {
            throw RecipePackError.emptyPack
        }

        let recipes = rawRecipes.map { parseEntry($0) }
        return RecipePack(format: format, version: version, recipes: recipes)
    }

    private static func parseEntry(_ json: [String: Any]) -> RecipePackEntry {
        let title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = json["description"] as? String ?? ""

        var ingredients: [ScrapedIngredient] = []
        if let rawIngredients = json["ingredients"] as? [[String: Any]] {
            ingredients = rawIngredients.map { parseIngredient($0) }
        }

        var instructions: [String] = []
        if let steps = json["instructions"] as? [String] {
            instructions = steps
        }

        let prep = intValue(json["prepTimeMinutes"])
        let cook = intValue(json["cookTimeMinutes"])
        let servings = max(1, intValue(json["servings"], default: 1))

        let imageURL = stringValue(json["imageURL"])
        let sourceURL = stringValue(json["sourceURL"]) ?? ""
        var sourceDomain = stringValue(json["sourceDomain"]) ?? ""

        if sourceDomain.isEmpty, let host = URL(string: sourceURL)?.host {
            sourceDomain = host.replacingOccurrences(of: "www.", with: "")
        }

        let categories: String?
        if let stringCats = json["categories"] as? String {
            let trimmed = stringCats.trimmingCharacters(in: .whitespacesAndNewlines)
            categories = trimmed.isEmpty ? nil : trimmed
        } else if let arrayCats = json["categories"] as? [String] {
            let joined = arrayCats
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            categories = joined.isEmpty ? nil : joined
        } else {
            categories = nil
        }

        return RecipePackEntry(
            title: title.isEmpty ? "Untitled Recipe" : title,
            description: description,
            ingredients: ingredients,
            instructions: instructions,
            prepTimeMinutes: prep,
            cookTimeMinutes: cook,
            servings: servings,
            imageURL: imageURL,
            sourceURL: sourceURL,
            sourceDomain: sourceDomain,
            categories: categories
        )
    }

    private static func parseIngredient(_ json: [String: Any]) -> ScrapedIngredient {
        let amount: Double
        if let d = json["amount"] as? Double {
            amount = d
        } else if let n = json["amount"] as? NSNumber {
            amount = n.doubleValue
        } else if let s = json["amount"] as? String {
            amount = RecipeScraperService.parseAmount(s)
        } else {
            amount = 0
        }

        return ScrapedIngredient(
            amount: amount,
            unit: json["unit"] as? String ?? "",
            name: json["name"] as? String ?? "",
            notes: json["notes"] as? String ?? ""
        )
    }

    private static func intValue(_ value: Any?, default defaultValue: Int = 0) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let i = Int(s) { return i }
        return defaultValue
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let s = value as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Incoming file (Files / share sheet)

enum RecipePackOpenHandler {
    static let notification = Notification.Name("OurWeek.recipePackFileOpened")
    private static let lock = NSLock()
    private static var pendingFileURL: URL?

    static func handle(url: URL) {
        guard url.pathExtension.lowercased() == "json" else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("ourweek-pack-\(UUID().uuidString).json")

        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: url, to: dest)
            setPending(dest)
            NotificationCenter.default.post(name: notification, object: dest)
        } catch {
            setPending(url)
            NotificationCenter.default.post(name: notification, object: url)
        }
    }

    static func consumePendingURL() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let url = pendingFileURL
        pendingFileURL = nil
        return url
    }

    private static func setPending(_ url: URL) {
        lock.lock()
        pendingFileURL = url
        lock.unlock()
    }
}

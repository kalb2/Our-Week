import Foundation

// MARK: - Pack Import Summary

struct RecipePackImportSummary {
    var imported: Int = 0
    var skippedDuplicates: Int = 0
    var failed: Int = 0
    var failedTitles: [String] = []
    /// Recipes that were saved, but whose `imageURL` could not be downloaded/stored.
    var imageFailures: Int = 0
}

enum RecipePackImportFailure: Error, LocalizedError {
    case missingTitle
    case missingIngredients
    case missingInstructions

    var errorDescription: String? {
        switch self {
        case .missingTitle:
            return "Recipe name is required"
        case .missingIngredients:
            return "Add at least one ingredient"
        case .missingInstructions:
            return "Add at least one instruction step"
        }
    }
}

// MARK: - Importer

/// Creates household recipes from a parsed pack via `DataManager.createRecipe`,
/// matching the save path in `ImportPreviewView`.
enum RecipePackImporter {

    @MainActor
    static func importPack(
        _ pack: RecipePack,
        dataManager: DataManager,
        progress: (_ completed: Int, _ total: Int, _ title: String) -> Void
    ) async -> RecipePackImportSummary {
        var summary = RecipePackImportSummary()
        let total = pack.recipes.count
        var seenURLs = Set<String>()
        var seenNameAndURL = Set<String>()

        for (index, entry) in pack.recipes.enumerated() {
            progress(index, total, entry.title)
            await Task.yield()

            let sourceURL = entry.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameKey = "\(name.lowercased())|\(sourceURL.lowercased())"

            let isBatchDuplicate =
                (!sourceURL.isEmpty && seenURLs.contains(sourceURL.lowercased()))
                || seenNameAndURL.contains(nameKey)

            if isBatchDuplicate || dataManager.hasDuplicateRecipe(sourceURL: sourceURL, name: name) {
                summary.skippedDuplicates += 1
                remember(sourceURL: sourceURL, nameKey: nameKey, seenURLs: &seenURLs, seenNameAndURL: &seenNameAndURL)
                continue
            }

            do {
                let storedImage = try await createRecipe(from: entry, dataManager: dataManager)
                summary.imported += 1
                if !storedImage, let url = entry.imageURL, !url.isEmpty {
                    summary.imageFailures += 1
                }
                remember(sourceURL: sourceURL, nameKey: nameKey, seenURLs: &seenURLs, seenNameAndURL: &seenNameAndURL)
            } catch {
                summary.failed += 1
                let label = name.isEmpty ? "Untitled Recipe" : name
                summary.failedTitles.append(label)
            }
        }

        progress(total, total, "")
        return summary
    }

    /// Same mapping as `ImportPreviewView.saveRecipe`.
    /// Downloads `imageURL` when present; image failure does not fail the recipe.
    /// Returns whether hero image data was stored.
    @discardableResult
    @MainActor
    static func createRecipe(from entry: RecipePackEntry, dataManager: DataManager) async throws -> Bool {
        let name = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw RecipePackImportFailure.missingTitle }

        let validIngredients = entry.ingredients.filter {
            !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !validIngredients.isEmpty else { throw RecipePackImportFailure.missingIngredients }

        let validInstructions = entry.instructions.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !validInstructions.isEmpty else { throw RecipePackImportFailure.missingInstructions }

        let ingInputs: [DataManager.IngredientInput] = validIngredients.enumerated().map { index, ing in
            DataManager.IngredientInput(
                amount: ing.amount,
                unit: ing.unit,
                name: ing.name,
                notes: ing.notes,
                sectionName: "",
                sortOrder: Int16(index)
            )
        }

        let instInputs: [DataManager.InstructionInput] = validInstructions.enumerated().map { index, text in
            DataManager.InstructionInput(
                stepNumber: Int16(index + 1),
                text: text,
                timerSeconds: 0
            )
        }

        let sourceURL = entry.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceDomain = entry.sourceDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        let categories = entry.categories?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)

        let imageData = await downloadHeroImage(from: entry.imageURL)

        _ = dataManager.createRecipe(
            name: name,
            recipeDescription: description.isEmpty ? nil : description,
            prepTime: Int16(entry.prepTimeMinutes),
            cookTime: Int16(entry.cookTimeMinutes),
            servings: Int16(max(1, entry.servings)),
            difficulty: nil,
            categories: (categories?.isEmpty ?? true) ? nil : categories,
            tags: nil,
            notes: nil,
            imageData: imageData,
            sourceURL: sourceURL.isEmpty ? nil : sourceURL,
            sourceDomain: sourceDomain.isEmpty ? nil : sourceDomain,
            ingredientInputs: ingInputs,
            instructionInputs: instInputs
        )

        return imageData != nil
    }

    private static func downloadHeroImage(from imageURL: String?) async -> Data? {
        guard let imageURL, !imageURL.isEmpty else { return nil }
        return await RecipeScraperService.downloadImage(from: imageURL)
    }

    private static func remember(
        sourceURL: String,
        nameKey: String,
        seenURLs: inout Set<String>,
        seenNameAndURL: inout Set<String>
    ) {
        if !sourceURL.isEmpty {
            seenURLs.insert(sourceURL.lowercased())
        }
        seenNameAndURL.insert(nameKey)
    }
}

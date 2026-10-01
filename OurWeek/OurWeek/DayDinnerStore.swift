import Foundation

/// One dinner line per day, stored on the existing MealPlan so the shared week stays in sync.
enum DayDinnerStore {
    static func dinners(on date: Date, dataManager: DataManager) -> [MealPlan] {
        dataManager.fetchMealPlans(for: date).filter {
            ($0.mealType ?? "dinner").lowercased() == "dinner"
        }
    }

    static func setDinner(on date: Date, title: String, recipe: Recipe?, dataManager: DataManager) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: date)
        let existing = dinners(on: day, dataManager: dataManager)
        let ingredients = recipe.flatMap { ingredientText(for: $0, dataManager: dataManager) }
        if let first = existing.first {
            dataManager.updateMealPlan(
                first,
                title: trimmed,
                mealType: "Dinner",
                notes: nil,
                ingredients: ingredients,
                recipe: recipe
            )
            for extra in existing.dropFirst() {
                dataManager.deleteMealPlan(extra)
            }
        } else {
            _ = dataManager.createMealPlan(
                title: trimmed,
                date: day,
                mealType: "Dinner",
                notes: nil,
                ingredients: ingredients,
                recipe: recipe
            )
        }
    }

    static func clearDinner(on date: Date, dataManager: DataManager) {
        for meal in dinners(on: date, dataManager: dataManager) {
            dataManager.deleteMealPlan(meal)
        }
    }

    private static func ingredientText(for recipe: Recipe, dataManager: DataManager) -> String? {
        let items = dataManager.sortedIngredients(for: recipe).map { ing in
            let text = CookingAmount.line(
                amount: ing.amount,
                unit: ing.unit ?? "",
                name: ing.name ?? "",
                notes: ing.notes ?? ""
            )
            return "0|\(text)"
        }
        return items.isEmpty ? nil : items.joined(separator: "\n")
    }
}

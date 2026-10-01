import Foundation

/// Dinner lines for a day, each one an existing MealPlan so the shared week stays in sync.
enum DayDinnerStore {
    static func dinners(on date: Date, dataManager: DataManager) -> [MealPlan] {
        let start = Calendar.current.startOfDay(for: date)
        return dataManager.fetchMealPlans(for: date)
            .filter { ($0.mealType ?? "dinner").lowercased() == "dinner" }
            .sorted { lhs, rhs in
                let left = lhs.date ?? .distantPast
                let right = rhs.date ?? .distantPast
                if left != right { return left < right }
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
            .filter { meal in
                guard let when = meal.date else { return true }
                return when.timeIntervalSince(start) < 86_400
            }
    }

    static func update(_ meal: MealPlan, title: String, recipe: Recipe?, dataManager: DataManager) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dataManager.updateMealPlan(
            meal,
            title: trimmed,
            mealType: "Dinner",
            notes: nil,
            ingredients: recipe.flatMap { ingredientText(for: $0, dataManager: dataManager) },
            recipe: recipe
        )
    }

    /// Adds another dinner on the same day. A few seconds after midnight keeps order without a new field.
    @discardableResult
    static func append(on date: Date, title: String, recipe: Recipe?, dataManager: DataManager) -> MealPlan {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = Calendar.current.startOfDay(for: date)
        let existing = dinners(on: start, dataManager: dataManager)
        let used = existing.compactMap { meal -> Int? in
            guard let when = meal.date else { return nil }
            let delta = when.timeIntervalSince(start)
            guard delta >= 0 else { return nil }
            return Int(delta.rounded())
        }
        let slot = min((used.max() ?? -1) + 1, 86_399)
        return dataManager.createMealPlan(
            title: trimmed.isEmpty ? title : trimmed,
            date: start.addingTimeInterval(TimeInterval(slot)),
            mealType: "Dinner",
            notes: nil,
            ingredients: recipe.flatMap { ingredientText(for: $0, dataManager: dataManager) },
            recipe: recipe
        )
    }

    static func remove(_ meal: MealPlan, dataManager: DataManager) {
        dataManager.deleteMealPlan(meal)
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

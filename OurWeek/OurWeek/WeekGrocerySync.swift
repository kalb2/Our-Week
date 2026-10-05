import CoreData
import Foundation

/// Puts ingredients from saved recipes on the visible week onto the shopping list.
/// A typed meal with no recipe adds nothing. Clearing or swapping a meal removes
/// only what that meal added. Hand-added items and checked items stay.
enum WeekGrocerySync {
    private static let storageKey = "weekGroceryLedger.v1"
    private static var isReconciling = false

    struct MealShare: Codable, Equatable {
        var mealID: String
        var amount: Double
    }

    struct Line: Codable, Equatable {
        var itemID: UUID
        var nameKey: String
        var unitKey: String
        var displayName: String
        var createdBySync: Bool
        var originalQuantity: String
        var handAmount: Double
        var meals: [MealShare]
    }

    struct Ledger: Codable {
        var lines: [Line]
    }

    private struct Desired {
        var displayName: String
        var unit: String
        var section: String
        var meals: [MealShare]
        var total: Double { meals.reduce(0) { $0 + $1.amount } }
    }

    static func reconcile(meals: [MealPlan], visibleDays: [Date], dataManager: DataManager) {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let calendar = Calendar.current
        let visible = meals.filter { meal in
            guard let date = meal.date else { return false }
            return visibleDays.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        let desired = desiredLines(from: visible, dataManager: dataManager)
        var ledger = load()
        var changed = false

        var lists = dataManager.fetchShoppingLists()
        if lists.isEmpty, !desired.isEmpty {
            _ = dataManager.createShoppingList(name: "Groceries")
            lists = dataManager.fetchShoppingLists()
        }

        var next: [Line] = []
        var usedKeys = Set<String>()

        for (key, bucket) in desired {
            usedKeys.insert(key)
            if let index = ledger.lines.firstIndex(where: { lineKey($0) == key }) {
                var line = ledger.lines[index]
                if dataManager.shoppingItem(id: line.itemID) == nil {
                    let sameMeals = Set(line.meals.map(\.mealID)) == Set(bucket.meals.map(\.mealID))
                    if sameMeals { continue }
                    if let created = createLine(bucket: bucket, lists: lists, dataManager: dataManager) {
                        next.append(created)
                        changed = true
                    }
                    continue
                }
                if apply(bucket, to: &line, dataManager: dataManager) {
                    changed = true
                }
                line.meals = bucket.meals
                line.displayName = bucket.displayName
                next.append(line)
            } else if let line = createLine(bucket: bucket, lists: lists, dataManager: dataManager) {
                next.append(line)
                changed = true
            }
        }

        for line in ledger.lines where !usedKeys.contains(lineKey(line)) {
            if release(line, dataManager: dataManager) {
                changed = true
            }
        }

        if changed || ledger.lines != next {
            save(Ledger(lines: next))
            if changed {
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
            }
        }
    }

    private static func desiredLines(from meals: [MealPlan], dataManager: DataManager) -> [String: Desired] {
        var desired: [String: Desired] = [:]
        for meal in meals {
            guard let recipe = meal.recipe else { continue }
            let mealID = meal.id?.uuidString ?? meal.objectID.uriRepresentation().absoluteString
            for ingredient in dataManager.sortedIngredients(for: recipe) {
                let name = (ingredient.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let unit = CookingAmount.canonicalUnit(ingredient.unit ?? "")
                let key = ingredientKey(name: name, unit: unit)
                var bucket = desired[key] ?? Desired(
                    displayName: name,
                    unit: unit,
                    section: (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    meals: []
                )
                if let index = bucket.meals.firstIndex(where: { $0.mealID == mealID }) {
                    bucket.meals[index].amount += max(0, ingredient.amount)
                } else {
                    bucket.meals.append(MealShare(mealID: mealID, amount: max(0, ingredient.amount)))
                }
                if bucket.section.isEmpty {
                    bucket.section = (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                desired[key] = bucket
            }
        }
        return desired
    }

    /// Writes the combined amount. A checked item is left alone.
    private static func apply(_ bucket: Desired, to line: inout Line, dataManager: DataManager) -> Bool {
        guard let item = dataManager.shoppingItem(id: line.itemID) else {
            return false
        }
        if item.isChecked { return false }
        let total = line.handAmount + bucket.total
        let quantity = quantityText(total, unit: bucket.unit)
        if (item.quantity ?? "") == quantity { return false }
        dataManager.setShoppingQuantity(item, quantity: quantity)
        return true
    }

    private static func createLine(
        bucket: Desired,
        lists: [ShoppingList],
        dataManager: DataManager
    ) -> Line? {
        let items = dataManager.allShoppingItems()
        if let existing = items.first(where: { item in
            !item.isChecked && nameKey(item.name ?? "") == nameKey(bucket.displayName)
        }), let itemID = existing.id {
            let parsed = handAmount(in: existing, unit: bucket.unit)
            if let parsed {
                let quantity = quantityText(parsed + bucket.total, unit: bucket.unit)
                if (existing.quantity ?? "") != quantity {
                    dataManager.setShoppingQuantity(existing, quantity: quantity)
                }
                return Line(
                    itemID: itemID,
                    nameKey: nameKey(bucket.displayName),
                    unitKey: bucket.unit.lowercased(),
                    displayName: bucket.displayName,
                    createdBySync: false,
                    originalQuantity: existing.quantity ?? "",
                    handAmount: parsed,
                    meals: bucket.meals
                )
            }
        }

        if let checked = items.first(where: { item in
            item.isChecked && nameKey(item.name ?? "") == nameKey(bucket.displayName)
        }), let itemID = checked.id {
            return Line(
                itemID: itemID,
                nameKey: nameKey(bucket.displayName),
                unitKey: bucket.unit.lowercased(),
                displayName: bucket.displayName,
                createdBySync: false,
                originalQuantity: checked.quantity ?? "",
                handAmount: 0,
                meals: bucket.meals
            )
        }

        guard let list = list(for: bucket.section, lists: lists) else { return nil }
        let quantity = quantityText(bucket.total, unit: bucket.unit)
        let item = dataManager.addShoppingItem(
            name: bucket.displayName,
            quantity: quantity,
            category: bucket.section.isEmpty ? nil : bucket.section,
            to: list
        )
        guard let itemID = item.id else { return nil }
        return Line(
            itemID: itemID,
            nameKey: nameKey(bucket.displayName),
            unitKey: bucket.unit.lowercased(),
            displayName: bucket.displayName,
            createdBySync: true,
            originalQuantity: "",
            handAmount: 0,
            meals: bucket.meals
        )
    }

    /// Removes only the amount this week added. Checked items and hand-added items stay.
    private static func release(_ line: Line, dataManager: DataManager) -> Bool {
        guard let item = dataManager.shoppingItem(id: line.itemID) else { return false }
        if item.isChecked { return false }
        if line.createdBySync {
            dataManager.delete(item)
            return true
        }
        if (item.quantity ?? "") != line.originalQuantity {
            dataManager.setShoppingQuantity(item, quantity: line.originalQuantity)
            return true
        }
        return false
    }

    private static func list(for section: String, lists: [ShoppingList]) -> ShoppingList? {
        let key = section.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            if let exact = lists.first(where: {
                ($0.name ?? "").compare(key, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }) {
                return exact
            }
            if let loose = lists.first(where: { list in
                let name = list.name ?? ""
                guard name.count > 2 else { return false }
                return name.localizedCaseInsensitiveContains(key) || key.localizedCaseInsensitiveContains(name)
            }) {
                return loose
            }
        }
        return lists.first
    }

    private static func handAmount(in item: ShoppingItem, unit: String) -> Double? {
        let quantity = (item.quantity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if quantity.isEmpty { return 0 }
        let parsed = RecipeScraperService.parseIngredientString(quantity)
        let parsedUnit = CookingAmount.canonicalUnit(parsed.unit).lowercased()
        let want = CookingAmount.canonicalUnit(unit).lowercased()
        guard parsed.amount > 0 else { return nil }
        if parsedUnit == want { return parsed.amount }
        return nil
    }

    private static func quantityText(_ amount: Double, unit: String) -> String {
        guard amount > 0.001 else { return "" }
        return CookingAmount.labeled(amount, unit: unit)
    }

    private static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func ingredientKey(name: String, unit: String) -> String {
        "\(nameKey(name))|\(unit.lowercased())"
    }

    private static func lineKey(_ line: Line) -> String {
        "\(line.nameKey)|\(line.unitKey)"
    }

    private static func load() -> Ledger {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let ledger = try? JSONDecoder().decode(Ledger.self, from: data) else {
            return Ledger(lines: [])
        }
        return ledger
    }

    private static func save(_ ledger: Ledger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

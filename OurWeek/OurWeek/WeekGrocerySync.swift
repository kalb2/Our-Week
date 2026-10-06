import CoreData
import Foundation

/// Puts ingredients from saved recipes on the visible week onto the shopping list.
/// A typed meal with no recipe adds nothing. Clearing or swapping a meal removes
/// only what that meal added. Hand-added items and checked items stay.
enum WeekGrocerySync {
    private static let storageKey = "weekGroceryLedger.v1"
    /// Items the user removed, keyed by ingredient, so the same meals do not come back.
    private static let removalStorageKey = "weekGroceryUserRemovals.v1"
    private static var isReconciling = false

    struct MealShare: Codable, Equatable {
        var mealID: String
        var amount: Double
        /// Empty on ledgers saved before mixed-unit merges.
        var unit: String

        init(mealID: String, amount: Double, unit: String = "") {
            self.mealID = mealID
            self.amount = amount
            self.unit = unit
        }

        private enum CodingKeys: String, CodingKey {
            case mealID, amount, unit
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            mealID = try container.decode(String.self, forKey: .mealID)
            amount = try container.decode(Double.self, forKey: .amount)
            unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(mealID, forKey: .mealID)
            try container.encode(amount, forKey: .amount)
            try container.encode(unit, forKey: .unit)
        }
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
        var section: String
        var meals: [MealShare]
    }

    private static var lastMeals: [MealPlan] = []
    private static var lastDays: [Date] = []
    private static var lastDataManager: DataManager?

    static func reconcile(meals: [MealPlan], visibleDays: [Date], dataManager: DataManager) {
        guard !isReconciling else { return }
        isReconciling = true
        defer { isReconciling = false }

        let calendar = Calendar.current
        let visible = meals.filter { meal in
            guard let date = meal.date else { return false }
            return visibleDays.contains { calendar.isDate($0, inSameDayAs: date) }
        }
        lastMeals = meals
        lastDays = visibleDays
        lastDataManager = dataManager
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
        var removals = loadRemovals()
        var removalsChanged = false

        for (key, bucket) in desired {
            usedKeys.insert(key)
            let meals = Set(bucket.meals.map(\.mealID))
            if let index = ledger.lines.firstIndex(where: { lineKey($0) == key }) {
                var line = ledger.lines[index]
                if dataManager.shoppingItem(id: line.itemID) == nil {
                    let sameMeals = Set(line.meals.map(\.mealID)) == meals
                    if sameMeals {
                        // The row is gone and the meals have not changed. Remember that
                        // instead of creating the ingredient again.
                        recordRemoval(key: key, meals: meals, into: &removals, changed: &removalsChanged)
                        next.append(line)
                        continue
                    }
                    dropRemoval(key: key, from: &removals, changed: &removalsChanged)
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
                line.nameKey = key
                next.append(line)
            } else if removalMatches(key, meals: meals, in: removals) {
                continue
            } else {
                dropRemoval(key: key, from: &removals, changed: &removalsChanged)
                if let line = createLine(bucket: bucket, lists: lists, dataManager: dataManager) {
                    next.append(line)
                    changed = true
                }
            }
        }

        let keptRemovals = removals.compactMap { removal -> Removal? in
            let name = removalName(removal.key)
            guard usedKeys.contains(name) else { return nil }
            return Removal(key: name, mealIDs: removal.mealIDs)
        }
        if keptRemovals != removals {
            removals = keptRemovals
            removalsChanged = true
        }
        if removalsChanged {
            saveRemovals(removals)
        }

        let keptIDs = Set(next.map(\.itemID))
        for line in ledger.lines where !keptIDs.contains(line.itemID) {
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
                let rawName = (ingredient.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawName.isEmpty else { continue }
                let display = GroceryName.display(rawName)
                let key = GroceryName.key(display)
                guard !key.isEmpty else { continue }
                if PantryStaples.contains(key) { continue }
                let unit = CookingAmount.canonicalUnit(ingredient.unit ?? "")
                let amount = max(0, ingredient.amount)
                var bucket = desired[key] ?? Desired(
                    displayName: display,
                    section: (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    meals: []
                )
                if let index = bucket.meals.firstIndex(where: {
                    $0.mealID == mealID && CookingAmount.canonicalUnit($0.unit) == unit
                }) {
                    bucket.meals[index].amount += amount
                } else {
                    bucket.meals.append(MealShare(mealID: mealID, amount: amount, unit: unit))
                }
                if bucket.section.isEmpty {
                    bucket.section = (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if bucket.displayName.count > display.count, !display.isEmpty {
                    bucket.displayName = display
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
        let quantity = describe(meals: bucket.meals, handAmount: line.handAmount, handUnit: line.unitKey)
        var changed = false
        if line.createdBySync, (item.name ?? "") != bucket.displayName {
            item.name = bucket.displayName
            changed = true
        }
        if (item.quantity ?? "") != quantity {
            item.quantity = quantity
            changed = true
        }
        if changed {
            dataManager.save()
        }
        return changed
    }

    private static func createLine(
        bucket: Desired,
        lists: [ShoppingList],
        dataManager: DataManager
    ) -> Line? {
        let items = dataManager.allShoppingItems()
        let key = GroceryName.key(bucket.displayName)
        let owned = Set(load().lines.map(\.itemID))
        if let existing = items.first(where: { item in
            guard let id = item.id, !owned.contains(id), !item.isChecked else { return false }
            return GroceryName.key(item.name ?? "") == key
        }), let itemID = existing.id {
            let original = existing.quantity ?? ""
            let parsed = handAmount(in: existing, meals: bucket.meals)
            let handUnit = parsed == nil ? "" : CookingAmount.canonicalUnit(singleUnit(in: bucket.meals) ?? "")
            let quantity = describe(meals: bucket.meals, handAmount: parsed ?? 0, handUnit: handUnit)
            if original != quantity {
                existing.quantity = quantity
                dataManager.save()
            }
            return Line(
                itemID: itemID,
                nameKey: key,
                unitKey: handUnit.lowercased(),
                displayName: bucket.displayName,
                createdBySync: false,
                originalQuantity: original,
                handAmount: parsed ?? 0,
                meals: bucket.meals
            )
        }

        if let checked = items.first(where: { item in
            item.isChecked && GroceryName.key(item.name ?? "") == key
        }), let itemID = checked.id {
            return Line(
                itemID: itemID,
                nameKey: key,
                unitKey: "",
                displayName: bucket.displayName,
                createdBySync: false,
                originalQuantity: checked.quantity ?? "",
                handAmount: 0,
                meals: bucket.meals
            )
        }

        guard let list = list(for: bucket.section, lists: lists) else { return nil }
        let quantity = describe(meals: bucket.meals, handAmount: 0, handUnit: "")
        let item = dataManager.addShoppingItem(
            name: bucket.displayName,
            quantity: quantity,
            category: bucket.section.isEmpty ? nil : bucket.section,
            to: list
        )
        guard let itemID = item.id else { return nil }
        return Line(
            itemID: itemID,
            nameKey: key,
            unitKey: "",
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

    /// A hand-typed amount can be added only when the recipe shares one unit family.
    private static func handAmount(in item: ShoppingItem, meals: [MealShare]) -> Double? {
        guard let unit = singleUnit(in: meals) else { return nil }
        let quantity = (item.quantity ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if quantity.isEmpty || quantity.contains(" + ") { return quantity.isEmpty ? 0 : nil }
        let parsed = RecipeScraperService.parseIngredientString(quantity)
        guard parsed.amount > 0 else { return quantity.isEmpty ? 0 : nil }
        let parsedUnit = CookingAmount.canonicalUnit(parsed.unit)
        let want = CookingAmount.canonicalUnit(unit)
        if MeasureFamily.family(of: parsedUnit) == MeasureFamily.family(of: want) {
            return MeasureFamily.convert(parsed.amount, from: parsedUnit, to: want)
        }
        return nil
    }

    private static func singleUnit(in meals: [MealShare]) -> String? {
        let units = Set(meals.map { CookingAmount.canonicalUnit($0.unit).lowercased() })
        guard units.count == 1, let unit = units.first else { return nil }
        return unit
    }

    private static func describe(meals: [MealShare], handAmount: Double, handUnit: String) -> String {
        var parts = meals.filter { $0.amount > 0.001 }
        if handAmount > 0.001 {
            parts.append(MealShare(mealID: "", amount: handAmount, unit: handUnit))
        }
        var order: [MeasureFamily] = []
        var totals: [MeasureFamily: Double] = [:]
        for part in parts {
            let family = MeasureFamily.family(of: part.unit)
            if totals[family] == nil {
                order.append(family)
                totals[family] = 0
            }
            totals[family, default: 0] += MeasureFamily.baseAmount(part.amount, unit: part.unit)
        }
        let labels = order.compactMap { family -> String? in
            guard let total = totals[family], total > 0.001 else { return nil }
            return family.label(total)
        }
        return labels.joined(separator: " + ")
    }

    private static func lineKey(_ line: Line) -> String {
        let normalized = GroceryName.key(line.nameKey)
        return normalized.isEmpty ? line.nameKey : normalized
    }

    /// Marks ledger lines for these shopping rows as removed by the user.
    /// Call before the rows are deleted.
    static func noteUserRemoved(itemIDs: [UUID]) {
        let ids = Set(itemIDs)
        guard !ids.isEmpty else { return }
        var removals = loadRemovals()
        var changed = false
        for line in load().lines where ids.contains(line.itemID) {
            let meals = Set(line.meals.map(\.mealID))
            guard !meals.isEmpty else { continue }
            recordRemoval(key: lineKey(line), meals: meals, into: &removals, changed: &changed)
        }
        if changed {
            saveRemovals(removals)
        }
    }

    private struct Removal: Codable, Equatable {
        var key: String
        var mealIDs: [String]
    }

    private static func removalName(_ key: String) -> String {
        let name = key.split(separator: "|", maxSplits: 1).first.map(String.init) ?? key
        let normalized = GroceryName.key(name)
        return normalized.isEmpty ? name : normalized
    }

    private static func removalMatches(_ key: String, meals: Set<String>, in removals: [Removal]) -> Bool {
        removals.contains { removal in
            removalName(removal.key) == key && Set(removal.mealIDs) == meals
        }
    }

    /// Runs the last week reconcile again after a pantry change.
    static func reconcileAgain() {
        guard let dataManager = lastDataManager else { return }
        reconcile(meals: lastMeals, visibleDays: lastDays, dataManager: dataManager)
    }

    static func generatedItemIDs() -> Set<UUID> {
        Set(load().lines.filter(\.createdBySync).map(\.itemID))
    }

    static func stapleNames() -> [String] {
        PantryStaples.names()
    }

    static func addStaple(_ name: String) {
        PantryStaples.add(name)
        reconcileAgain()
    }

    static func removeStaple(_ name: String) {
        PantryStaples.remove(name)
        reconcileAgain()
    }

    private static func recordRemoval(
        key: String,
        meals: Set<String>,
        into removals: inout [Removal],
        changed: inout Bool
    ) {
        let sorted = meals.sorted()
        if let index = removals.firstIndex(where: { $0.key == key }) {
            if removals[index].mealIDs != sorted {
                removals[index].mealIDs = sorted
                changed = true
            }
        } else {
            removals.append(Removal(key: key, mealIDs: sorted))
            changed = true
        }
    }

    private static func dropRemoval(key: String, from removals: inout [Removal], changed: inout Bool) {
        guard let index = removals.firstIndex(where: { $0.key == key }) else { return }
        removals.remove(at: index)
        changed = true
    }

    private static func loadRemovals() -> [Removal] {
        guard let data = UserDefaults.standard.data(forKey: removalStorageKey),
              let removals = try? JSONDecoder().decode([Removal].self, from: data) else {
            return []
        }
        return removals
    }

    private static func saveRemovals(_ removals: [Removal]) {
        guard let data = try? JSONEncoder().encode(removals) else { return }
        UserDefaults.standard.set(data, forKey: removalStorageKey)
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

/// Volume and weight families that can be summed. Everything else stays in its own unit.
private enum MeasureFamily: Hashable {
    case volume
    case weight
    case counted(String)

    static func family(of unit: String) -> MeasureFamily {
        switch CookingAmount.canonicalUnit(unit).lowercased() {
        case "tsp", "tbsp", "cup": return .volume
        case "oz", "lb": return .weight
        default: return .counted(CookingAmount.canonicalUnit(unit).lowercased())
        }
    }

    static func baseAmount(_ amount: Double, unit: String) -> Double {
        let canonical = CookingAmount.canonicalUnit(unit).lowercased()
        switch canonical {
        case "tbsp": return amount * 3
        case "cup": return amount * 48
        case "lb": return amount * 16
        default: return amount
        }
    }

    static func convert(_ amount: Double, from: String, to: String) -> Double {
        let base = baseAmount(amount, unit: from)
        switch CookingAmount.canonicalUnit(to).lowercased() {
        case "tbsp": return base / 3
        case "cup": return base / 48
        case "lb": return base / 16
        default: return base
        }
    }

    func label(_ base: Double) -> String {
        switch self {
        case .volume:
            if base >= 48 - 0.01 {
                return CookingAmount.labeled(base / 48, unit: "cup", fractionsOnly: true)
            }
            if base >= 3 - 0.01 {
                return CookingAmount.labeled(base / 3, unit: "tbsp", fractionsOnly: true)
            }
            return CookingAmount.labeled(base, unit: "tsp", fractionsOnly: true)
        case .weight:
            if base >= 16 - 0.01 {
                return CookingAmount.labeled(base / 16, unit: "lb", fractionsOnly: true)
            }
            return CookingAmount.labeled(base, unit: "oz", fractionsOnly: true)
        case .counted(let unit):
            return CookingAmount.labeled(base, unit: unit, fractionsOnly: true)
        }
    }
}

/// Cleans a recipe ingredient down to the food, so package sizes and prep notes merge.
private enum GroceryName {
    private static let containers: [String] = [
        "cans", "can", "packages", "package", "pkg", "jars", "jar", "bottles", "bottle",
        "bags", "bag", "boxes", "box", "tins", "tin", "containers", "container", "pouches", "pouch"
    ]
    private static let prepPhrases = ["drained and rinsed", "rinsed and drained"]
    private static let prepWords: Set<String> = [
        "chopped", "diced", "minced", "divided", "drained", "rinsed"
    ]

    static func display(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        if let comma = text.firstIndex(of: ",") {
            text = String(text[..<comma])
        }
        text = text.replacingOccurrences(
            of: #"\d+(?:\.\d+)?\s*[-‐‑–]?\s*(?:ounces|ounce|oz)\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = collapse(text)
        var words = text.split(separator: " ").map(String.init)
        while let first = words.first, containers.contains(first.lowercased()) {
            words.removeFirst()
            if words.first?.lowercased() == "of" { words.removeFirst() }
        }
        text = words.joined(separator: " ")
        for phrase in prepPhrases {
            text = text.replacingOccurrences(of: phrase, with: " ", options: .caseInsensitive)
        }
        words = text.split(separator: " ").map(String.init).filter { !prepWords.contains($0.lowercased()) }
        while words.first?.lowercased() == "and" { words.removeFirst() }
        while words.last?.lowercased() == "and" { words.removeLast() }
        text = collapse(words.joined(separator: " "))
        if text.isEmpty {
            text = collapse(raw.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression))
        }
        guard let first = text.first else { return "" }
        if first.isLowercase {
            text = first.uppercased() + text.dropFirst()
        }
        return text
    }

    static func key(_ name: String) -> String {
        let cleaned = display(name).lowercased()
        let words = cleaned.split(separator: " ").map { singular(String($0)) }
        return words.joined(separator: " ")
    }

    private static func singular(_ word: String) -> String {
        let word = word.lowercased()
        if ["chiles", "chilis", "chilies", "chilli", "chillies", "chile"].contains(word) { return "chili" }
        if word.hasSuffix("oes"), word.count > 4 { return String(word.dropLast(2)) }
        if word.hasSuffix("ies"), word.count > 4 { return String(word.dropLast(3)) + "y" }
        if word.hasSuffix("ches") || word.hasSuffix("shes") || word.hasSuffix("xes") || word.hasSuffix("zes") || word.hasSuffix("sses") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), !word.hasSuffix("us"), !word.hasSuffix("is"), word.count > 3 {
            return String(word.dropLast())
        }
        return word
    }

    private static func collapse(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum PantryStaples {
    private static let storageKey = "pantryStaples.v1"
    private static let seed = [
        "Salt", "Pepper", "Black pepper", "Kosher salt", "Olive oil", "Vegetable oil",
        "Cooking spray", "Water", "Sugar", "Flour", "Garlic powder", "Onion powder",
        "Paprika", "Cumin", "Chili powder", "Oregano", "Basil", "Cinnamon",
        "Baking soda", "Baking powder"
    ]

    static func names() -> [String] {
        let stored = load()
        if stored.isEmpty, UserDefaults.standard.object(forKey: storageKey) == nil {
            save(seed)
            return seed
        }
        return stored
    }

    static func contains(_ key: String) -> Bool {
        names().contains { GroceryName.key($0) == key }
    }

    static func add(_ name: String) {
        let display = GroceryName.display(name)
        let key = GroceryName.key(display)
        guard !key.isEmpty else { return }
        var current = names()
        guard !current.contains(where: { GroceryName.key($0) == key }) else { return }
        current.append(display)
        save(current)
    }

    static func remove(_ name: String) {
        let key = GroceryName.key(name)
        let current = names().filter { GroceryName.key($0) != key }
        save(current)
    }

    private static func load() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let names = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return names
    }

    private static func save(_ names: [String]) {
        guard let data = try? JSONEncoder().encode(names) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

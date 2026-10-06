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
        var singular: String
        var kind: GroceryPlanner.Kind
        var section: String
        var meals: [MealShare]

        func row(handAmount: Double = 0, handUnit: String = "") -> GroceryPlanner.Row {
            var shares = meals.map { GroceryPlanner.Share(amount: $0.amount, unit: $0.unit) }
            if handAmount > 0.001 {
                shares.append(GroceryPlanner.Share(amount: handAmount, unit: handUnit))
            }
            return GroceryPlanner.present(
                parsed: GroceryPlanner.Parsed(key: singular, singular: singular, kind: kind),
                shares: shares
            )
        }
    }

    private static var lastMeals: [MealPlan] = []
    private static var lastDays: [Date] = []
    private static var lastDataManager: DataManager?
    private static var didCheckMerge = false

    static func reconcile(meals: [MealPlan], visibleDays: [Date], dataManager: DataManager) {
        if !didCheckMerge {
            didCheckMerge = true
            #if DEBUG
            let problems = GroceryPlanner.problems()
            if !problems.isEmpty {
                print("Grocery merge self-check failed:\n\(problems.joined(separator: "\n"))")
            }
            #endif
        }
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
                line.displayName = bucket.row().name
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
                guard let parsed = GroceryPlanner.parse(name: rawName) else { continue }
                let unit = GroceryPlanner.normalizeUnit(ingredient.unit ?? "")
                let amount = max(0, ingredient.amount)
                var bucket = desired[parsed.key] ?? Desired(
                    singular: parsed.singular,
                    kind: parsed.kind,
                    section: (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    meals: []
                )
                if let index = bucket.meals.firstIndex(where: {
                    $0.mealID == mealID && GroceryPlanner.normalizeUnit($0.unit) == unit
                }) {
                    bucket.meals[index].amount += amount
                } else {
                    bucket.meals.append(MealShare(mealID: mealID, amount: amount, unit: unit))
                }
                if bucket.section.isEmpty {
                    bucket.section = (ingredient.sectionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                desired[parsed.key] = bucket
            }
        }
        return desired
    }

    /// Rewrites a recipe-generated row. Checked items and hand-added items stay as they are.
    private static func apply(_ bucket: Desired, to line: inout Line, dataManager: DataManager) -> Bool {
        guard let item = dataManager.shoppingItem(id: line.itemID) else {
            return false
        }
        if item.isChecked || !line.createdBySync { return false }
        let row = bucket.row(handAmount: line.handAmount, handUnit: line.unitKey)
        var changed = false
        if (item.name ?? "") != row.name {
            item.name = row.name
            changed = true
        }
        if (item.quantity ?? "") != row.quantity {
            item.quantity = row.quantity
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
        let key = bucket.singular
        let row = bucket.row()
        let owned = Set(load().lines.map(\.itemID))
        if let existing = items.first(where: { item in
            guard let id = item.id, !owned.contains(id), !item.isChecked else { return false }
            return GroceryName.key(item.name ?? "") == key
        }), let itemID = existing.id {
            // A hand-added row with this food stays as the person typed it.
            return Line(
                itemID: itemID,
                nameKey: key,
                unitKey: "",
                displayName: existing.name ?? row.name,
                createdBySync: false,
                originalQuantity: existing.quantity ?? "",
                handAmount: 0,
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
                displayName: checked.name ?? row.name,
                createdBySync: false,
                originalQuantity: checked.quantity ?? "",
                handAmount: 0,
                meals: bucket.meals
            )
        }

        guard let list = list(for: bucket.section, lists: lists) else { return nil }
        let item = dataManager.addShoppingItem(
            name: row.name,
            quantity: row.quantity,
            category: bucket.section.isEmpty ? nil : bucket.section,
            to: list
        )
        guard let itemID = item.id else { return nil }
        return Line(
            itemID: itemID,
            nameKey: key,
            unitKey: "",
            displayName: row.name,
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

/// Turns recipe lines into one shopping row per food: a clean name and a purchase amount.
private enum GroceryPlanner {
    enum Kind: Equatable {
        case plain
        case herb
        case onion
        case garlic
        case lime
        case canned(Double)
    }

    struct Parsed: Equatable {
        var key: String
        var singular: String
        var kind: Kind
    }

    struct Share {
        var amount: Double
        var unit: String
    }

    struct Row: Equatable {
        var name: String
        var quantity: String
    }

    private static let containers: Set<String> = [
        "cans", "can", "packages", "package", "pkg", "jars", "jar", "bottles", "bottle",
        "bags", "bag", "boxes", "box", "tins", "tin", "containers", "container", "pouches", "pouch"
    ]
    private static let descriptors: Set<String> = [
        "large", "medium", "small", "fresh", "finely", "roughly", "light", "thinly", "coarsely",
        "freshly", "boneless", "skinless", "frozen", "canned", "dried", "optional", "extra-virgin"
    ]
    private static let prepWords: Set<String> = [
        "chopped", "diced", "minced", "divided", "drained", "rinsed"
    ]
    private static let nonFood: Set<String> = [
        "topping", "toppings", "serving", "garnish", "garnishes", "note", "notes",
        "instruction", "instructions", "variation", "variations", "accompaniment",
        "accompaniments", "optional"
    ]
    private static let headers: Set<String> = [
        "topping", "toppings", "garnish", "garnishes", "optional toppings",
        "for serving", "to serve", "serving", "notes", "note"
    ]
    private static let herbs: Set<String> = [
        "cilantro", "parsley", "mint", "dill", "chive", "rosemary", "thyme", "sage",
        "tarragon", "marjoram", "lemongrass", "basil", "oregano"
    ]
    private static let meats: Set<String> = [
        "beef", "pork", "turkey", "chicken", "lamb", "veal", "meat", "sausage", "bison", "venison"
    ]
    private static let spices: Set<String> = [
        "cumin", "oregano", "paprika", "cinnamon", "chili", "chile", "coriander", "nutmeg",
        "ginger", "turmeric", "allspice", "cayenne", "pepper", "salt", "clove", "cardamom",
        "mustard", "thyme", "rosemary", "sage", "basil", "dill", "seasoning", "powder"
    ]
    private static let alwaysPlural: Set<String> = ["bean"]
    private static let cuts: Set<String> = ["thigh", "breast", "leg", "wing", "drumstick", "tenderloin", "tender"]

    /// Nil when the line is a pantry staple, a section header, or only a descriptor.
    static func parse(name: String) -> Parsed? {
        guard let words = foodWords(name) else { return nil }
        let key = words.joined(separator: " ")
        if PantryStaples.contains(key) { return nil }
        return Parsed(key: key, singular: key, kind: kind(for: key))
    }

    static func matchKey(_ name: String) -> String {
        foodWords(name)?.joined(separator: " ") ?? ""
    }

    static func displayName(for raw: String) -> String {
        guard let words = foodWords(raw) else { return "" }
        let key = words.joined(separator: " ")
        let parsed = Parsed(key: key, singular: key, kind: kind(for: key))
        return present(parsed: parsed, shares: [Share(amount: 1, unit: "")]).name
    }

    static func normalizeUnit(_ unit: String) -> String {
        let canonical = CookingAmount.canonicalUnit(unit).lowercased()
        switch canonical {
        case "whole", "each", "count", "ct": return ""
        default: return canonical
        }
    }

    static func present(parsed: Parsed, shares: [Share]) -> Row {
        let parts = shares
            .map { Share(amount: $0.amount, unit: normalizeUnit($0.unit)) }
            .filter { $0.amount > 0.001 }
        switch parsed.kind {
        case .herb:
            return Row(name: styled(parsed.singular, plural: false), quantity: herbQuantity(parts))
        case .onion:
            let count = onionCount(parts)
            return Row(name: styled(parsed.singular, plural: count > 1.001), quantity: countText(count))
        case .garlic:
            return Row(name: styled(parsed.singular, plural: false), quantity: garlicQuantity(parts))
        case .lime:
            let count = limeCount(parts)
            return Row(name: styled(parsed.singular, plural: count > 1.001), quantity: countText(count))
        case .canned(let ounces):
            let cans = canCount(parts, ounces: ounces)
            let last = parsed.singular.split(separator: " ").last.map(String.init) ?? ""
            let pluralName = last == "tomato" || last == "bean"
            let quantity = cans > 0 ? CookingAmount.labeled(cans, unit: "can", fractionsOnly: true) : ""
            return Row(name: styled(parsed.singular, plural: pluralName), quantity: quantity)
        case .plain:
            return Row(
                name: styled(parsed.singular, plural: plainShouldPlural(parsed.singular, parts)),
                quantity: plainQuantity(parts)
            )
        }
    }

    private struct Group {
        var parsed: Parsed
        var shares: [Share]
    }

    static func combine(_ items: [(name: String, amount: Double, unit: String)]) -> [Row] {
        var order: [String] = []
        var groups: [String: Group] = [:]
        for item in items {
            guard let parsed = parse(name: item.name) else { continue }
            var group = groups[parsed.key] ?? Group(parsed: parsed, shares: [])
            if groups[parsed.key] == nil {
                order.append(parsed.key)
            }
            group.shares.append(Share(amount: item.amount, unit: item.unit))
            groups[parsed.key] = group
        }
        return order.compactMap { key in
            guard let group = groups[key] else { return nil }
            return present(parsed: group.parsed, shares: group.shares)
        }
    }

    /// Checks the Smith's-list cases. Empty means the merger is sound.
    static func problems() -> [String] {
        var failures: [String] = []
        func expect(_ condition: Bool, _ message: String) {
            if !condition { failures.append(message) }
        }

        for lone in ["Boneless", "Skinless", "Large", "Fresh", "Finely", "Optional", "Optional toppings", "For serving", "Toppings"] {
            expect(parse(name: lone) == nil, "kept non-food \(lone)")
        }
        for hidden in ["Ground cumin", "Light olive oil", "Dried oregano", "Kosher salt", "Mexican Seasoning", "Taco seasoning", "Italian seasoning", "extra-virgin olive oil"] {
            expect(parse(name: hidden) == nil, "pantry item was kept: \(hidden)")
        }
        expect(matchKey("Large lime") == "lime" && matchKey("Lime") == "lime", "limes did not match")
        expect(matchKey("Finely cilantro") == "cilantro" && matchKey("Cilantro") == "cilantro", "cilantro did not match")
        expect(matchKey("Frozen corn") == "corn" && matchKey("Corn") == "corn", "corn did not match")
        expect(matchKey("chicken broth") == matchKey("chicken stock"), "broth and stock did not match")
        expect(matchKey("garlic cloves") == "garlic" && matchKey("minced garlic") == "garlic", "garlic did not match")
        expect(matchKey("jalapeno") == matchKey("jalapeno peppers") && matchKey("jalapeño") == "jalapeno", "jalapeno did not match")
        expect(matchKey("ground beef") == "ground beef", "ground beef lost its name")
        expect(matchKey("bell pepper") == "bell pepper", "bell pepper collapsed to pepper")
        expect(!matchKey("Corn tortillas )").contains(")") && !matchKey("Corn tortillas )").contains("("), "paren survived")

        let rows = combine([
            ("Black beans", 15, "oz"),
            ("boneless, skinless chicken thighs", 1, "lb"),
            ("Chicken Thighs", 6, ""),
            ("Chicken breasts", 1, "lb"),
            ("Chicken broth", 2, "lb"),
            ("chicken stock", 2, "cup"),
            ("Cilantro", 5.75, "tbsp"),
            ("Finely cilantro", 4, "tbsp"),
            ("Corn", 15, "oz"),
            ("Corn tortillas )", 8, ""),
            ("Cream cheese", 1, ""),
            ("Crushed tomatoes", 1.75, "lb"),
            ("Dried oregano", 0.75, "tsp"),
            ("Frozen corn", 8, "tbsp"),
            ("Garlic", 1, "tsp"),
            ("Garlic cloves", 4, ""),
            ("(15.5-ounce) cans Great Northern white beans (drained and rinsed)", 2, ""),
            ("(4-ounce) cans diced green chiles (mild)", 2, ""),
            ("(10-ounce) can green enchilada sauce", 1, ""),
            ("Ground cumin", 1.5, "tbsp"),
            ("Jalapeno peppers", 1, ""),
            ("Large avocado", 1, ""),
            ("Large lime", 1, ""),
            ("Large yellow onion", 1, ""),
            ("Light olive oil", 2, "tbsp"),
            ("Lime", 1, ""),
            ("Lime juice", 2.5, "tbsp"),
            ("Mexican Seasoning", 1, "tbsp"),
            ("Optional toppings", 1, ""),
            ("Kosher salt", 1, "tsp"),
            ("ground beef", 1, "lb"),
            ("bell pepper", 1, "")
        ])
        let expected: [Row] = [
            Row(name: "Black beans", quantity: "1 can"),
            Row(name: "Chicken thighs", quantity: "1 lb + 6"),
            Row(name: "Chicken breasts", quantity: "1 lb"),
            Row(name: "Chicken broth", quantity: "2 lbs + 2 cups"),
            Row(name: "Cilantro", quantity: "1 bunch"),
            Row(name: "Corn", quantity: "1 can"),
            Row(name: "Corn tortillas", quantity: "8"),
            Row(name: "Cream cheese", quantity: "1"),
            Row(name: "Crushed tomatoes", quantity: "1 can"),
            Row(name: "Garlic", quantity: "5 cloves"),
            Row(name: "Great northern white beans", quantity: "2 cans"),
            Row(name: "Green chiles", quantity: "2"),
            Row(name: "Green enchilada sauce", quantity: "1"),
            Row(name: "Jalapeno", quantity: "1"),
            Row(name: "Avocado", quantity: "1"),
            Row(name: "Limes", quantity: "4"),
            Row(name: "Yellow onion", quantity: "1"),
            Row(name: "Ground beef", quantity: "1 lb"),
            Row(name: "Bell pepper", quantity: "1")
        ]
        if rows != expected {
            failures.append("merged rows\n\(rows)\nexpected\n\(expected)")
        }
        let onion = combine([("onion", 2, "cup")])
        expect(onion == [Row(name: "Onions", quantity: "2")], "onions were not counted whole: \(onion)")
        return failures
    }

    private static func kind(for key: String) -> Kind {
        if herbs.contains(key) { return .herb }
        if key == "garlic" { return .garlic }
        if key == "lime" { return .lime }
        if key == "onion" || (key.hasSuffix(" onion") && key != "green onion" && key != "spring onion") {
            return .onion
        }
        if let ounces = canOunces(key) { return .canned(ounces) }
        return .plain
    }

    private static func canOunces(_ key: String) -> Double? {
        if key.contains("tortilla") || key.contains("meal") || key.contains("starch")
            || key.contains("chip") || key.contains("bread") || key.contains("muffin") {
            return nil
        }
        if key == "corn" || key.hasSuffix(" corn") { return 15 }
        if key.contains("bean") && !key.contains("green bean") { return 15 }
        if key == "crushed tomato" || key == "diced tomato" || key == "whole tomato"
            || key.hasPrefix("crushed tomato") || key.hasPrefix("diced tomato") {
            return 28
        }
        return nil
    }

    private static func foodWords(_ raw: String) -> [String]? {
        var text = raw.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        text = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\(\)\[\]\{\}]"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[;:]+"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(
            of: #"\d+(?:\.\d+)?\s*[-‐‑–]?\s*(?:ounces|ounce|oz)\b"#,
            with: " ",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "extra-virgin", with: " ")
        text = text.replacingOccurrences(of: "extra virgin", with: " ")
        text = text.replacingOccurrences(of: "drained and rinsed", with: " ")
        text = text.replacingOccurrences(of: "rinsed and drained", with: " ")
        text = text.replacingOccurrences(of: #"\bto serve\b.*$"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\bfor\b.*$"#, with: " ", options: .regularExpression)
        text = collapse(text).trimmingCharacters(in: CharacterSet(charactersIn: ",."))
        if text.isEmpty || headers.contains(text) { return nil }

        var kept: [String] = []
        for segment in text.split(separator: ",").map({ collapse(String($0)) }) where !segment.isEmpty {
            var words = segment.split(separator: " ").map(String.init)
            words = stripContainers(words)
            words = stripListed(words, prepWords)
            words = stripListed(words, descriptors)
            words = stripGroundIfSpice(words)
            words = trimJoiners(words)
            if !hasFood(words) { continue }
            kept.append(contentsOf: words)
        }
        var words = trimJoiners(stripGroundIfSpice(stripListed(stripListed(kept, prepWords), descriptors)))
        if !hasFood(words) { return nil }
        words = words.map(singular)
        words = synonyms(words)
        words = words.map(singular)
        if !hasFood(words) { return nil }
        return words
    }

    private static func stripContainers(_ words: [String]) -> [String] {
        var words = words
        while let first = words.first, containers.contains(first) {
            words.removeFirst()
            if words.first == "of" { words.removeFirst() }
        }
        return words
    }

    private static func stripListed(_ words: [String], _ banned: Set<String>) -> [String] {
        words.filter { !banned.contains($0) }
    }

    private static func stripGroundIfSpice(_ words: [String]) -> [String] {
        guard words.contains("ground") else { return words }
        let rest = words.filter { $0 != "ground" }
        if rest.contains(where: { meats.contains($0) }) { return words }
        if rest.contains(where: { spices.contains($0) }) { return rest }
        return words
    }

    private static func trimJoiners(_ words: [String]) -> [String] {
        var words = words
        while words.first == "and" || words.first == "or" { words.removeFirst() }
        while words.last == "and" || words.last == "or" { words.removeLast() }
        return words
    }

    private static func hasFood(_ words: [String]) -> Bool {
        words.contains { word in
            !descriptors.contains(word) && !prepWords.contains(word) && !nonFood.contains(word)
                && !containers.contains(word) && word != "ground" && word != "and" && word != "or" && word != "of"
        }
    }

    private static func synonyms(_ words: [String]) -> [String] {
        var words = words.map { $0 == "stock" ? "broth" : $0 }
        if words.contains("garlic") {
            words.removeAll { $0 == "clove" || $0 == "head" }
        }
        if words.contains("lime") && words.contains("juice") {
            words.removeAll { $0 == "juice" }
        }
        if words.contains("jalapeno") {
            words.removeAll { $0 == "pepper" }
        }
        var seen = Set<String>()
        return words.filter { seen.insert($0).inserted }
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

    private static func styled(_ singular: String, plural: Bool) -> String {
        let words = singular.split(separator: " ").map(String.init)
        guard var last = words.last else { return "" }
        if plural || alwaysPlural.contains(last) {
            last = pluralWord(last)
        } else if last == "chili" {
            last = "chile"
        }
        var copy = words
        copy[copy.count - 1] = last
        return sentence(copy.joined(separator: " "))
    }

    private static func pluralWord(_ word: String) -> String {
        if word == "chili" || word == "chile" { return "chiles" }
        if ["jalapeno", "avocado"].contains(word) { return word + "s" }
        if word.hasSuffix("o") { return word + "es" }
        if word.hasSuffix("y"), let previous = word.dropLast().last, !"aeiou".contains(previous) {
            return String(word.dropLast()) + "ies"
        }
        if word.hasSuffix("ch") || word.hasSuffix("sh") || word.hasSuffix("x") || word.hasSuffix("z") {
            return word + "es"
        }
        if word.hasSuffix("s") { return word }
        return word + "s"
    }

    private static func sentence(_ text: String) -> String {
        guard let first = text.first else { return "" }
        return String(first).uppercased() + text.dropFirst()
    }

    private static func plainShouldPlural(_ singular: String, _ parts: [Share]) -> Bool {
        let counted = parts.filter { !isMeasured($0.unit) }.reduce(0) { $0 + $1.amount }
        if counted > 1.001 { return true }
        if counted > 0.001 { return false }
        let last = singular.split(separator: " ").last.map(String.init) ?? ""
        return cuts.contains(last)
    }

    private static func isMeasured(_ unit: String) -> Bool {
        ["tsp", "tbsp", "cup", "oz", "lb", "g", "kg", "ml", "l", "fl oz"].contains(unit)
    }

    private static func plainQuantity(_ parts: [Share]) -> String {
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
        return order.compactMap { family -> String? in
            guard let total = totals[family], total > 0.001 else { return nil }
            return family.label(total)
        }.joined(separator: " + ")
    }

    private static func herbQuantity(_ parts: [Share]) -> String {
        var bunches = 0.0
        var volume = false
        for part in parts {
            switch part.unit {
            case "tsp", "tbsp", "cup", "sprig": volume = true
            default: bunches += part.amount
            }
        }
        if volume { bunches = max(bunches, 1) }
        guard bunches > 0.001 else { return "" }
        return CookingAmount.labeled(whole(bunches), unit: "bunch", fractionsOnly: true)
    }

    private static func onionCount(_ parts: [Share]) -> Double {
        var wholes = 0.0
        var spoons = false
        for part in parts {
            switch part.unit {
            case "cup": wholes += part.amount
            case "tsp", "tbsp": spoons = true
            case "lb": wholes += part.amount * 2
            case "oz": wholes += part.amount / 8
            default: wholes += part.amount
            }
        }
        if spoons && wholes < 0.001 { wholes = 1 }
        return wholes > 0.001 ? whole(wholes) : 0
    }

    private static func limeCount(_ parts: [Share]) -> Double {
        var wholes = 0.0
        var tbsp = 0.0
        for part in parts {
            switch part.unit {
            case "tbsp": tbsp += part.amount
            case "tsp": tbsp += part.amount / 3
            case "cup": tbsp += part.amount * 16
            default: wholes += part.amount
            }
        }
        if tbsp > 0.001 { wholes += (tbsp / 2).rounded(.up) }
        return wholes
    }

    private static func garlicQuantity(_ parts: [Share]) -> String {
        var cloves = 0.0
        var heads = 0.0
        for part in parts {
            switch part.unit {
            case "head": heads += part.amount
            case "tsp": cloves += part.amount
            case "tbsp": cloves += part.amount * 3
            case "cup": cloves += part.amount * 48
            default: cloves += part.amount
            }
        }
        var bits: [String] = []
        if heads > 0.001 {
            bits.append(CookingAmount.labeled(whole(heads), unit: "head", fractionsOnly: true))
        }
        if cloves > 0.001 {
            bits.append(CookingAmount.labeled(whole(cloves), unit: "clove", fractionsOnly: true))
        }
        return bits.joined(separator: " + ")
    }

    private static func canCount(_ parts: [Share], ounces: Double) -> Double {
        var cans = 0.0
        var volume = false
        for part in parts {
            switch part.unit {
            case "oz": cans += part.amount / ounces
            case "lb": cans += (part.amount * 16) / ounces
            case "tsp", "tbsp", "cup": volume = true
            default: cans += part.amount
            }
        }
        if cans > 0.001 { return max(1, cans.rounded()) }
        return volume ? 1 : 0
    }

    private static func countText(_ count: Double) -> String {
        guard count > 0.001 else { return "" }
        return CookingAmount.format(count, unit: "", fractionsOnly: true)
    }

    private static func whole(_ amount: Double) -> Double {
        guard amount > 0.001 else { return 0 }
        return (amount - 0.001).rounded(.up)
    }

    private static func collapse(_ text: String) -> String {
        text.split(separator: " ").joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Match key and the name stored on a pantry staple.
private enum GroceryName {
    static func display(_ raw: String) -> String {
        GroceryPlanner.displayName(for: raw)
    }

    static func key(_ name: String) -> String {
        GroceryPlanner.matchKey(name)
    }
}

private enum PantryStaples {
    private static let storageKey = "pantryStaples.v1"
    private static let migrationKey = "pantryStaples.v64Defaults"
    private static let seed = [
        "Salt", "Pepper", "Black pepper", "Kosher salt", "Olive oil", "Vegetable oil",
        "Cooking spray", "Water", "Sugar", "Flour", "Garlic powder", "Onion powder",
        "Paprika", "Cumin", "Chili powder", "Oregano", "Basil", "Cinnamon",
        "Mexican seasoning", "Taco seasoning", "Italian seasoning",
        "Baking soda", "Baking powder"
    ]
    private static let addedIn64 = ["Mexican seasoning", "Taco seasoning", "Italian seasoning"]

    static func names() -> [String] {
        if UserDefaults.standard.object(forKey: storageKey) == nil {
            save(seed)
            UserDefaults.standard.set(true, forKey: migrationKey)
            return seed
        }
        var stored = load()
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            for item in addedIn64 where !stored.contains(where: { GroceryName.key($0) == GroceryName.key(item) }) {
                stored.append(item)
            }
            save(stored)
            UserDefaults.standard.set(true, forKey: migrationKey)
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

//
//  DataManager.swift
//  OurWeek
//
//  Provides CRUD operations for all Core Data entities
//  and bridges private + shared store data for the views.
//

import SwiftUI
import CoreData
import CloudKit

@Observable
class DataManager {
    let persistenceController: PersistenceController
    private var viewContext: NSManagedObjectContext {
        persistenceController.container.viewContext
    }

    var allHouseholds: [Household] = []
    var currentHousehold: Household?
    var syncStatus: SyncStatus = .idle

    enum SyncStatus {
        case idle
        case syncing
        case error(String)
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        loadOrCreateHousehold()

        // Listen for Core Data remote changes to detect when a shared household arrives
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistenceController.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.loadOrCreateHousehold()
        }
        setupSyncListener()
    }

    // MARK: - Household

    /// Load existing households and select the active one (preferring shared)
    func loadOrCreateHousehold() {
        let request: NSFetchRequest<Household> = Household.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true)]

        do {
            let results = try viewContext.fetch(request)
            allHouseholds = results

            // If we don't have a current household, or if the current household was deleted, Pick one
            if currentHousehold == nil || !results.contains(currentHousehold!) {
                // Prefer a shared household over a private one automatically
                if let shared = results.first(where: { persistenceController.isShared(object: $0) }) {
                    currentHousehold = shared
                } else {
                    currentHousehold = results.first
                }
            } else {
                // Even if we have a current one, if a NEW shared one just arrived, and our current is private, switch to it automatically
                let hasShared = results.contains { persistenceController.isShared(object: $0) }
                let currentIsPrivate = !persistenceController.isShared(object: currentHousehold!)

                if hasShared && currentIsPrivate {
                    currentHousehold = results.first(where: { persistenceController.isShared(object: $0) })
                }
            }
        } catch {
            print("Error fetching household: \(error)")
        }
    }

    /// Check if the user is the owner of this household (lives in the private store)
    func isOwner(of household: Household) -> Bool {
        guard let store = household.objectID.persistentStore else { return true }
        return store == persistenceController.privatePersistentStore
    }

    /// Switch the active household (for users with multiple)
    func switchHousehold(to household: Household) {
        currentHousehold = household
    }

    /// Delete a household (only safely deletes private ones or owned ones)
    func deleteHousehold(_ household: Household) {
        if !isOwner(of: household) && persistenceController.isShared(object: household) {
            print("WARNING: Prevented accidental deletion of a shared household by participant. Use 'Leave' instead.")
            return
        }
        
        if currentHousehold == household {
            currentHousehold = nil
        }
        viewContext.delete(household)
        save()
        loadOrCreateHousehold()
    }

    /// Merge data from a source household into a target household, then delete the source.
    func mergeHousehold(from source: Household, to target: Household) {
        // Deep copy Calendar Events
        let eventsRequest: NSFetchRequest<CalendarEvent> = CalendarEvent.fetchRequest()
        eventsRequest.predicate = NSPredicate(format: "household == %@", source)
        if let events = try? viewContext.fetch(eventsRequest) {
            for event in events {
                _ = createEvent(
                    title: event.title ?? "Untitled",
                    date: event.date ?? Date(),
                    endDate: event.endDate,
                    notes: event.notes,
                    color: event.color,
                    isAllDay: event.isAllDay,
                    in: target
                )
            }
        }

        // Deep copy Meal Plans
        let mealsRequest: NSFetchRequest<MealPlan> = MealPlan.fetchRequest()
        mealsRequest.predicate = NSPredicate(format: "household == %@", source)
        if let meals = try? viewContext.fetch(mealsRequest) {
            for meal in meals {
                _ = createMealPlan(
                    title: meal.title ?? "Untitled",
                    date: meal.date ?? Date(),
                    mealType: meal.mealType ?? "dinner",
                    notes: meal.notes,
                    ingredients: meal.ingredients,
                    recipe: nil, // We lose explicit recipe links during merge to avoid cross-store faults, but keep ingredients text
                    in: target
                )
            }
        }

        // Deep copy Shopping Lists
        let listsRequest: NSFetchRequest<ShoppingList> = ShoppingList.fetchRequest()
        listsRequest.predicate = NSPredicate(format: "household == %@", source)
        if let lists = try? viewContext.fetch(listsRequest) {
            for list in lists {
                let newList = createShoppingList(name: list.name ?? "List", in: target)
                // Copy list items
                if let items = list.items as? Set<ShoppingItem> {
                    for item in items {
                        _ = addShoppingItem(
                            name: item.name ?? "",
                            quantity: item.quantity,
                            category: item.category,
                            to: newList
                        )
                    }
                }
            }
        }

        // Deep copy Recipes
        let recipesRequest: NSFetchRequest<Recipe> = Recipe.fetchRequest()
        recipesRequest.predicate = NSPredicate(format: "household == %@", source)
        if let recipes = try? viewContext.fetch(recipesRequest) {
            for recipe in recipes {
                // Read structured inputs
                let ingredients = sortedIngredients(for: recipe).map { ing in
                    IngredientInput(
                        amount: ing.amount,
                        unit: ing.unit ?? "",
                        name: ing.name ?? "",
                        notes: ing.notes ?? "",
                        sectionName: ing.sectionName ?? "",
                        sortOrder: ing.sortOrder
                    )
                }
                
                let instructions = sortedInstructions(for: recipe).map { ins in
                    InstructionInput(
                        stepNumber: ins.stepNumber,
                        text: ins.text ?? "",
                        timerSeconds: ins.timerSeconds
                    )
                }

                _ = createRecipe(
                    name: recipe.name ?? "Untitled",
                    recipeDescription: recipe.recipeDescription,
                    prepTime: recipe.prepTime,
                    cookTime: recipe.cookTime,
                    servings: recipe.servings,
                    difficulty: recipe.difficulty,
                    categories: recipe.categories,
                    tags: recipe.tags,
                    notes: recipe.notes,
                    imageData: recipe.imageData,
                    sourceURL: recipe.sourceURL,
                    sourceDomain: recipe.sourceDomain,
                    ingredientInputs: ingredients,
                    instructionInputs: instructions,
                    in: target
                )
            }
        }

        // Finally, delete the source household
        viewContext.delete(source)
        save()
        loadOrCreateHousehold()
    }

    /// Create a new Household
    func createHousehold(name: String, ownerName: String) -> Household {
        let household = Household(context: viewContext)
        household.id = UUID()
        household.name = name
        household.ownerName = ownerName
        household.createdAt = Date()
        save()
        currentHousehold = household
        return household
    }

    // MARK: - Sync Notifications

    private func setupSyncListener() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            // We only care if an import or export finishes
            if event.endDate != nil && event.succeeded {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastCloudKitSyncDate")
            }
        }
    }

    // MARK: - Calendar Events

    func createEvent(
        title: String,
        date: Date,
        endDate: Date? = nil,
        notes: String? = nil,
        color: String? = nil,
        isAllDay: Bool = false,
        in household: Household? = nil
    ) -> CalendarEvent {
        let event = CalendarEvent(context: viewContext)
        event.id = UUID()
        event.title = title
        event.date = date
        event.endDate = endDate
        event.notes = notes
        event.color = color
        event.isAllDay = isAllDay
        event.createdAt = Date()
        event.household = household ?? currentHousehold
        save()
        return event
    }

    func fetchEvents(for date: Date? = nil, in household: Household? = nil) -> [CalendarEvent] {
        let request: NSFetchRequest<CalendarEvent> = CalendarEvent.fetchRequest()
        var predicates: [NSPredicate] = []

        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }

        if let date = date {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            predicates.append(NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CalendarEvent.date, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching events: \(error)")
            return []
        }
    }

    func fetchWeekEvents(from startDate: Date, in household: Household? = nil) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }

        let request: NSFetchRequest<CalendarEvent> = CalendarEvent.fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        ]
        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CalendarEvent.date, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching week events: \(error)")
            return []
        }
    }

    // MARK: - Meal Plans

    func createMealPlan(
        title: String,
        date: Date,
        mealType: String,
        notes: String? = nil,
        ingredients: String? = nil,
        recipe: Recipe? = nil,
        in household: Household? = nil
    ) -> MealPlan {
        let meal = MealPlan(context: viewContext)
        meal.id = UUID()
        meal.title = title
        meal.date = date
        meal.mealType = mealType
        meal.notes = notes
        meal.ingredients = ingredients
        meal.recipe = recipe
        meal.household = household ?? currentHousehold
        save()
        return meal
    }

    func fetchMealPlans(for date: Date? = nil, in household: Household? = nil) -> [MealPlan] {
        let request: NSFetchRequest<MealPlan> = MealPlan.fetchRequest()
        var predicates: [NSPredicate] = []

        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }

        if let date = date {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start)!
            predicates.append(NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealPlan.date, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching meal plans: \(error)")
            return []
        }
    }

    func fetchWeekMealPlans(from startDate: Date, in household: Household? = nil) -> [MealPlan] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }

        let request: NSFetchRequest<MealPlan> = MealPlan.fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "date >= %@ AND date < %@", start as NSDate, end as NSDate)
        ]
        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MealPlan.date, ascending: true)]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching week meal plans: \(error)")
            return []
        }
    }

    func updateMealPlan(
        _ meal: MealPlan,
        title: String,
        mealType: String,
        notes: String? = nil,
        ingredients: String? = nil,
        recipe: Recipe? = nil
    ) {
        meal.title = title
        meal.mealType = mealType
        meal.notes = notes
        meal.ingredients = ingredients
        meal.recipe = recipe
        save()
    }

    func deleteMealPlan(_ meal: MealPlan) {
        viewContext.delete(meal)
        save()
    }

    // MARK: - Recipes

    func updateRecipeImage(recipe: Recipe, newImageData: Data?) {
        recipe.imageData = newImageData
        recipe.updatedAt = Date()
        save()
    }

    enum RecipeSortOption: String, CaseIterable {
        case recentlyAdded = "Recently Added"
        case alphabetical = "A → Z"
        case favoritesFirst = "Favorites First"
    }

    struct IngredientInput {
        var amount: Double
        var unit: String
        var name: String
        var notes: String
        var sectionName: String
        var sortOrder: Int16
    }

    struct InstructionInput {
        var stepNumber: Int16
        var text: String
        var timerSeconds: Int32
    }

    func createRecipe(
        name: String,
        recipeDescription: String? = nil,
        prepTime: Int16 = 0,
        cookTime: Int16 = 0,
        servings: Int16 = 1,
        difficulty: String? = nil,
        categories: String? = nil,
        tags: String? = nil,
        notes: String? = nil,
        imageData: Data? = nil,
        sourceURL: String? = nil,
        sourceDomain: String? = nil,
        ingredientInputs: [IngredientInput] = [],
        instructionInputs: [InstructionInput] = [],
        in household: Household? = nil
    ) -> Recipe {
        let recipe = Recipe(context: viewContext)
        recipe.id = UUID()
        recipe.name = name
        recipe.recipeDescription = recipeDescription
        recipe.prepTime = prepTime
        recipe.cookTime = cookTime
        recipe.servings = servings
        recipe.difficulty = difficulty
        recipe.categories = categories
        recipe.tags = tags
        recipe.notes = notes
        recipe.imageData = imageData
        recipe.isFavorite = false
        recipe.rating = 0
        recipe.timesCooked = 0
        recipe.sourceURL = sourceURL
        recipe.sourceDomain = sourceDomain
        recipe.createdAt = Date()
        recipe.updatedAt = Date()
        recipe.household = household ?? currentHousehold

        // Build legacy string fields for backward compat
        recipe.ingredients = ingredientInputs.map { "\($0.amount) \($0.unit) \($0.name)".trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        recipe.instructions = instructionInputs.map { $0.text }.joined(separator: "\n")

        // Create structured ingredients
        for input in ingredientInputs {
            let ing = RecipeIngredient(context: viewContext)
            ing.id = UUID()
            ing.amount = input.amount
            ing.unit = input.unit
            ing.name = input.name
            ing.notes = input.notes
            ing.sectionName = input.sectionName
            ing.sortOrder = input.sortOrder
            ing.recipe = recipe
        }

        // Create structured instructions
        for input in instructionInputs {
            let inst = RecipeInstruction(context: viewContext)
            inst.id = UUID()
            inst.stepNumber = input.stepNumber
            inst.text = input.text
            inst.timerSeconds = input.timerSeconds
            inst.recipe = recipe
        }

        save()
        return recipe
    }

    func updateRecipe(
        _ recipe: Recipe,
        name: String,
        recipeDescription: String? = nil,
        prepTime: Int16 = 0,
        cookTime: Int16 = 0,
        servings: Int16 = 1,
        difficulty: String? = nil,
        categories: String? = nil,
        tags: String? = nil,
        notes: String? = nil,
        imageData: Data? = nil,
        sourceURL: String? = nil,
        sourceDomain: String? = nil,
        ingredientInputs: [IngredientInput] = [],
        instructionInputs: [InstructionInput] = []
    ) {
        recipe.name = name
        recipe.recipeDescription = recipeDescription
        recipe.prepTime = prepTime
        recipe.cookTime = cookTime
        recipe.servings = servings
        recipe.difficulty = difficulty
        recipe.categories = categories
        recipe.tags = tags
        recipe.notes = notes
        recipe.imageData = imageData
        recipe.sourceURL = sourceURL ?? recipe.sourceURL
        recipe.sourceDomain = sourceDomain ?? recipe.sourceDomain
        recipe.updatedAt = Date()

        // Update legacy strings
        recipe.ingredients = ingredientInputs.map { "\($0.amount) \($0.unit) \($0.name)".trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        recipe.instructions = instructionInputs.map { $0.text }.joined(separator: "\n")

        // Replace ingredients
        if let existing = recipe.recipeIngredients as? Set<RecipeIngredient> {
            for old in existing { viewContext.delete(old) }
        }
        for input in ingredientInputs {
            let ing = RecipeIngredient(context: viewContext)
            ing.id = UUID()
            ing.amount = input.amount
            ing.unit = input.unit
            ing.name = input.name
            ing.notes = input.notes
            ing.sectionName = input.sectionName
            ing.sortOrder = input.sortOrder
            ing.recipe = recipe
        }

        // Replace instructions
        if let existing = recipe.recipeInstructions as? Set<RecipeInstruction> {
            for old in existing { viewContext.delete(old) }
        }
        for input in instructionInputs {
            let inst = RecipeInstruction(context: viewContext)
            inst.id = UUID()
            inst.stepNumber = input.stepNumber
            inst.text = input.text
            inst.timerSeconds = input.timerSeconds
            inst.recipe = recipe
        }

        save()
    }

    /// True when the current household already has this recipe.
    /// Matches a non-empty `sourceURL`, or the same name + sourceURL pair.
    func hasDuplicateRecipe(sourceURL: String, name: String, in household: Household? = nil) -> Bool {
        let request: NSFetchRequest<Recipe> = Recipe.fetchRequest()
        var predicates: [NSPredicate] = []

        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }

        let trimmedURL = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var matchers: [NSPredicate] = []
        if !trimmedURL.isEmpty {
            matchers.append(NSPredicate(format: "sourceURL ==[cd] %@", trimmedURL))
        }
        if !trimmedName.isEmpty {
            let nameMatch = NSPredicate(format: "name ==[cd] %@", trimmedName)
            if trimmedURL.isEmpty {
                matchers.append(NSCompoundPredicate(andPredicateWithSubpredicates: [
                    nameMatch,
                    NSPredicate(format: "sourceURL == nil OR sourceURL == ''")
                ]))
            } else {
                matchers.append(NSCompoundPredicate(andPredicateWithSubpredicates: [
                    nameMatch,
                    NSPredicate(format: "sourceURL ==[cd] %@", trimmedURL)
                ]))
            }
        }

        guard !matchers.isEmpty else { return false }
        predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: matchers))
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1

        return ((try? viewContext.count(for: request)) ?? 0) > 0
    }

    func deleteRecipe(_ recipe: Recipe) {
        viewContext.delete(recipe)
        save()
    }

    /// Delete many recipes in one save so CloudKit gets a single changeset.
    /// Ingredients/instructions cascade from the Core Data model.
    func deleteRecipes(_ recipes: [Recipe]) {
        guard !recipes.isEmpty else { return }
        for recipe in recipes {
            viewContext.delete(recipe)
        }
        save()
    }

    /// Replace categories on every selected recipe. Empty / nil clears them.
    func setRecipesCategories(_ recipes: [Recipe], categories: String?) {
        guard !recipes.isEmpty else { return }
        let now = Date()
        for recipe in recipes {
            recipe.categories = categories
            recipe.updatedAt = now
        }
        save()
    }

    /// Replace tags on every selected recipe. Empty / nil clears them.
    func setRecipesTags(_ recipes: [Recipe], tags: String?) {
        guard !recipes.isEmpty else { return }
        let now = Date()
        for recipe in recipes {
            recipe.tags = tags
            recipe.updatedAt = now
        }
        save()
    }

    /// Append tags to every selected recipe, de-duping case-insensitively.
    func addTagsToRecipes(_ recipes: [Recipe], tags: String) {
        guard !recipes.isEmpty else { return }
        let now = Date()
        for recipe in recipes {
            recipe.tags = RecipeLabelFormatting.mergedTags(existing: recipe.tags, adding: tags)
            recipe.updatedAt = now
        }
        save()
    }

    func toggleRecipeFavorite(_ recipe: Recipe) {
        recipe.isFavorite.toggle()
        recipe.updatedAt = Date()
        save()
    }

    func updateRecipeRating(_ recipe: Recipe, rating: Int16) {
        recipe.rating = rating
        recipe.updatedAt = Date()
        save()
    }

    func incrementTimesCooked(_ recipe: Recipe) {
        recipe.timesCooked += 1
        recipe.lastCookedDate = Date()
        recipe.updatedAt = Date()
        save()
    }

    func fetchRecipes(
        searchText: String = "",
        categories: String? = nil,
        difficulty: String? = nil,
        favoritesOnly: Bool = false,
        sortBy: RecipeSortOption = .recentlyAdded,
        in household: Household? = nil
    ) -> [Recipe] {
        let request: NSFetchRequest<Recipe> = Recipe.fetchRequest()
        var predicates: [NSPredicate] = []

        if let household = household ?? currentHousehold {
            predicates.append(NSPredicate(format: "household == %@", household))
        }
        if !searchText.isEmpty {
            predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", searchText))
        }
        if let categories = categories, !categories.isEmpty {
            predicates.append(NSPredicate(format: "categories CONTAINS[cd] %@", categories))
        }
        if let difficulty = difficulty, !difficulty.isEmpty {
            predicates.append(NSPredicate(format: "difficulty == %@", difficulty))
        }
        if favoritesOnly {
            predicates.append(NSPredicate(format: "isFavorite == YES"))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        switch sortBy {
        case .recentlyAdded:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Recipe.createdAt, ascending: false)]
        case .alphabetical:
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Recipe.name, ascending: true)]
        case .favoritesFirst:
            request.sortDescriptors = [
                NSSortDescriptor(keyPath: \Recipe.isFavorite, ascending: false),
                NSSortDescriptor(keyPath: \Recipe.createdAt, ascending: false)
            ]
        }

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching recipes: \(error)")
            return []
        }
    }

    func sortedIngredients(for recipe: Recipe) -> [RecipeIngredient] {
        guard let set = recipe.recipeIngredients as? Set<RecipeIngredient> else { return [] }
        return set.sorted { $0.sortOrder < $1.sortOrder }
    }

    func sortedInstructions(for recipe: Recipe) -> [RecipeInstruction] {
        guard let set = recipe.recipeInstructions as? Set<RecipeInstruction> else { return [] }
        return set.sorted { $0.stepNumber < $1.stepNumber }
    }

    // MARK: - Shopping Lists

    func createShoppingList(
        name: String,
        sortOrder: Int16? = nil,
        in household: Household? = nil
    ) -> ShoppingList {
        let list = ShoppingList(context: viewContext)
        list.id = UUID()
        list.name = name
        list.createdAt = Date()
        list.household = household ?? currentHousehold
        
        // Auto-assign next sort order if not provided
        if let order = sortOrder {
            list.sortOrder = order
        } else {
            let existing = fetchShoppingLists(in: household)
            list.sortOrder = Int16(existing.count)
        }
        
        save()
        return list
    }

    func fetchShoppingLists(in household: Household? = nil) -> [ShoppingList] {
        let request: NSFetchRequest<ShoppingList> = ShoppingList.fetchRequest()
        if let household = household ?? currentHousehold {
            request.predicate = NSPredicate(format: "household == %@", household)
        }
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ShoppingList.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ShoppingList.createdAt, ascending: false)
        ]

        do {
            return try viewContext.fetch(request)
        } catch {
            print("Error fetching shopping lists: \(error)")
            return []
        }
    }
    
    func reorderShoppingLists(_ lists: [ShoppingList]) {
        for (index, list) in lists.enumerated() {
            list.sortOrder = Int16(index)
        }
        save()
    }
    
    func deleteShoppingList(_ list: ShoppingList) {
        viewContext.delete(list)
        save()
        // Re-normalize sort orders
        let remaining = fetchShoppingLists()
        for (index, l) in remaining.enumerated() {
            l.sortOrder = Int16(index)
        }
        save()
    }

    // MARK: - Shopping Items

    func addShoppingItem(
        name: String,
        quantity: String? = nil,
        category: String? = nil,
        to list: ShoppingList
    ) -> ShoppingItem {
        let item = ShoppingItem(context: viewContext)
        item.id = UUID()
        item.name = name
        item.quantity = quantity
        item.category = category
        item.isChecked = false
        item.list = list
        save()
        return item
    }

    func toggleShoppingItem(_ item: ShoppingItem) {
        item.isChecked.toggle()
        save()
    }

    // MARK: - Sync Meal Plan
    
    func syncMealPlanToShoppingList(syncRecipes: Bool) {
        let calendar = Calendar.current
        let today = Calendar.current.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) else { return }
        
        let weekMeals = fetchWeekMealPlans(from: monday)
        let lists = fetchShoppingLists()
        
        // Find default generic store or the first one
        let targetList = lists.first(where: { $0.name?.lowercased().contains("grocery") == true }) ?? lists.first
        
        guard let list = targetList else { return }
        
        var newItems = [String]()
        
        for meal in weekMeals {
            // Add manual ingredients from meal plans
            if let ingredientsStr = meal.ingredients {
                let lines = ingredientsStr.components(separatedBy: "\n")
                for line in lines {
                    let parts = line.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let isChecked = parts[0] == "1"
                        let text = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        if !isChecked && !text.isEmpty {
                            newItems.append(text)
                        }
                    } else if parts.count == 1 {
                        let text = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            newItems.append(text)
                        }
                    }
                }
            }
            
            // Add recipe ingredients if enabled
            if syncRecipes, let recipe = meal.recipe {
                let recipeIngredients = sortedIngredients(for: recipe)
                for ing in recipeIngredients {
                    let name = ing.name ?? ""
                    let amount = ing.amount
                    let unit = ing.unit ?? ""
                    
                    var text = name
                    if amount > 0 {
                        let amountFormatter = NumberFormatter()
                        amountFormatter.minimumFractionDigits = 0
                        amountFormatter.maximumFractionDigits = 2
                        let amountStr = amountFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
                        text = "\(amountStr) \(unit) \(name)".trimmingCharacters(in: .whitespaces)
                    }
                    if !text.isEmpty {
                        newItems.append(text)
                    }
                }
            }
        }
        
        let existingItems = (list.items as? Set<ShoppingItem>)?.map({ $0.name?.lowercased().trimmingCharacters(in: .whitespaces) ?? "" }) ?? []
        let existingSet = Set(existingItems)
        
        for item in newItems {
            let lowerItem = item.lowercased().trimmingCharacters(in: .whitespaces)
            if !existingSet.contains(lowerItem) {
                _ = addShoppingItem(name: item, quantity: "", to: list)
            }
        }
        
        save()
    }

    // MARK: - Generic Operations

    func delete(_ object: NSManagedObject) {
        viewContext.delete(object)
        save()
    }

    func save() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Error saving context: \(nsError), \(nsError.userInfo)")
        }
    }
}

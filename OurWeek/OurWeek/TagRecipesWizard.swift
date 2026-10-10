import SwiftUI
import CoreData
import UIKit

/// Walks the library one recipe at a time so each gets the week-night tags Plan week matches on.
struct TagRecipesWizard: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    @State private var queue: [Recipe] = []
    @State private var index = 0
    @State private var checked: Set<String> = []
    @State private var taggedCount = 0
    @State private var didLoad = false
    @State private var nights = PlanCategory.recipeNights
    @State private var dishType = "Main"
    @State private var showNewNight = false
    @State private var newNightName = ""

    /// Course values in Recipe.categories. Only Main can be a dinner pick.
    static let dishTypes = ["Main", "Side", "Appetizer", "Dessert", "Breakfast", "Snack", "Drink"]
    private static let dinnerLabels: Set<String> = ["Main", "Dinner", "Full meal"]
    private let chipColumns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    private var current: Recipe? { index < queue.count ? queue[index] : nil }

    var body: some View {
        ZStack {
            Color.bgBase.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let recipe = current {
                    card(recipe)
                } else {
                    endScreen
                }
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .alert("New night", isPresented: $showNewNight) {
            TextField("Fondue, Brinner…", text: $newNightName)
            Button("Add") { addNight() }
            Button("Cancel", role: .cancel) { newNightName = "" }
        } message: {
            Text("It shows up as a chip everywhere you tag recipes.")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Done")
            Spacer()
            Text(current == nil ? "Tag recipes" : "\(index + 1) of \(queue.count)")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(HomeQuiet.quiet)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    // MARK: - Card

    private func card(_ recipe: Recipe) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photo(recipe)
                    Text(displayName(recipe))
                        .font(.system(size: 28, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                        .lineLimit(3)
                    if dishType == "Main" {
                        Text("Which nights does this fit?")
                            .font(.system(size: 15))
                            .foregroundStyle(HomeQuiet.quiet)
                        LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 10) {
                            ForEach(nights) { night in
                                chip(night)
                            }
                            newNightChip
                        }
                    } else {
                        Text("Won't show in dinner picks")
                            .font(.system(size: 15))
                            .foregroundStyle(HomeQuiet.quiet)
                            .padding(.vertical, 4)
                    }
                    Text("Dish type")
                        .font(.system(size: 15))
                        .foregroundStyle(HomeQuiet.quiet)
                        .padding(.top, 8)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(Self.dishTypes, id: \.self) { type in
                            dishChip(type)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: dishType)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            HStack(spacing: 12) {
                Button { advance() } label: {
                    Text("Skip")
                        .font(.system(size: 17))
                        .foregroundStyle(HomeQuiet.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Button { saveAndAdvance(recipe) } label: {
                    Text("Next")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .id(recipe.objectID)
    }

    private func photo(_ recipe: Recipe) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                if let data = recipe.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(red: 0.98, green: 0.96, blue: 0.94)
                        .overlay(
                            Image(systemName: "fork.knife")
                                .font(.system(size: 28))
                                .foregroundStyle(HomeQuiet.quiet)
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chip(_ night: PlanCategory) -> some View {
        let on = checked.contains(night.name)
        return Button {
            if on { checked.remove(night.name) } else { checked.insert(night.name) }
        } label: {
            HStack(spacing: 6) {
                Text(night.emoji)
                Text(night.name)
                    .font(.system(size: 14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .foregroundStyle(on ? Color.white : HomeQuiet.ink)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(on ? Color.terra500 : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Color.terra600 : HomeQuiet.buttonStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(night.name)
        .accessibilityValue(on ? "Selected" : "Not selected")
    }

    private var newNightChip: some View {
        Button {
            newNightName = ""
            showNewNight = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("New")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.terra600)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HomeQuiet.buttonStroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New night")
    }

    private func dishChip(_ type: String) -> some View {
        let on = dishType == type
        return Button {
            dishType = type
        } label: {
            Text(type)
                .font(.system(size: 14))
                .foregroundStyle(on ? Color.white : HomeQuiet.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(on ? Color.terra500 : Color.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(on ? Color.terra600 : HomeQuiet.buttonStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dish type \(type)")
        .accessibilityValue(on ? "Selected" : "Not selected")
    }

    private func addNight() {
        let name = newNightName
        newNightName = ""
        guard let night = CustomNightStore.add(name) else { return }
        if !nights.contains(where: { $0.id == night.id }) {
            nights.append(night)
        }
        checked.insert(night.name)
    }

    // MARK: - End

    private var endScreen: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("\(taggedCount) \(taggedCount == 1 ? "recipe" : "recipes") tagged")
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Text("Plan week will use these tags to suggest dinners.")
                .font(.system(size: 15))
                .foregroundStyle(HomeQuiet.quiet)
                .multilineTextAlignment(.center)
            Spacer()
            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.terra500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    // MARK: - Flow

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let all = dataManager.fetchRecipes(sortBy: .recentlyAdded)
        queue = all.enumerated().sorted { a, b in
            let ka = (Self.isMain(a.element) ? 0 : 1, Self.hasNightTag(a.element) ? 1 : 0)
            let kb = (Self.isMain(b.element) ? 0 : 1, Self.hasNightTag(b.element) ? 1 : 0)
            return ka != kb ? ka < kb : a.offset < b.offset
        }.map(\.element)
        prepareChecks()
    }

    private func prepareChecks() {
        guard let recipe = current else { checked = []; return }
        dishType = Self.currentDishType(recipe)
        let existing = Set(RecipeLabelFormatting.decodeTags(recipe.tags).map { $0.lowercased() })
        var result: Set<String> = []
        for night in nights {
            if existing.contains(night.name.lowercased()) {
                result.insert(night.name)
                continue
            }
            // Strong title keyword only (10...29); 30+ already means tagged above.
            let score = PlanWeekCatalog.score(
                name: displayName(recipe),
                categories: recipe.categories,
                tags: recipe.tags,
                minutes: 0,
                category: night
            )
            if score >= 10 { result.insert(night.name) }
        }
        checked = result
    }

    private func saveAndAdvance(_ recipe: Recipe) {
        saveDishType(recipe)
        guard dishType == "Main" else {
            advance()
            return
        }
        let nightNames = Set(nights.map { $0.name.lowercased() })
        let others = RecipeLabelFormatting.decodeTags(recipe.tags)
            .filter { !nightNames.contains($0.lowercased()) }
        let chosen = nights.map(\.name).filter { checked.contains($0) }
        let tags = others + chosen
        let encoded = tags.isEmpty ? nil : tags.joined(separator: ", ")
        if encoded != recipe.tags {
            dataManager.setRecipesTags([recipe], tags: encoded)
        }
        if !chosen.isEmpty { taggedCount += 1 }
        advance()
    }

    /// Replaces only the course value; a non-main type also drops Main/Dinner/Full meal.
    private func saveDishType(_ recipe: Recipe) {
        let current = RecipeLabelFormatting.decodeCategories(recipe.categories)
        var updated = current.filter { label in
            !Self.dishTypes.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
        }
        if dishType != "Main" {
            updated = updated.filter { label in
                !Self.dinnerLabels.contains { $0.caseInsensitiveCompare(label) == .orderedSame }
            }
        }
        updated.insert(dishType)
        if updated != current {
            dataManager.setRecipesCategories([recipe], categories: RecipeLabelFormatting.encodeCategories(updated))
        }
    }

    /// The recipe's course from its categories, or a guess from its title.
    static func currentDishType(_ recipe: Recipe) -> String {
        let labels = RecipeLabelFormatting.decodeCategories(recipe.categories)
        for type in dishTypes where type != "Main" {
            if labels.contains(where: { $0.caseInsensitiveCompare(type) == .orderedSame }) { return type }
        }
        if labels.contains(where: { $0.caseInsensitiveCompare("Main") == .orderedSame }) { return "Main" }
        let title = (recipe.name ?? "").lowercased()
        let desserts = ["brownie", "cookie", "cake", "cupcake", "cheesecake", "pie", "dessert", "pudding", "fudge", "cobbler", "crisp", "tart"]
        if desserts.contains(where: { title.range(of: "\\b\($0)s?\\b", options: .regularExpression) != nil }) {
            return "Dessert"
        }
        return PlanWeekCatalog.looksLikeSide(recipe.name ?? "") ? "Side" : "Main"
    }

    private func advance() {
        index += 1
        prepareChecks()
    }

    private func displayName(_ recipe: Recipe) -> String {
        let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Recipe" : name
    }

    // MARK: - Shared checks (also used by the Plan week nudge)

    static func isMain(_ recipe: Recipe) -> Bool {
        PlanWeekCatalog.isDinnerMain(
            name: recipe.name ?? "",
            categories: recipe.categories,
            tags: recipe.tags,
            categoryID: ""
        )
    }

    static func hasNightTag(_ recipe: Recipe) -> Bool {
        let names = Set(PlanCategory.recipeNights.map { $0.name.lowercased() })
        return RecipeLabelFormatting.decodeTags(recipe.tags).contains { names.contains($0.lowercased()) }
    }

    /// True when Plan week should suggest tagging first: 3+ recipes and under 30% of mains tagged.
    static func needsTagging(_ recipes: [Recipe]) -> Bool {
        guard recipes.count >= 3 else { return false }
        let mains = recipes.filter(isMain)
        guard !mains.isEmpty else { return false }
        let tagged = mains.filter(hasNightTag).count
        return Double(tagged) / Double(mains.count) < 0.3
    }
}

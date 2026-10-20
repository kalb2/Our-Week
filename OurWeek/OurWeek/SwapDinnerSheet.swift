import SwiftUI
import UIKit
import CoreData

/// Swap one day's dinner for another recipe from his book.
/// Same ranking as Plan week: mains only, the night's category first, tagged recipes before untagged.
struct SwapDinnerSheet: View {
    let dayName: String
    let current: Recipe?
    var onPick: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @State private var picks: [Recipe] = []
    @State private var category: PlanCategory?
    @State private var didLoad = false
    /// Every main dish he could have instead, for Surprise me.
    @State private var surprisePool: [Recipe] = []
    @State private var surprise: Recipe?
    @State private var surpriseSeen: Set<NSManagedObjectID> = []

    static let limit = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Swap \(dayName.lowercased() == "today" ? "tonight's" : "\(dayName)") dinner")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(HomeQuiet.quiet)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 12)

            if !surprisePool.isEmpty {
                surpriseBlock
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }

            if picks.isEmpty && didLoad {
                Text("No other dinners in your recipes yet.")
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.quiet)
                    .padding(.horizontal, 24)
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(picks, id: \.objectID) { recipe in
                            Button {
                                onPick(recipe)
                                dismiss()
                            } label: {
                                row(recipe)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(HomeQuiet.rule).frame(height: 1).padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgBase)
        .onAppear(perform: load)
    }

    // MARK: - Surprise me

    @ViewBuilder
    private var surpriseBlock: some View {
        if let pick = surprise {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    thumbnail(pick, size: 56)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SURPRISE PICK")
                            .font(.system(size: 10))
                            .tracking(1.2)
                            .foregroundStyle(Color.terra500)
                        Text(name(pick))
                            .font(.system(size: 19, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                            .lineLimit(2)
                        Text(RecipeRecency.madeLine(times: Int(pick.timesCooked), last: pick.lastCookedDate))
                            .font(.system(size: 12))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button {
                        onPick(pick)
                        dismiss()
                    } label: {
                        Text("Use")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.terra500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    if surprisePool.count > 1 {
                        Button(action: drawSurprise) {
                            Text("Another")
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HomeQuiet.cardStroke, lineWidth: 1))
        } else {
            Button(action: drawSurprise) {
                HStack(spacing: 8) {
                    Image(systemName: "dice")
                        .font(.system(size: 14))
                    Text("Surprise me")
                        .font(.system(size: 15, weight: .regular, design: .serif))
                }
                .foregroundStyle(Color.terra600)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.terra500.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    /// One random main, three times as likely when it hasn't been made in the last two weeks.
    /// Another doesn't repeat until every main has been shown.
    private func drawSurprise() {
        var pool = surprisePool.filter { !surpriseSeen.contains($0.objectID) && $0.objectID != surprise?.objectID }
        if pool.isEmpty {
            surpriseSeen = []
            pool = surprisePool.filter { $0.objectID != surprise?.objectID }
        }
        guard !pool.isEmpty else { return }
        let weights = pool.map { RecipeRecency.isRecent($0) ? 1 : 3 }
        var roll = Int.random(in: 0..<weights.reduce(0, +))
        var chosen = pool[0]
        for (recipe, weight) in zip(pool, weights) {
            if roll < weight { chosen = recipe; break }
            roll -= weight
        }
        surpriseSeen.insert(chosen.objectID)
        withAnimation(.easeOut(duration: 0.2)) { surprise = chosen }
    }

    static func surprisePool(_ recipes: [Recipe], excluding current: Recipe?) -> [Recipe] {
        recipes.filter { recipe in
            guard recipe.objectID != current?.objectID else { return false }
            let title = (recipe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return false }
            return PlanWeekCatalog.isDinnerMain(name: title, categories: recipe.categories, tags: recipe.tags, categoryID: "")
                && TagRecipesWizard.currentDishType(recipe) == "Main"
        }
    }

    private func thumbnail(_ recipe: Recipe, size: CGFloat) -> some View {
        Group {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.terra100
                    Image(systemName: "fork.knife")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.terra500)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var subtitle: String {
        let count = "\(picks.count) \(picks.count == 1 ? "pick" : "picks")"
        if let category { return "\(count) · \(category.emoji) \(category.name) first" }
        return "\(count) from your recipes"
    }

    private func row(_ recipe: Recipe) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = recipe.imageData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.terra100
                        Image(systemName: "fork.knife")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.terra500)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(name(recipe))
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineLimit(2)
                if let tag = nightLabel(recipe) {
                    Text(tag)
                        .font(.system(size: 12))
                        .foregroundStyle(HomeQuiet.quiet)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let nights = PlanCategory.recipeNights
        category = current.flatMap { recipe in
            let tags = Set(RecipeLabelFormatting.decodeTags(recipe.tags).map { $0.lowercased() })
            return nights.first { tags.contains($0.name.lowercased()) }
        }
        let all = dataManager.fetchRecipes(sortBy: .favoritesFirst)
        picks = Self.rank(all, category: category, excluding: current)
        surprisePool = Self.surprisePool(all, excluding: current)
    }

    static func rank(_ recipes: [Recipe], category: PlanCategory?, excluding current: Recipe?) -> [Recipe] {
        let nights = PlanCategory.recipeNights
        var ranked: [(recipe: Recipe, score: Int, tagged: Bool)] = []
        for recipe in recipes where recipe.objectID != current?.objectID {
            let title = (recipe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            guard PlanWeekCatalog.isDinnerMain(
                name: title,
                categories: recipe.categories,
                tags: recipe.tags,
                categoryID: category?.id ?? ""
            ) else { continue }
            let score = category.map {
                PlanWeekCatalog.score(
                    name: title,
                    categories: recipe.categories,
                    tags: recipe.tags,
                    minutes: Int(recipe.prepTime) + Int(recipe.cookTime),
                    category: $0
                )
            } ?? 0
            let tags = Set(RecipeLabelFormatting.decodeTags(recipe.tags).map { $0.lowercased() })
            let tagged = nights.contains { tags.contains($0.name.lowercased()) }
            ranked.append((recipe, score, tagged))
        }
        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.tagged != rhs.tagged { return lhs.tagged }
            if let order = RecipeRecency.fresherFirst(lhs.recipe, rhs.recipe, favorites: true) { return order }
            return (lhs.recipe.name ?? "").localizedCaseInsensitiveCompare(rhs.recipe.name ?? "") == .orderedAscending
        }
        return Array(ranked.prefix(limit).map(\.recipe))
    }

    private func name(_ recipe: Recipe) -> String {
        let title = (recipe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Recipe" : title
    }

    private func nightLabel(_ recipe: Recipe) -> String? {
        let tags = Set(RecipeLabelFormatting.decodeTags(recipe.tags).map { $0.lowercased() })
        let names = PlanCategory.recipeNights.filter { tags.contains($0.name.lowercased()) }.map { "\($0.emoji) \($0.name)" }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }
}

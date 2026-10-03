import SwiftUI
import CoreData

struct AddMealSheet: View {
    let dataManager: DataManager
    /// When set, a pick is returned and nothing is written. Plan Week Review uses this so Save stays the confirm.
    var onSelect: ((String, Recipe?) -> Void)? = nil
    /// Home day planning uses the library only. Takeout is typed as a dinner line, not a separate button.
    var showsQuickAdds: Bool = true
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var mealDate: Date
    @State private var searchText: String = ""
    @State private var allRecipes: [Recipe] = []
    @State private var isSaving = false
    @FocusState private var isSearchFocused: Bool
    
    init(date: Date, dataManager: DataManager, showsQuickAdds: Bool = true, onSelect: ((String, Recipe?) -> Void)? = nil) {
        self.dataManager = dataManager
        self.onSelect = onSelect
        self.showsQuickAdds = showsQuickAdds
        self._mealDate = State(initialValue: date)
    }
    
    // Filtered recipes based on search
    private var displayedRecipes: [Recipe] {
        if searchText.isEmpty {
            // Show favorites first, then recent — up to 10
            let sorted = allRecipes.sorted { a, b in
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                return (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
            return Array(sorted.prefix(10))
        } else {
            let query = searchText.lowercased()
            return allRecipes.filter { ($0.name ?? "").lowercased().contains(query) }
        }
    }
    
    private var dateLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(mealDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(mealDate) {
            return "Tomorrow"
        } else {
            let f = DateFormatter()
            f.dateFormat = "EEEE, MMM d"
            return f.string(from: mealDate)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.black.opacity(0.12))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { isSearchFocused = false }
            
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Meal")
                        .font(.system(size: 24, weight: .regular, design: .serif))
                        .foregroundStyle(.black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.terra500)
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.terra500)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isSearchFocused = false }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Search Input — Return key saves immediately
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.terra400)
                        
                        TextField("What's for dinner?", text: $searchText)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(.black)
                            .focused($isSearchFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                quickSave(title: searchText)
                            }
                        
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.gray.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .boldShadow(Color.terra400, size: 3, radius: 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    
                    if showsQuickAdds {
                    HStack(spacing: 10) {
                        quickAddButton(
                            title: "Takeout",
                            icon: "takeoutbag.and.cup.and.straw.fill",
                            bgColor: Color.white,
                            fgColor: HomeQuiet.ink,
                            borderColor: HomeQuiet.buttonStroke
                        ) {
                            quickSave(title: "Take Out")
                        }
                        
                        quickAddButton(
                            title: "Leftovers",
                            icon: "fork.knife",
                            bgColor: Color.white,
                            fgColor: HomeQuiet.ink,
                            borderColor: HomeQuiet.buttonStroke
                        ) {
                            quickSave(title: "Leftovers")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    }
                    
                    // Recipe Suggestions
                    if !allRecipes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(searchText.isEmpty ? "FROM YOUR LIBRARY" : "MATCHES")
                                    .font(.system(size: 10, weight: .regular))
                                    .tracking(1.5)
                                    .foregroundStyle(.gray.opacity(0.45))
                                Spacer()
                                if !displayedRecipes.isEmpty {
                                    Text("\(displayedRecipes.count) recipe\(displayedRecipes.count == 1 ? "" : "s")")
                                        .font(.system(size: 10, weight: .regular))
                                        .foregroundStyle(Color.terra400)
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(displayedRecipes, id: \.objectID) { recipe in
                                        recipeChip(recipe: recipe)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                    }
                    
                    if !searchText.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "return")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.terra400)
                                .padding(4)
                                .background(Color.terra100)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.terra200, lineWidth: 1)
                                )
                            Text(onSelect == nil
                                 ? "Press return to save \"\(searchText)\""
                                 : "Press return to use \"\(searchText)\"")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.gray.opacity(0.5))
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                    }

                    Color.clear
                        .frame(minHeight: 220)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { isSearchFocused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.bgBase.ignoresSafeArea())
        .onAppear {
            allRecipes = dataManager.fetchRecipes()
            isSearchFocused = true
        }
        .allowsHitTesting(!isSaving)
        .opacity(isSaving ? 0.6 : 1.0)
    }
    
    // MARK: - Subviews
    
    private func quickAddButton(
        title: String,
        icon: String,
        bgColor: Color,
        fgColor: Color,
        borderColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(fgColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .boldShadowSm(borderColor, radius: 12)
        }
        .buttonStyle(.plain)
    }
    
    private func recipeChip(recipe: Recipe) -> some View {
        Button(action: {
            quickSave(title: recipe.name ?? "Recipe", recipe: recipe)
        }) {
            HStack(spacing: 8) {
                // Thumbnail
                ZStack {
                    if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.98, green: 0.96, blue: 0.94))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "fork.knife")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(HomeQuiet.quiet)
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name ?? "Untitled")
                        .font(.system(size: 12, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(.black)
                    
                    if recipe.isFavorite {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                            Text("Favorite")
                                .font(.system(size: 9, weight: .regular))
                        }
                        .foregroundStyle(Color.peach500)
                    } else if recipe.prepTime + recipe.cookTime > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                            Text("\(recipe.prepTime + recipe.cookTime) min")
                                .font(.system(size: 9, weight: .regular))
                        }
                        .foregroundStyle(Color.terra400)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .boldShadowSm(.black, radius: 12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Actions
    
    private func quickSave(title: String, recipe: Recipe? = nil) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !isSaving else { return }
        isSaving = true
        
        let finalTitle = title.trimmingCharacters(in: .whitespaces)

        if let onSelect {
            onSelect(finalTitle, recipe)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
            return
        }
        
        // Build ingredients from recipe if available
        var ingredientString: String? = nil
        if let recipe = recipe {
            let recipeIngredients = dataManager.sortedIngredients(for: recipe)
            let items = recipeIngredients.map { ing in
                let name = ing.name ?? ""
                let amount = ing.amount
                let unit = ing.unit ?? ""
                let text = CookingAmount.line(amount: amount, unit: unit, name: name, notes: ing.notes ?? "")
                return "0|\(text)"
            }
            if !items.isEmpty {
                ingredientString = items.joined(separator: "\n")
            }
        }
        
        _ = dataManager.createMealPlan(
            title: finalTitle,
            date: mealDate,
            mealType: "Dinner",
            notes: nil,
            ingredients: ingredientString,
            recipe: recipe
        )
        
        // Brief haptic + dismiss
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        dismiss()
    }
}

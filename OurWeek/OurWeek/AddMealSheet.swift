import SwiftUI
import CoreData

struct AddMealSheet: View {
    let dataManager: DataManager
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var mealDate: Date
    @State private var searchText: String = ""
    @State private var allRecipes: [Recipe] = []
    @State private var isSaving = false
    @FocusState private var isSearchFocused: Bool
    
    init(date: Date, dataManager: DataManager) {
        self.dataManager = dataManager
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
            
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add a Meal")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.terra500)
                        Text(dateLabel)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.terra500)
                            .textCase(.uppercase)
                            .tracking(0.5)
                    }
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                        .background(Circle().fill(.black).offset(x: 2, y: 2))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            
            // Search Input — Return key saves immediately
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.terra400)
                
                TextField("What's for dinner?", text: $searchText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
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
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2.5))
            .boldShadow(Color.terra400, size: 3, radius: 14)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Quick-Add Buttons
            HStack(spacing: 10) {
                quickAddButton(
                    title: "Takeout",
                    icon: "takeoutbag.and.cup.and.straw.fill",
                    bgColor: Color.lilac100,
                    fgColor: Color.lilac600,
                    borderColor: Color.lilac400
                ) {
                    quickSave(title: "Take Out")
                }
                
                quickAddButton(
                    title: "Leftovers",
                    icon: "fork.knife",
                    bgColor: Color.sky100,
                    fgColor: Color.sky500,
                    borderColor: Color.sky400
                ) {
                    quickSave(title: "Leftovers")
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            
            // Recipe Suggestions
            if !allRecipes.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(searchText.isEmpty ? "FROM YOUR LIBRARY" : "MATCHES")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundStyle(.gray.opacity(0.45))
                        Spacer()
                        if !displayedRecipes.isEmpty {
                            Text("\(displayedRecipes.count) recipe\(displayedRecipes.count == 1 ? "" : "s")")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
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
            
            Spacer()
            
            // Hint text at bottom
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
                    Text("Press return to save \"\(searchText)\"")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .padding(.bottom, 20)
            }
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
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
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
                    .stroke(Color.black, lineWidth: 2)
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
                            .fill(
                                LinearGradient(
                                    colors: [Color.terra100, Color.terra200],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text("🍽️")
                                    .font(.system(size: 16))
                            )
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recipe.name ?? "Untitled")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.black)
                    
                    if recipe.isFavorite {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                            Text("Favorite")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.peach500)
                    } else if recipe.prepTime + recipe.cookTime > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 8))
                            Text("\(recipe.prepTime + recipe.cookTime) min")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
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
                    .stroke(Color.black, lineWidth: 2)
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
        
        // Build ingredients from recipe if available
        var ingredientString: String? = nil
        if let recipe = recipe {
            let recipeIngredients = dataManager.sortedIngredients(for: recipe)
            let items = recipeIngredients.map { ing in
                let name = ing.name ?? ""
                let amount = ing.amount
                let unit = ing.unit ?? ""
                var text = name
                if amount > 0 {
                    let formatter = NumberFormatter()
                    formatter.minimumFractionDigits = 0
                    formatter.maximumFractionDigits = 2
                    let amtStr = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
                    text = "\(amtStr) \(unit) \(name)".trimmingCharacters(in: .whitespaces)
                }
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

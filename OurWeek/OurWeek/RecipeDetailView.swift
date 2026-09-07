import SwiftUI

// MARK: - Recipe Detail View

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager

    @State private var selectedTab = 0
    @State private var showEditSheet = false
    @State private var showDeleteConfirm = false
    @State private var adjustedServings: Int = 1
    @State private var checkedIngredients: Set<UUID> = []
    @State private var checkedSteps: Set<UUID> = []
    @State private var editableNotes: String = ""
    @State private var currentRating: Int = 0
    
    // AI Generation State
    @State private var isGeneratingImage = false
    @State private var imageStyle: ImageStyle = .realistic
    @State private var generationError: String?
    @State private var hasAIKey = KeychainManager.hasGeminiAPIKey()

    private var totalTime: Int16 { recipe.prepTime + recipe.cookTime }
    private var servingMultiplier: Double {
        recipe.servings > 0 ? Double(adjustedServings) / Double(recipe.servings) : 1.0
    }

    private var ingredients: [RecipeIngredient] {
        dataManager.sortedIngredients(for: recipe)
    }

    private var instructions: [RecipeInstruction] {
        dataManager.sortedInstructions(for: recipe)
    }

    private var randomEmoji: String {
        let hash = abs((recipe.name ?? "").hashValue)
        return RecipeConstants.foodEmojis[hash % RecipeConstants.foodEmojis.count]
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                // Hero Image
                heroImage

                // Info Section
                VStack(alignment: .leading, spacing: 20) {
                    // Title and actions
                    titleSection

                    // Info pills
                    infoPills

                    // Description
                    if let desc = recipe.recipeDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 24)
                    }

                    // Source attribution (for imported recipes)
                    if let sourceURL = recipe.sourceURL, !sourceURL.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.terra500)

                            Text("Imported from \(recipe.sourceDomain ?? "website")")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.gray)

                            Spacer()

                            if let url = URL(string: sourceURL) {
                                Link(destination: url) {
                                    HStack(spacing: 4) {
                                        Text("View")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9, weight: .bold))
                                    }
                                    .foregroundStyle(Color.terra500)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.terra100)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.terra100.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.terra200, lineWidth: 1))
                        .padding(.horizontal, 24)
                    }

                    // Tab picker
                    Picker("Section", selection: $selectedTab) {
                        Text("Ingredients").tag(0)
                        Text("Instructions").tag(1)
                        Text("Notes").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 24)

                    // Tab content
                    switch selectedTab {
                    case 0: ingredientsTab
                    case 1: instructionsTab
                    case 2: notesTab
                    default: EmptyView()
                    }

                    // Action buttons
                    actionButtons
                        .padding(.horizontal, 24)

                    Spacer().frame(height: 40)
                }
            }
        }
        .background(Color.bgBase)
        .overlay(alignment: .topLeading) {
            // Back button
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 16)
        }
        .sheet(isPresented: $showEditSheet, onDismiss: {
            // Refresh state
            adjustedServings = max(1, Int(recipe.servings))
            editableNotes = recipe.notes ?? ""
            currentRating = Int(recipe.rating)
        }) {
            AddRecipeView(recipe: recipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                dataManager.deleteRecipe(recipe)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recipe will be permanently deleted.")
        }
        .onAppear {
            adjustedServings = max(1, Int(recipe.servings))
            editableNotes = recipe.notes ?? ""
            currentRating = Int(recipe.rating)
            hasAIKey = KeychainManager.hasGeminiAPIKey()
        }
        .alert("AI Error", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(generationError ?? "Unknown error occurred.")
        }
    }

    // MARK: - Hero Image

    private var heroImage: some View {
        ZStack(alignment: .bottomTrailing) {
            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 280)
                    .clipped()
                    .overlay(
                        LinearGradient(
                            colors: [.clear, Color.bgBase.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    colors: [Color.terra200, Color.terra300, Color.peach500.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 280)
                .overlay(
                    VStack(spacing: 12) {
                        Text(randomEmoji)
                            .font(.system(size: 64))
                            .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                            
                        if hasAIKey {
                            generateImageButton
                        } else {
                            Text("No photo yet")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.terra600)
                        }
                    }
                )
            }
            
            // Generate/Regenerate AI Image Menu
            if hasAIKey && recipe.imageData != nil {
                Menu {
                    Picker("Style", selection: $imageStyle) {
                        ForEach(ImageStyle.allCases) { style in
                            Label(style.rawValue, systemImage: style.icon).tag(style)
                        }
                    }
                    Button(action: generateAIPhoto) {
                        Label("Regenerate AI Photo", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.terra500)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
                }
                .padding(16)
                .disabled(isGeneratingImage)
            }
        }
    }
    
    private var generateImageButton: some View {
        VStack(spacing: 8) {
            if isGeneratingImage {
                ProgressView()
                    .tint(Color.terra600)
                    .scaleEffect(1.2)
                Text("Creating magic...")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.terra600)
            } else {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Style", selection: $imageStyle) {
                            ForEach(ImageStyle.allCases) { style in
                                Label(style.rawValue, systemImage: style.icon).tag(style)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: imageStyle.icon)
                            Text(imageStyle.rawValue)
                        }
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.5))
                        .clipShape(Capsule())
                    }
                    .tint(Color.terra600)
                    
                    Button(action: generateAIPhoto) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("Generate AI Photo")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.terra600, lineWidth: 1.5))
                        .shadow(color: Color.terra500.opacity(0.3), radius: 5, y: 3)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    private func generateAIPhoto() {
        guard !isGeneratingImage else { return }
        isGeneratingImage = true
        generationError = nil
        
        // Use custom property instead of dictionary directly
        let ingredientsList = ingredients.map { "\($0.amount) \($0.unit ?? "") \($0.name ?? "")" }
        
        Task {
            do {
                let image = try await GeminiService.shared.generateRecipeImage(
                    recipeName: recipe.name ?? "Unknown Recipe",
                    description: recipe.notes ?? "",
                    ingredients: ingredientsList,
                    style: imageStyle
                )
                
                await MainActor.run {
                    if let imageData = image.jpegData(compressionQuality: 0.8) {
                        dataManager.updateRecipeImage(recipe: recipe, newImageData: imageData)
                    }
                    isGeneratingImage = false
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGeneratingImage = false
                }
            }
        }
    }

    // MARK: - Title Section

    private var titleSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                // Categories
                if let cats = recipe.categories, !cats.isEmpty {
                    Text(cats.uppercased())
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Color.terra500)
                }

                Text(recipe.name ?? "Untitled")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
            }

            Spacer()

            // Favorite button
            Button(action: { dataManager.toggleRecipeFavorite(recipe) }) {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .frame(width: 40, height: 40)
                        .offset(x: 2, y: 2)

                    Circle()
                        .fill(recipe.isFavorite ? Color.terra500 : Color.cardWhite)
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))

                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(recipe.isFavorite ? .white : .gray)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Info Pills

    private var infoPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if totalTime > 0 {
                    infoPill(icon: "clock", text: "\(totalTime) min", color: Color.terra500)
                }
                if recipe.servings > 0 {
                    infoPill(icon: "person.2", text: "\(recipe.servings) servings", color: Color.lilac500)
                }
                if let diff = recipe.difficulty, !diff.isEmpty {
                    infoPill(icon: "chart.bar", text: diff, color: Color.lime500)
                }
                if recipe.rating > 0 {
                    infoPill(icon: "star.fill", text: "\(recipe.rating)/5", color: Color(red: 1.0, green: 0.8, blue: 0.0))
                }
            }
            .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private func infoPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1.5))
    }

    // MARK: - Ingredients Tab

    private var ingredientsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Serving adjuster
            HStack {
                Text("ADJUST SERVINGS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray)

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { if adjustedServings > 1 { adjustedServings -= 1 } }) {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.terra500)
                            .frame(width: 28, height: 28)
                            .background(Color.terra100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.terra200, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text("\(adjustedServings)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .frame(minWidth: 24)

                    Button(action: { adjustedServings += 1 }) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.terra500)
                            .frame(width: 28, height: 28)
                            .background(Color.terra100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.terra200, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            // Ingredient list
            VStack(spacing: 0) {
                ForEach(ingredients, id: \.objectID) { ing in
                    let isChecked = checkedIngredients.contains(ing.id ?? UUID())
                    Button(action: {
                        if let id = ing.id {
                            if checkedIngredients.contains(id) {
                                checkedIngredients.remove(id)
                            } else {
                                checkedIngredients.insert(id)
                            }
                        }
                    }) {
                        HStack(spacing: 12) {
                            // Checkbox
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(isChecked ? Color.terra500 : Color.white)
                                    .frame(width: 22, height: 22)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isChecked ? Color.terra600 : Color.gray.opacity(0.3), lineWidth: 1.5))

                                if isChecked {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }

                            // Amount + unit
                            if ing.amount > 0 {
                                let scaledAmount = ing.amount * servingMultiplier
                                Text("\(formatScaledAmount(scaledAmount)) \(ing.unit ?? "")")
                                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                                    .foregroundStyle(isChecked ? .gray : Color.terra500)
                            }

                            Text(ing.name ?? "")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isChecked ? .gray : .black)
                                .strikethrough(isChecked, color: .gray)

                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)

                    if ing != ingredients.last {
                        Divider().padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
            .boldShadow(Color.black, size: 3, radius: 16)
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Instructions Tab

    private var instructionsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(instructions, id: \.objectID) { step in
                let isChecked = checkedSteps.contains(step.id ?? UUID())

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if let id = step.id {
                            if checkedSteps.contains(id) {
                                checkedSteps.remove(id)
                            } else {
                                checkedSteps.insert(id)
                            }
                        }
                    }
                }) {
                    HStack(alignment: .top, spacing: 14) {
                        // Step number
                        ZStack {
                            Circle()
                                .fill(isChecked ? Color.lime500 : Color.lilac500)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.black, lineWidth: 2))

                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(step.stepNumber)")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.text ?? "")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(isChecked ? .gray : .black)
                                .strikethrough(isChecked, color: .gray)
                                .multilineTextAlignment(.leading)

                            if step.timerSeconds > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 10, weight: .bold))
                                    Text("\(step.timerSeconds / 60) min")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(Color.terra400)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.terra100)
                                .clipShape(Capsule())
                            }
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(Color.black, size: 2, radius: 14)
                .opacity(isChecked ? 0.7 : 1.0)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Notes Tab

    private var notesTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Rating
            VStack(alignment: .leading, spacing: 8) {
                Text("RATING")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray)

                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { star in
                        Button(action: {
                            currentRating = star
                            dataManager.updateRecipeRating(recipe, rating: Int16(star))
                        }) {
                            Image(systemName: star <= currentRating ? "star.fill" : "star")
                                .font(.system(size: 24))
                                .foregroundStyle(star <= currentRating ? Color(red: 1.0, green: 0.8, blue: 0.0) : .gray.opacity(0.3))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Stats
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("\(recipe.timesCooked)")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.terra500)
                    Text("Times Cooked")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.terra200, lineWidth: 1.5))

                if let lastCooked = recipe.lastCookedDate {
                    VStack(spacing: 4) {
                        Text(lastCooked, style: .date)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.terra500)
                        Text("Last Cooked")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.terra200, lineWidth: 1.5))
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("PERSONAL NOTES")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray)

                Text(editableNotes.isEmpty ? "No notes yet" : editableNotes)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(editableNotes.isEmpty ? .gray.opacity(0.5) : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.2), lineWidth: 1.5))
            }

            // Tags
            if let tags = recipe.tags, !tags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("TAGS")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray)

                    FlowLayout(spacing: 6) {
                        ForEach(tags.components(separatedBy: ","), id: \.self) { tag in
                            Text(tag.trimmingCharacters(in: .whitespaces))
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.sky500)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.sky100)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(Color.sky200, lineWidth: 1))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Edit button
            Button(action: { showEditSheet = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .bold))
                    Text("EDIT RECIPE")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.terra400, Color.peach500],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                .shadow(color: Color.terra500.opacity(0.3), radius: 6, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            // Mark as cooked
            Button(action: { dataManager.incrementTimesCooked(recipe) }) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 16, weight: .bold))
                    Text("MARK AS COOKED")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(Color.lime500)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.lime100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.lime400, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: { showDeleteConfirm = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .bold))
                    Text("DELETE")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.red.opacity(0.08))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.red.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func formatScaledAmount(_ amount: Double) -> String {
        if amount == floor(amount) {
            return "\(Int(amount))"
        }
        return String(format: "%.1f", amount)
    }
}

import SwiftUI

// MARK: - Import Preview View

struct ImportPreviewView: View {
    let scrapedRecipe: ScrapedRecipe
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager

    // Editable fields
    @State private var recipeName: String = ""
    @State private var recipeDescription: String = ""
    @State private var prepTime: Int = 0
    @State private var cookTime: Int = 0
    @State private var servings: Int = 1
    @State private var difficulty: String = ""
    @State private var selectedCategories: Set<String> = []
    @State private var tagsText: String = ""
    @State private var notes: String = ""
    @State private var selectedImageData: Data? = nil

    // Ingredients and Instructions
    @State private var ingredientRows: [AddRecipeView.IngredientRow] = []
    @State private var instructionRows: [AddRecipeView.InstructionRow] = []

    // State
    @State private var isLoadingImage = false
    @State private var imageDownloadTask: Task<Data?, Never>?
    @State private var showValidationError = false
    @State private var validationMessage = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    // Source attribution
                    sourceAttribution

                    // Basic Info
                    basicInfoSection

                    // Time & Servings
                    timeServingsSection

                    // Ingredients
                    ingredientsSection

                    // Instructions
                    instructionsSection

                    // Categories
                    categoriesSection

                    // Notes
                    notesSection

                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) { saveBar }
        .alert("Missing Info", isPresented: $showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
        .onAppear { populateFromScrapedRecipe() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .background(Circle().fill(.black).offset(x: 2, y: 2))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("REVIEW RECIPE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)

                Text(isPastedSource ? "PASTED · VERIFY DETAILS" : "IMPORTED · VERIFY DETAILS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.terra400)
                    .tracking(1)
            }

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    /// Whether this recipe was pasted as text rather than imported from a URL
    private var isPastedSource: Bool {
        scrapedRecipe.sourceURL.isEmpty || scrapedRecipe.sourceDomain == "Pasted Text"
    }

    // MARK: - Source Attribution

    private var sourceAttribution: some View {
        HStack(spacing: 10) {
            Image(systemName: isPastedSource ? "doc.on.clipboard.fill" : "link.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.terra500)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPastedSource ? "Source" : "Imported from")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.gray)

                Text(isPastedSource ? "Pasted text" : scrapedRecipe.sourceDomain)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.terra600)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.lime500)
        }
        .padding(14)
        .background(Color.terra100.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.terra200, lineWidth: 1.5))
    }

    // MARK: - Basic Info

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("BASIC INFO")

            VStack(alignment: .leading, spacing: 6) {
                Text("Recipe Name *")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                HStack {
                    TextField("Recipe name", text: $recipeName)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(.black, size: 3, radius: 14)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                TextField("Description...", text: $recipeDescription, axis: .vertical)
                    .lineLimit(3...5)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
            }

            // Photo
            VStack(alignment: .leading, spacing: 6) {
                Text("Photo")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                if isLoadingImage {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(Color.terra400)
                        Text("Downloading image...")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .foregroundStyle(Color.terra300)
                    )
                } else if let data = selectedImageData, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Color.terra400)
                        Text("No image found")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                            .foregroundStyle(Color.gray.opacity(0.3))
                    )
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.gray.opacity(0.05)))
                }
            }
        }
    }

    // MARK: - Time & Servings

    private var timeServingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("TIME & SERVINGS")

            HStack(spacing: 12) {
                timeField(label: "Prep", value: $prepTime, icon: "clock")
                timeField(label: "Cook", value: $cookTime, icon: "flame")
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Servings")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)

                    HStack {
                        Button(action: { if servings > 1 { servings -= 1 } }) {
                            Image(systemName: "minus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.terra500)
                                .frame(width: 32, height: 32)
                                .background(Color.terra100)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text("\(servings)")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .frame(minWidth: 32)

                        Button(action: { servings += 1 }) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.terra500)
                                .frame(width: 32, height: 32)
                                .background(Color.terra100)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Difficulty")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)

                    HStack(spacing: 6) {
                        ForEach(RecipeConstants.difficulties, id: \.self) { diff in
                            Button(action: { difficulty = difficulty == diff ? "" : diff }) {
                                Text(diff)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(difficulty == diff ? .white : Color.terra600)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(difficulty == diff ? Color.terra500 : Color.terra100)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(difficulty == diff ? Color.terra600 : Color.terra200, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func timeField(label: String, value: Binding<Int>, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(label) Time (min)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.gray)

            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.terra400)

                TextField("0", value: value, format: .number)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .keyboardType(.numberPad)
                    .frame(width: 60)

                Text("min")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ingredientsSectionHeader
            ingredientsSectionContent
        }
    }

    private var ingredientsSectionHeader: some View {
        HStack {
            sectionLabel("INGREDIENTS *")
            Spacer()
            Text("\(ingredientRows.count) ITEMS")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.lime400)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: 2))
        }
    }

    private var ingredientsSectionContent: some View {
        VStack(spacing: 12) {
            ForEach(Array(ingredientRows.enumerated()), id: \.element.id) { index, _ in
                importIngredientRow(at: index)
            }

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    ingredientRows.append(AddRecipeView.IngredientRow())
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add ingredient")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color.gray.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .foregroundStyle(Color.terra200)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func importIngredientRow(at index: Int) -> some View {
        let deleteAction = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                let _ = self.ingredientRows.remove(at: index)
            }
        }
        ImportIngredientCard(row: $ingredientRows[index], onDelete: deleteAction)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            instructionsSectionHeader
            instructionsSectionContent
        }
    }

    private var instructionsSectionHeader: some View {
        HStack {
            sectionLabel("INSTRUCTIONS *")
            Spacer()
            Text("\(instructionRows.count) STEPS")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.lilac400)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.black, lineWidth: 2))
        }
    }

    private var instructionsSectionContent: some View {
        VStack(spacing: 12) {
            ForEach(Array(instructionRows.enumerated()), id: \.element.id) { index, _ in
                importInstructionRow(at: index)
            }

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    instructionRows.append(AddRecipeView.InstructionRow())
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("Add step")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(Color.gray.opacity(0.6))
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .foregroundStyle(Color.lilac200)
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func importInstructionRow(at index: Int) -> some View {
        let deleteAction = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                let _ = self.instructionRows.remove(at: index)
            }
        }
        ImportInstructionCard(stepNumber: index + 1, row: $instructionRows[index], onDelete: deleteAction)
    }

    // MARK: - Categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CATEGORIES & TAGS")

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                FlowLayout(spacing: 8) {
                    ForEach(RecipeConstants.categories, id: \.self) { cat in
                        Button(action: {
                            if selectedCategories.contains(cat) {
                                selectedCategories.remove(cat)
                            } else {
                                selectedCategories.insert(cat)
                            }
                        }) {
                            HStack(spacing: 4) {
                                Text(RecipeConstants.categoryEmojis[cat] ?? "🍽️")
                                    .font(.system(size: 12))
                                Text(cat)
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(selectedCategories.contains(cat) ? .white : Color.terra600)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategories.contains(cat) ? Color.terra500 : Color.terra100)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(selectedCategories.contains(cat) ? Color.terra600 : Color.terra200, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tags (comma-separated)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                TextField("e.g. quick, family-favorite, healthy", text: $tagsText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOTES")

            TextField("Any personal notes...", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
        }
    }

    // MARK: - Save Bar

    private var saveBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.bgBase.opacity(0), Color.bgBase], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)

            VStack {
                Button(action: saveRecipe) {
                    Text(isSaving ? "SAVING…" : "SAVE RECIPE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: [Color.terra400, Color.peach500],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                        .shadow(color: Color.peach500.opacity(0.4), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.bgBase)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(.gray.opacity(0.6))
    }

    // MARK: - Populate from Scraped Data

    private func populateFromScrapedRecipe() {
        recipeName = scrapedRecipe.title
        recipeDescription = scrapedRecipe.description
        prepTime = scrapedRecipe.prepTimeMinutes
        cookTime = scrapedRecipe.cookTimeMinutes
        servings = max(1, scrapedRecipe.servings)

        // Convert scraped ingredients to rows
        ingredientRows = scrapedRecipe.ingredients.map { ing in
            AddRecipeView.IngredientRow(
                amount: ing.amount > 0 ? formatAmount(ing.amount) : "",
                unit: normalizeToAppUnit(ing.unit),
                name: ing.name,
                notes: ing.notes
            )
        }

        if ingredientRows.isEmpty {
            ingredientRows = [AddRecipeView.IngredientRow()]
        }

        // Convert scraped instructions to rows
        instructionRows = scrapedRecipe.instructions.map { text in
            AddRecipeView.InstructionRow(text: text)
        }

        if instructionRows.isEmpty {
            instructionRows = [AddRecipeView.InstructionRow()]
        }

        // Download image if available (same helper as pack import)
        imageDownloadTask?.cancel()
        imageDownloadTask = nil
        if let imageURL = scrapedRecipe.imageURL, !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isLoadingImage = true
            imageDownloadTask = Task {
                let data = await RecipeScraperService.downloadImage(from: imageURL)
                guard !Task.isCancelled else { return data }
                await MainActor.run {
                    selectedImageData = data
                    isLoadingImage = false
                }
                return data
            }
        }
    }

    private func formatAmount(_ amount: Double) -> String {
        let tolerance = 0.01
        if abs(amount - round(amount)) < tolerance {
            return "\(Int(round(amount)))"
        }
        
        let whole = Int(amount)
        let remainder = amount - Double(whole)
        
        let fractions: [(Double, String)] = [
            (1.0/2.0, "1/2"),
            (1.0/3.0, "1/3"),
            (2.0/3.0, "2/3"),
            (1.0/4.0, "1/4"),
            (3.0/4.0, "3/4"),
            (1.0/8.0, "1/8"),
            (3.0/8.0, "3/8"),
            (5.0/8.0, "5/8"),
            (7.0/8.0, "7/8")
        ]
        
        for (value, string) in fractions {
            if abs(remainder - value) < tolerance {
                if whole > 0 {
                    return "\(whole) \(string)"
                } else {
                    return string
                }
            }
        }
        
        return String(format: "%.2f", amount).replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
    }

    private func normalizeToAppUnit(_ unit: String) -> String {
        // Map scraped units to ones in RecipeConstants.units
        let appUnits = RecipeConstants.units
        let lower = unit.lowercased()
        if appUnits.contains(lower) { return lower }
        // Try common mappings
        switch lower {
        case "tablespoons", "tablespoon", "tbs": return "tbsp"
        case "teaspoons", "teaspoon": return "tsp"
        case "cups": return "cup"
        case "ounces", "ounce": return "oz"
        case "pounds", "pound", "lbs": return "lb"
        case "grams", "gram": return "g"
        case "kilograms", "kilogram": return "kg"
        case "milliliters", "milliliter": return "ml"
        case "liters", "liter": return "L"
        case "packages", "package": return "pkg"
        case "slices": return "slice"
        case "cloves": return "clove"
        case "cans": return "can"
        default: return unit
        }
    }

    // MARK: - Save

    private func saveRecipe() {
        guard !isSaving else { return }
        guard !recipeName.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationMessage = "Recipe name is required"
            showValidationError = true
            return
        }

        let validIngredients = ingredientRows.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validIngredients.isEmpty else {
            validationMessage = "Add at least one ingredient"
            showValidationError = true
            return
        }

        let validInstructions = instructionRows.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !validInstructions.isEmpty else {
            validationMessage = "Add at least one instruction step"
            showValidationError = true
            return
        }

        let ingInputs: [DataManager.IngredientInput] = validIngredients.enumerated().map { index, row in
            DataManager.IngredientInput(
                amount: RecipeScraperService.parseAmount(row.amount),
                unit: row.unit,
                name: row.name,
                notes: row.notes,
                sectionName: "",
                sortOrder: Int16(index)
            )
        }

        let instInputs: [DataManager.InstructionInput] = validInstructions.enumerated().map { index, row in
            DataManager.InstructionInput(
                stepNumber: Int16(index + 1),
                text: row.text,
                timerSeconds: Int32((Int(row.timerMinutes) ?? 0) * 60)
            )
        }

        let categoriesString = selectedCategories.sorted().joined(separator: ", ")

        if isLoadingImage {
            isSaving = true
            Task {
                if let data = await imageDownloadTask?.value {
                    selectedImageData = data
                }
                isLoadingImage = false
                persistRecipe(
                    ingredientInputs: ingInputs,
                    instructionInputs: instInputs,
                    categoriesString: categoriesString
                )
                isSaving = false
            }
            return
        }

        persistRecipe(
            ingredientInputs: ingInputs,
            instructionInputs: instInputs,
            categoriesString: categoriesString
        )
    }

    private func persistRecipe(
        ingredientInputs ingInputs: [DataManager.IngredientInput],
        instructionInputs instInputs: [DataManager.InstructionInput],
        categoriesString: String
    ) {
        _ = dataManager.createRecipe(
            name: recipeName,
            recipeDescription: recipeDescription,
            prepTime: Int16(prepTime),
            cookTime: Int16(cookTime),
            servings: Int16(servings),
            difficulty: difficulty.isEmpty ? nil : difficulty,
            categories: categoriesString.isEmpty ? nil : categoriesString,
            tags: tagsText.isEmpty ? nil : tagsText,
            notes: notes.isEmpty ? nil : notes,
            imageData: selectedImageData,
            sourceURL: isPastedSource ? nil : scrapedRecipe.sourceURL,
            sourceDomain: isPastedSource ? nil : scrapedRecipe.sourceDomain,
            ingredientInputs: ingInputs,
            instructionInputs: instInputs
        )

        dismiss()
    }
}

// MARK: - Import Ingredient Card

private struct ImportIngredientCard: View {
    @Binding var row: AddRecipeView.IngredientRow
    let onDelete: () -> Void

    @FocusState private var isAmountFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Amt", text: $row.amount)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .keyboardType(.decimalPad)
                .focused($isAmountFocused)
                .toolbar {
                    if isAmountFocused {
                        ToolbarItemGroup(placement: .keyboard) {
                            HStack(spacing: 8) {
                                Spacer()
                                Button("/") { row.amount += "/" }
                                Button("¼") { row.amount += "¼" }
                                Button("½") { row.amount += "½" }
                                Button("¾") { row.amount += "¾" }
                                Button("Done") { isAmountFocused = false }.bold()
                            }
                        }
                    }
                }
                .frame(width: 44)

            Menu {
                ForEach(RecipeConstants.units, id: \.self) { unit in
                    Button(unit.isEmpty ? "—" : unit) {
                        row.unit = unit
                    }
                }
            } label: {
                Text(row.unit.isEmpty ? "unit" : row.unit)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(row.unit.isEmpty ? .gray.opacity(0.5) : Color.terra600)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.terra100)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
            }

            TextField("Ingredient name", text: $row.name)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(Color.black, size: 2, radius: 14)
    }
}

// MARK: - Import Instruction Card

private struct ImportInstructionCard: View {
    let stepNumber: Int
    @Binding var row: AddRecipeView.InstructionRow
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.lilac500)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))

                Text("\(stepNumber)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.top, 2)

            VStack(spacing: 8) {
                TextField("Describe this step...", text: $row.text, axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(Color.black, size: 2, radius: 14)
    }
}

import SwiftUI
import PhotosUI

// MARK: - Add / Edit Recipe View

struct AddRecipeView: View {
    let recipe: Recipe?
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager

    // Basic Info
    @State private var recipeName: String = ""
    @State private var recipeDescription: String = ""
    @State private var selectedImageData: Data? = nil
    @State private var photoItem: PhotosPickerItem? = nil

    // Time & Servings
    @State private var prepTime: Int = 0
    @State private var cookTime: Int = 0
    @State private var servings: Int = 1
    @State private var difficulty: String = ""

    // Ingredients
    @State private var ingredientRows: [IngredientRow] = []

    // Instructions
    @State private var instructionRows: [InstructionRow] = []

    // Categories & Tags
    @State private var selectedCategories: Set<String> = []
    @State private var tagsText: String = ""

    // Notes
    @State private var notes: String = ""

    // UI State
    @State private var showDiscardConfirm = false
    @State private var showValidationError = false
    @State private var validationMessage = ""

    private var isEditing: Bool { recipe != nil }

    struct IngredientRow: Identifiable {
        let id = UUID()
        var amount: String = ""
        var unit: String = ""
        var name: String = ""
        var notes: String = ""
    }

    struct InstructionRow: Identifiable {
        let id = UUID()
        var text: String = ""
        var timerMinutes: String = ""
    }

    private var hasUnsavedChanges: Bool {
        !recipeName.isEmpty || !recipeDescription.isEmpty ||
        !ingredientRows.filter({ !$0.name.isEmpty }).isEmpty ||
        !instructionRows.filter({ !$0.text.isEmpty }).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 32) {
                    basicInfoSection
                    timeServingsSection
                    ingredientsSection
                    instructionsSection
                    categoriesSection
                    notesSection
                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) { saveBar }
        .alert("Discard Changes?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text("You have unsaved changes that will be lost.")
        }
        .alert("Missing Info", isPresented: $showValidationError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
        .onAppear { loadExistingRecipe() }
        .onChange(of: photoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    await MainActor.run { selectedImageData = data }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: {
                if hasUnsavedChanges && !isEditing {
                    showDiscardConfirm = true
                } else {
                    dismiss()
                }
            }) {
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
                Text(isEditing ? "EDIT RECIPE" : "NEW RECIPE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)

                Text("PHASE 1 · MANUAL ENTRY")
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

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("BASIC INFO")

            // Title
            VStack(alignment: .leading, spacing: 6) {
                Text("Recipe Name *")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                HStack {
                    TextField("What are you making?", text: $recipeName)
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

            // Description
            VStack(alignment: .leading, spacing: 6) {
                Text("Description")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                TextField("A short description of this recipe...", text: $recipeDescription, axis: .vertical)
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

                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let data = selectedImageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(Color.terra500)
                                    .background(Circle().fill(.white).padding(4))
                                    .padding(8)
                            }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.terra400)
                            Text("Add a photo")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.terra500)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .foregroundStyle(Color.terra300)
                        )
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.terra100.opacity(0.3)))
                    }
                }
            }
        }
    }

    // MARK: - Time & Servings Section

    private var timeServingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("TIME & SERVINGS")

            HStack(spacing: 12) {
                // Prep Time
                timeField(label: "Prep", value: $prepTime, icon: "clock")
                // Cook Time
                timeField(label: "Cook", value: $cookTime, icon: "flame")
            }

            HStack(spacing: 12) {
                // Servings
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

                // Difficulty
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

    // MARK: - Ingredients Section

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            VStack(spacing: 12) {
                ForEach(Array(ingredientRows.enumerated()), id: \.element.id) { index, _ in
                    ingredientRowView(index: index)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        ingredientRows.append(IngredientRow())
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
    }

    @ViewBuilder
    private func ingredientRowView(index: Int) -> some View {
        let deleteAction = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                let _ = self.ingredientRows.remove(at: index)
            }
        }
        IngredientRowCard(
            row: $ingredientRows[index],
            onDelete: deleteAction
        )
    }
}

// MARK: - Extracted Ingredient Row Card

private struct IngredientRowCard: View {
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

extension AddRecipeView {

    // MARK: - Instructions Section

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
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

            VStack(spacing: 12) {
                ForEach(Array(instructionRows.enumerated()), id: \.element.id) { index, _ in
                    instructionRowView(index: index)
                }

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        instructionRows.append(InstructionRow())
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
    }

    @ViewBuilder
    private func instructionRowView(index: Int) -> some View {
        let deleteAction = {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                let _ = self.instructionRows.remove(at: index)
            }
        }
        InstructionRowCard(
            stepNumber: index + 1,
            row: $instructionRows[index],
            onDelete: deleteAction
        )
    }
}

// MARK: - Extracted Instruction Row Card

private struct InstructionRowCard: View {
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

                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.terra400)
                    TextField("Timer (min)", text: $row.timerMinutes)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .foregroundStyle(.gray)
                }
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

extension AddRecipeView {

    // MARK: - Categories Section

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionLabel("CATEGORIES & TAGS")

            // Categories chips
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

            // Tags
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

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("NOTES")

            TextField("Any personal notes about this recipe...", text: $notes, axis: .vertical)
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
                    Text(isEditing ? "SAVE CHANGES" : "SAVE RECIPE")
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

    // MARK: - Actions

    private func saveRecipe() {
        // Validate
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

        if let recipe = recipe {
            dataManager.updateRecipe(
                recipe,
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
                ingredientInputs: ingInputs,
                instructionInputs: instInputs
            )
        } else {
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
                ingredientInputs: ingInputs,
                instructionInputs: instInputs
            )
        }

        dismiss()
    }

    private func loadExistingRecipe() {
        guard let recipe = recipe else {
            // Start with one empty ingredient and instruction row
            ingredientRows = [IngredientRow()]
            instructionRows = [InstructionRow()]
            return
        }

        recipeName = recipe.name ?? ""
        recipeDescription = recipe.recipeDescription ?? ""
        selectedImageData = recipe.imageData
        prepTime = Int(recipe.prepTime)
        cookTime = Int(recipe.cookTime)
        servings = max(1, Int(recipe.servings))
        difficulty = recipe.difficulty ?? ""
        notes = recipe.notes ?? ""
        tagsText = recipe.tags ?? ""

        if let cats = recipe.categories, !cats.isEmpty {
            selectedCategories = Set(cats.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }

        // Load structured ingredients
        let ings = dataManager.sortedIngredients(for: recipe)
        if ings.isEmpty {
            ingredientRows = [IngredientRow()]
        } else {
            ingredientRows = ings.map { ing in
                IngredientRow(
                    amount: ing.amount > 0 ? formatAmount(ing.amount) : "",
                    unit: ing.unit ?? "",
                    name: ing.name ?? "",
                    notes: ing.notes ?? ""
                )
            }
        }

        // Load structured instructions
        let insts = dataManager.sortedInstructions(for: recipe)
        if insts.isEmpty {
            instructionRows = [InstructionRow()]
        } else {
            instructionRows = insts.map { inst in
                InstructionRow(
                    text: inst.text ?? "",
                    timerMinutes: inst.timerSeconds > 0 ? "\(inst.timerSeconds / 60)" : ""
                )
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
}

// MARK: - Flow Layout (for category chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

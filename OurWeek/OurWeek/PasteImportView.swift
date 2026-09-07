import SwiftUI

// MARK: - Paste Import View

struct PasteImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scrapedRecipe: ScrapedRecipe?

    @State private var recipeText: String = ""
    @State private var isParsing = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    private var canParse: Bool {
        recipeText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // Text Input Section
                    textInputSection

                    // Tips
                    tipsSection

                    // Error State
                    if let error = errorMessage {
                        errorView(error)
                    }

                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) { parseButton }
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
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
                Text("PASTE RECIPE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)

                Text("FROM TEXT")
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

    // MARK: - Text Input Section

    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECIPE TEXT")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.gray.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste recipe text from any source")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $recipeText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.black)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 240, maxHeight: 360)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .onChange(of: recipeText) { _, _ in
                            errorMessage = nil
                        }

                    if recipeText.isEmpty {
                        Text("Paste your recipe here...\n\nExample:\nChicken Stir Fry\n\nServings: 4\nPrep Time: 15 min\nCook Time: 20 min\n\nIngredients:\n2 chicken breasts, diced\n1 tbsp soy sauce\n2 cups vegetables\n\nInstructions:\n1. Heat oil in a wok\n2. Cook chicken until golden\n3. Add vegetables and sauce")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.35))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(.black, size: 3, radius: 14)

                HStack(spacing: 12) {
                    // Paste from clipboard
                    Button(action: pasteFromClipboard) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .bold))
                            Text("Paste from clipboard")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(Color.terra500)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.terra100.opacity(0.5))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    // Clear
                    if !recipeText.isEmpty {
                        Button(action: { recipeText = "" }) {
                            HStack(spacing: 6) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Clear")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Character count
                    Text("\(recipeText.count) chars")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.4))
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Tips Section

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TIPS")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.gray.opacity(0.6))

            VStack(alignment: .leading, spacing: 10) {
                tipRow(icon: "checkmark.circle.fill", color: Color.lime500, text: "Copy recipe text from websites, emails, or messages")
                tipRow(icon: "checkmark.circle.fill", color: Color.lime500, text: "Section headers like \"Ingredients\" and \"Instructions\" help parsing")
                tipRow(icon: "checkmark.circle.fill", color: Color.lime500, text: "Numbered steps are automatically detected")
                tipRow(icon: "info.circle.fill", color: Color.sky500, text: "You can edit everything after parsing")
            }
            .padding(16)
            .background(Color.terra100.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.terra200, lineWidth: 1))
        }
    }

    @ViewBuilder
    private func tipRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(color)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.7))
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Text("Parsing Issue")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(.black, size: 3, radius: 14)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Parse Button

    private var parseButton: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.bgBase.opacity(0), Color.bgBase], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)

            VStack {
                Button(action: parseRecipeText) {
                    Text("PARSE RECIPE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: canParse ? [Color.terra400, Color.peach500] : [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(canParse ? Color.black : Color.gray.opacity(0.3), lineWidth: 2))
                        .shadow(color: canParse ? Color.peach500.opacity(0.4) : .clear, radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(!canParse || isParsing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.bgBase)
        }
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.lime500)
                    .symbolEffect(.bounce, value: showSuccess)

                Text("Recipe Parsed!")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            recipeText = clipboardString
        }
    }

    private func parseRecipeText() {
        guard canParse else { return }
        errorMessage = nil
        isParsing = true

        let text = recipeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = RecipeTextParser.parse(text)

        // Validate that we got something useful
        if parsed.ingredients.isEmpty && parsed.instructions.isEmpty {
            isParsing = false
            errorMessage = "Couldn't identify ingredients or instructions. Try adding section headers like \"Ingredients:\" and \"Instructions:\" to help."
            return
        }

        scrapedRecipe = parsed
        isParsing = false
        showSuccess = true

        // Brief success animation then dismiss
        Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await MainActor.run {
                showSuccess = false
                dismiss()
            }
        }
    }
}

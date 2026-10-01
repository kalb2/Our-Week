import SwiftUI
import CoreData

struct DayPlanTarget: Identifiable {
    let date: Date
    var id: Date { date }
}

/// One dinner line per day, stored on the existing MealPlan so the shared week stays in sync.
enum DayDinnerStore {
    static let starterBlob = [
        "Tacos",
        "Pasta",
        "Soup",
        "Stir fry",
        "Burgers",
        "Sheet pan chicken",
        "Salad night",
        "Breakfast for dinner"
    ].joined(separator: "\n")

    static func dinners(on date: Date, dataManager: DataManager) -> [MealPlan] {
        dataManager.fetchMealPlans(for: date).filter {
            ($0.mealType ?? "dinner").lowercased() == "dinner"
        }
    }

    static func titles(from blob: String) -> [String] {
        blob
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func setDinner(on date: Date, title: String, recipe: Recipe?, dataManager: DataManager) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let day = Calendar.current.startOfDay(for: date)
        let existing = dinners(on: day, dataManager: dataManager)
        let ingredients = recipe.flatMap { ingredientText(for: $0, dataManager: dataManager) }
        if let first = existing.first {
            dataManager.updateMealPlan(
                first,
                title: trimmed,
                mealType: "Dinner",
                notes: nil,
                ingredients: ingredients,
                recipe: recipe
            )
        } else {
            _ = dataManager.createMealPlan(
                title: trimmed,
                date: day,
                mealType: "Dinner",
                notes: nil,
                ingredients: ingredients,
                recipe: recipe
            )
        }
    }

    static func clearDinner(on date: Date, dataManager: DataManager) {
        for meal in dinners(on: date, dataManager: dataManager) {
            dataManager.deleteMealPlan(meal)
        }
    }

    private static func ingredientText(for recipe: Recipe, dataManager: DataManager) -> String? {
        let items = dataManager.sortedIngredients(for: recipe).map { ing in
            let text = CookingAmount.line(
                amount: ing.amount,
                unit: ing.unit ?? "",
                name: ing.name ?? "",
                notes: ing.notes ?? ""
            )
            return "0|\(text)"
        }
        return items.isEmpty ? nil : items.joined(separator: "\n")
    }
}

struct DayDinnerSheet: View {
    let date: Date
    let ideas: [String]
    var onFinished: () -> Void

    @Environment(DataManager.self) private var dataManager

    @State private var line = ""
    @State private var showIdeas = false
    @State private var showRecipes = false
    @State private var finishAfterRecipes = false
    @State private var currentTitle: String?
    @FocusState private var lineFocused: Bool

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(dayTitle)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)

                if let currentTitle, !currentTitle.isEmpty {
                    Text(currentTitle)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.terra600)
                }

                sheetButton("Choose recipe", systemImage: "book.closed.fill") {
                    showRecipes = true
                }

                sheetButton("Pick an idea", systemImage: "lightbulb.fill") {
                    lineFocused = false
                    showIdeas.toggle()
                }

                if showIdeas {
                    ideaChips
                }

                HStack(spacing: 8) {
                    TextField("Dominos, Out, chicken Alfredo", text: $line)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .focused($lineFocused)
                        .submitLabel(.done)
                        .onSubmit { saveLine() }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                        .frame(maxWidth: .infinity)

                    Button(action: saveLine) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(width: 48, height: 48)
                            .background(lineCanSave ? Color.lime100 : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .disabled(!lineCanSave)
                    .accessibilityLabel("Save dinner")
                }
                .boldShadow(.black, size: 3, radius: 14)

                Button(action: leaveBlank) {
                    Text("Leave blank")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .padding(.bottom, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.bgBase.ignoresSafeArea())
        .sheet(isPresented: $showRecipes, onDismiss: {
            if finishAfterRecipes {
                finishAfterRecipes = false
                onFinished()
            }
        }) {
            AddMealSheet(
                date: date,
                dataManager: dataManager,
                showsQuickAdds: false,
                onSelect: { title, recipe in
                    DayDinnerStore.setDinner(on: date, title: title, recipe: recipe, dataManager: dataManager)
                    finishAfterRecipes = true
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.bgBase)
        }
        .onAppear {
            currentTitle = DayDinnerStore.dinners(on: date, dataManager: dataManager).first?.title
        }
    }

    private var ideaChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ideas, id: \.self) { idea in
                    Button {
                        DayDinnerStore.setDinner(on: date, title: idea, recipe: nil, dataManager: dataManager)
                        onFinished()
                    } label: {
                        Text(idea)
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.terra100)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sheetButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .bold))
                Text(title)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                Spacer()
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
            .boldShadow(.black, size: 3, radius: 14)
        }
        .buttonStyle(.plain)
    }

    private var lineCanSave: Bool {
        !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveLine() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lineFocused = false
        DayDinnerStore.setDinner(on: date, title: trimmed, recipe: nil, dataManager: dataManager)
        onFinished()
    }

    private func leaveBlank() {
        DayDinnerStore.clearDinner(on: date, dataManager: dataManager)
        onFinished()
    }
}

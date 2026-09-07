import SwiftUI
import CoreData

// MARK: - Meal Plan Carousel

struct MealPlanCarousel: View {
    @Environment(DataManager.self) private var dataManager
    @State private var weekMeals: [MealPlan] = []
    @State private var selectedMeal: MealPlan?
    @State private var showAddMealSheet = false
    @State private var addingMealDate: Date?
    @State private var viewingRecipe: Recipe?

    private let mealTypes = ["Breakfast", "Lunch", "Dinner", "Snack"]

    // Current week dates (Mon-Sun)
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        guard let monday = calendar.date(byAdding: .day, value: daysToMonday, to: today) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func meals(for date: Date) -> [MealPlan] {
        let calendar = Calendar.current
        return weekMeals.filter { meal in
            guard let mealDate = meal.date else { return false }
            return calendar.isDate(mealDate, inSameDayAs: date)
        }
    }

    private func todayIndex() -> Int {
        let calendar = Calendar.current
        return weekDates.firstIndex { calendar.isDateInToday($0) } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "fork.knife")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.terra500)
                Text("THIS WEEK'S MEALS")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1)
                Spacer()
                Text("\(weekMeals.count) planned")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.5))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 24)

            // Carousel
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(Array(weekDates.enumerated()), id: \.offset) { _, date in
                        MealPlanDayCard(
                            date: date,
                            meals: meals(for: date),
                            onMealTap: { meal in
                                selectedMeal = meal
                            },
                            onRecipeViewTap: { recipe in
                                viewingRecipe = recipe
                            },
                            onAddTap: {
                                addingMealDate = date
                                showAddMealSheet = true
                            },
                            onMealDelete: { meal in
                                dataManager.deleteMealPlan(meal)
                                loadMeals()
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .defaultScrollAnchor(scrollAnchor)
        }
        .onAppear { loadMeals() }
        .sheet(item: $selectedMeal, onDismiss: { loadMeals() }) { meal in
            MealEditSheet(
                meal: meal,
                date: meal.date ?? Date(),
                dataManager: dataManager
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddMealSheet, onDismiss: { loadMeals() }) {
            AddMealSheet(
                date: addingMealDate ?? Date(),
                dataManager: dataManager
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $viewingRecipe) { recipe in
            RecipeDetailView(recipe: recipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var scrollAnchor: UnitPoint {
        let idx = todayIndex()
        let fraction = Double(idx) / max(1.0, Double(weekDates.count - 1))
        return UnitPoint(x: fraction, y: 0.5)
    }

    private func loadMeals() {
        guard let monday = weekDates.first else { return }
        weekMeals = dataManager.fetchWeekMealPlans(from: monday)
    }
}

// MARK: - Day Card

struct MealPlanDayCard: View {
    let date: Date
    let meals: [MealPlan]
    let onMealTap: (MealPlan) -> Void
    var onRecipeViewTap: ((Recipe) -> Void)? = nil
    let onAddTap: () -> Void
    var onMealDelete: ((MealPlan) -> Void)? = nil

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date).uppercased()
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private var monthString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date).uppercased()
    }

    private var accentColor: Color { isToday ? Color.lime500 : Color.terra500 }
    private var lightAccent: Color { isToday ? Color.lime100 : Color.terra100 }
    private var borderColor: Color { isToday ? Color.lime500 : Color.terra500 }
    private var shadowColor: Color { isToday ? Color.lime500 : Color.terra500 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isToday ? "TODAY" : dayString)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(accentColor)
                Text(dateString)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(isToday ? Color(red: 0.30, green: 0.52, blue: 0.15) : .primary)
                Spacer()
                Text(monthString)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.4))
                    .tracking(0.5)
            }
            .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(lightAccent)
                .frame(height: 2)
                .padding(.bottom, 12)

            // Meals list
            if meals.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "takeoutbag.and.cup.and.straw")
                        .font(.system(size: 22))
                        .foregroundStyle(.gray.opacity(0.25))
                    Text("No meals planned")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 8) {
                    ForEach(meals, id: \.objectID) { meal in
                        HStack(spacing: 0) {
                            // Text area — opens recipe if linked, otherwise edit
                            Button(action: {
                                if let recipe = meal.recipe {
                                    onRecipeViewTap?(recipe)
                                } else {
                                    onMealTap(meal)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Text(mealEmoji(for: meal.mealType ?? ""))
                                        .font(.system(size: 12))
                                    Text(meal.title ?? "Untitled")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Color.terra600)
                            }
                            .buttonStyle(.plain)

                            Spacer(minLength: 0)

                            // Pencil — opens add meal sheet to swap/replace
                            Button(action: { onAddTap() }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.terra600.opacity(0.5))
                                    .frame(width: 28, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.leading, 10)
                        .padding(.trailing, 2)
                        .padding(.vertical, 4)
                        .background(Color.terra100)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.terra200, lineWidth: 1)
                        )
                        .contextMenu {
                            if let onDelete = onMealDelete {
                                Button(role: .destructive) {
                                    onDelete(meal)
                                } label: {
                                    Label("Delete Meal", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            // Add button
            Button(action: onAddTap) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add Meal")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(0.5)
                }
                .foregroundStyle(accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [5, 4])
                        )
                        .foregroundStyle(accentColor.opacity(0.4))
                )
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(lightAccent.opacity(0.5))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 220)
        .frame(minHeight: 220)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 2)
        )
        .boldShadow(shadowColor)
    }

    private func mealEmoji(for type: String) -> String {
        switch type.lowercased() {
        case "breakfast": return "🥞"
        case "lunch": return "🥗"
        case "dinner": return "🍝"
        case "snack": return "🍎"
        default: return "🍽️"
        }
    }
}

// MARK: - Meal Edit Sheet

struct MealEditSheet: View {
    let meal: MealPlan?
    let date: Date
    let dataManager: DataManager

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var ingredients: [EditIngredient] = []
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { meal != nil }

    struct EditIngredient: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var isChecked: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 40) {
                    mealNameSection
                    ingredientsSection
                    
                    if isEditing {
                        deleteButton
                    }
                    
                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            bottomSaveBar
        }
        .alert("Delete Meal?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteMeal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This meal will be removed from your plan.")
        }
        .onAppear {
            if let meal = meal {
                title = meal.title ?? ""
                if let ingString = meal.ingredients, !ingString.isEmpty {
                    ingredients = decodeIngredients(ingString)
                }
            } else {
                ingredients = [EditIngredient(text: "", isChecked: false)]
            }
        }
    }
    
    // MARK: - Subviews
    
    private var topBar: some View {
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
                Text(isEditing ? "EDIT MEAL" : "ADD MEAL")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)
                
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.peach500)
                    .textCase(.uppercase)
                    .tracking(1)
            }
            
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }
    
    private var mealNameSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MEAL NAME")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .textCase(.uppercase)
                .tracking(2)
                .foregroundStyle(.gray.opacity(0.6))
                .padding(.leading, 4)
            
            HStack {
                TextField("What are you eating?", text: $title)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                
                Image(systemName: "pencil")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.peach500)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
            .boldShadow(.black)
        }
    }
    
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LIST INGREDIENTS")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)
                
                Spacer()
                
                Text("\(ingredients.count) ITEMS")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.lime400)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 16) {
                ForEach($ingredients) { $ingredient in
                    ingredientRow(for: $ingredient)
                }
                
                Button(action: {
                    ingredients.append(EditIngredient(text: "", isChecked: false))
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                        Text("Add more ingredients")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .foregroundStyle(Color.gray.opacity(0.6))
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                            .foregroundStyle(Color.gray.opacity(0.4))
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func ingredientRow(for ingredient: Binding<EditIngredient>) -> some View {
        HStack(spacing: 16) {
            Button(action: { ingredient.wrappedValue.isChecked.toggle() }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(ingredient.wrappedValue.isChecked ? Color.lilac500 : Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black, lineWidth: 2))
                    
                    if ingredient.wrappedValue.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            TextField("Ingredient", text: ingredient.text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .strikethrough(ingredient.wrappedValue.isChecked, color: .gray)
                .foregroundStyle(ingredient.wrappedValue.isChecked ? .gray : .black)
            
            Spacer()
            
            Button(action: {
                if let idx = ingredients.firstIndex(where: { $0.id == ingredient.wrappedValue.id }) {
                    ingredients.remove(at: idx)
                }
            }) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
        .boldShadow(.black)
    }
    
    private var deleteButton: some View {
        Button(action: { showDeleteConfirm = true }) {
            HStack(spacing: 8) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("DELETE MEAL")
                    .font(.system(size: 16, weight: .black, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.red)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.red.opacity(0.3), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
    
    private var bottomSaveBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.bgBase.opacity(0), Color.bgBase], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
            
            VStack {
                Button(action: saveMeal) {
                    Text("SAVE CHANGES")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .background(LinearGradient(colors: [Color.terra400, Color.peach500], startPoint: .leading, endPoint: .trailing))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                        .shadow(color: Color.peach500.opacity(0.4), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(title.isEmpty)
                .opacity(title.isEmpty ? 0.6 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.bgBase)
        }
    }

    // MARK: - Actions
    
    private func saveMeal() {
        let ingString = encodeIngredients(ingredients)
        if let meal = meal {
            dataManager.updateMealPlan(
                meal,
                title: title,
                mealType: meal.mealType ?? "Dinner",
                notes: meal.notes,
                ingredients: ingString,
                recipe: meal.recipe
            )
        } else {
            _ = dataManager.createMealPlan(
                title: title,
                date: date,
                mealType: "Dinner",
                notes: nil,
                ingredients: ingString,
                recipe: nil
            )
        }
        dismiss()
    }

    private func deleteMeal() {
        if let meal = meal { dataManager.deleteMealPlan(meal) }
        dismiss()
    }
    
    // MARK: - Helpers
    
    private func encodeIngredients(_ ing: [EditIngredient]) -> String {
        let items = ing.filter { !$0.text.isEmpty }.map { "\($0.isChecked ? "1" : "0")|\($0.text)" }
        return items.joined(separator: "\n")
    }
    
    private func decodeIngredients(_ str: String) -> [EditIngredient] {
        return str.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return EditIngredient(text: String(parts[1]), isChecked: parts[0] == "1")
        }
    }
}

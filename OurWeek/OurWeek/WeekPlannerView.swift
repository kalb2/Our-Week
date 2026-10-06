//
//  WeekPlannerView.swift
//  OurWeek
//
//  Swipe keeps or skips a recipe. The day it lands on stays hidden until
//  the summary, which places kept recipes on open days of the week Home
//  is already showing (From today, Every day, or Next 7 days).
//  Days that already have a dinner stay as they are unless a recipe is
//  dropped on that day. Nothing is written until Save.
//

import SwiftUI
import CoreData
import UIKit
import UniformTypeIdentifiers

struct WeekPlannerView: View {
    /// The days Home is listing right now. Not always Monday–Sunday.
    let weekDays: [Date]

    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    private static let plannedMealType = "Dinner"
    private static let dropTypes: [UTType] = [.text, .plainText, .utf8PlainText]

    private struct PlannerDay: Identifiable {
        var date: Date
        var existing: [MealPlan]
        var planned: Recipe?
        var id: Date { date }
    }

    private enum Swipe {
        case keep(NSManagedObjectID)
        case skip(NSManagedObjectID)
    }

    @State private var didLoad = false
    @State private var planDays: [PlannerDay] = []
    @State private var sourceRecipes: [Recipe] = []
    @State private var remaining: [Recipe] = []
    @State private var skipped: [Recipe] = []
    @State private var kept: [Recipe] = []
    @State private var history: [Swipe] = []
    @State private var showSummary = false
    @State private var drag: CGSize = .zero
    @State private var flying = false
    @State private var isSaving = false
    @State private var showDiscard = false
    @State private var dropTarget: Date?

    private var openCount: Int {
        planDays.filter { $0.existing.isEmpty }.count
    }

    private var hasDraft: Bool {
        !kept.isEmpty || planDays.contains { $0.planned != nil }
    }

    private var canFinish: Bool {
        !kept.isEmpty && (openCount == 0 || kept.count < openCount)
    }

    private var placedRecipes: [Recipe] {
        planDays.compactMap(\.planned)
    }

    private var unplaced: [Recipe] {
        let placed = Set(placedRecipes.map(\.objectID))
        return kept.filter { !placed.contains($0.objectID) }
    }

    private var canReshuffle: Bool {
        let recipes = placedRecipes
        return recipes.count >= 2 && reshuffleSlots().count >= 2
    }

    private var canSave: Bool {
        planDays.contains { $0.planned != nil }
    }

    var body: some View {
        ZStack {
            Color.bgBase.ignoresSafeArea()
            if didLoad {
                if showSummary {
                    summary
                } else if sourceRecipes.isEmpty {
                    emptyLibrary
                } else {
                    swiper
                }
            }
            if showDiscard {
                discardPrompt
            }
        }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
    }

    // MARK: - Swipe

    private var swiper: some View {
        VStack(spacing: 0) {
            swipeBar
            GeometryReader { geo in
                let cardWidth = min(geo.size.width - 40, 520)
                let cardHeight = min(geo.size.height - 24, 640)
                ZStack {
                    if remaining.count > 1 {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .stroke(HomeQuiet.cardStroke, lineWidth: 1)
                            )
                            .frame(width: cardWidth, height: cardHeight)
                            .scaleEffect(0.94)
                            .offset(y: 16)
                    }
                    if let recipe = remaining.first {
                        recipeCard(recipe, width: cardWidth, height: cardHeight)
                            .id(recipe.objectID)
                            .offset(drag)
                            .rotationEffect(.degrees(Double(drag.width / 22)))
                            .gesture(swipeGesture)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            swipeControls
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
                .padding(.top, 8)
        }
    }

    private var swipeBar: some View {
        HStack {
            iconButton("xmark", label: "Close", action: requestClose)
            Spacer()
            if canFinish {
                iconButton("checkmark", label: "Done", tint: Color.terra500, action: reveal)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var swipeControls: some View {
        ZStack {
            HStack(spacing: 48) {
                circleButton("xmark", label: "Skip", fill: Color.white, foreground: HomeQuiet.ink) {
                    fly(keep: false)
                }
                circleButton("checkmark", label: "Keep", fill: Color.terra500, foreground: .white) {
                    fly(keep: true)
                }
            }
            HStack {
                if !history.isEmpty {
                    iconButton("arrow.uturn.backward", label: "Undo", action: undo)
                }
                Spacer()
            }
        }
        .frame(height: 76)
    }

    private func recipeCard(_ recipe: Recipe, width: CGFloat, height: CGFloat) -> some View {
        let photo = recipeImage(recipe)
        let wash = drag.width >= 0
            ? Color.terra500.opacity(min(0.22, Double(drag.width) / 700))
            : HomeQuiet.ink.opacity(min(0.16, Double(-drag.width) / 800))
        return VStack(alignment: .leading, spacing: 0) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height * 0.62)
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(displayName(for: recipe))
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta = meta(for: recipe) {
                    Text(meta)
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: photo == nil ? .infinity : nil, alignment: .topLeading)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: height, alignment: .top)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(HomeQuiet.cardStroke, lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(wash)
                .allowsHitTesting(false)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 22, x: 0, y: 10)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !flying else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !flying else { return }
                let travel = value.translation.width
                if travel > 110 {
                    fly(keep: true)
                } else if travel < -110 {
                    fly(keep: false)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        drag = .zero
                    }
                }
            }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 0) {
            swipeBar
            Spacer()
            Text("No recipes to plan")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Spacer()
        }
    }

    // MARK: - Summary

    private var summary: some View {
        VStack(spacing: 0) {
            HStack {
                iconButton("chevron.left", label: "Back", action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        showSummary = false
                    }
                })
                Spacer()
                if canReshuffle {
                    iconButton("shuffle", label: "Reshuffle", action: reshuffle)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(unplaced, id: \.objectID) { recipe in
                        mealRow(title: displayName(for: recipe), photo: recipeImage(recipe), draggable: true, targeted: false)
                            .onDrag { dragItem(recipe) }
                    }
                    ForEach(planDays.indices, id: \.self) { index in
                        dayRow(index)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }

            if canSave {
                Button(action: savePlan) {
                    Text("Save")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .accessibilityLabel("Save")
            }
        }
    }

    private func dayRow(_ index: Int) -> some View {
        let day = planDays[index]
        let planned = day.planned
        let title = rowTitle(day)
        let existingRecipe = day.existing.first?.recipe
        let photo = planned.flatMap { recipeImage($0) } ?? existingRecipe.flatMap { recipeImage($0) }
        let isToday = Calendar.current.isDateInToday(day.date)
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatted(day.date, "EEEE"))
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(isToday ? Color.terra500 : HomeQuiet.ink)
                Text(formatted(day.date, "MMM d"))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            if let title {
                mealLabel(title: title, photo: photo)
            }
            if planned != nil {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background((dropTarget == day.date) ? Color.terra100 : Color.white)
        .clipShape(HomeQuiet.card)
        .overlay(HomeQuiet.card.stroke(HomeQuiet.cardStroke, lineWidth: 1))
        .modifier(DayDrop(planned: planned, dropTypes: Self.dropTypes, isTargeted: dropBinding(for: day.date), drag: { dragItem($0) }, accept: { providers in
            acceptDrop(providers, on: index)
        }))
    }

    private func mealRow(title: String, photo: UIImage?, draggable: Bool, targeted: Bool) -> some View {
        HStack(spacing: 12) {
            mealLabel(title: title, photo: photo)
            Spacer()
            if draggable {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(targeted ? Color.terra100 : Color.white)
        .clipShape(HomeQuiet.card)
        .overlay(HomeQuiet.card.stroke(HomeQuiet.cardStroke, lineWidth: 1))
    }

    private func mealLabel(title: String, photo: UIImage?) -> some View {
        HStack(spacing: 10) {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text(title)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private var discardPrompt: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("Discard this plan?")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 10) {
                    Button {
                        showDiscard = false
                    } label: {
                        Text("Keep planning")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.terra500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        dismiss()
                    } label: {
                        Text("Discard")
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.bgBase)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(HomeQuiet.cardStroke, lineWidth: 1)
            )
            .padding(.horizontal, 28)
        }
    }

    // MARK: - Controls

    private func iconButton(
        _ system: String,
        label: String,
        tint: Color = HomeQuiet.ink,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func circleButton(
        _ system: String,
        label: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 64, height: 64)
                .background(fill)
                .clipShape(Circle())
                .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(flying || remaining.isEmpty)
        .accessibilityLabel(label)
    }

    // MARK: - Swipe actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let calendar = Calendar.current
        let dates = weekDays.map { calendar.startOfDay(for: $0) }
        if let first = dates.first, let last = dates.last {
            let meals = dataManager.fetchMealPlans(from: first, through: last)
            planDays = dates.map { date in
                PlannerDay(date: date, existing: dinners(on: date, from: meals), planned: nil)
            }
        }
        let library = dataManager.fetchRecipes(sortBy: .favoritesFirst)
        sourceRecipes = library.filter {
            RecipePlannerMeals.includes(categories: $0.categories, tags: $0.tags)
        }
        let favorites = sourceRecipes.filter(\.isFavorite).shuffled()
        let others = sourceRecipes.filter { !$0.isFavorite }.shuffled()
        remaining = favorites + others
    }

    private func fly(keep: Bool) {
        guard !flying, remaining.first != nil else { return }
        flying = true
        impact(keep ? .medium : .light)
        withAnimation(.easeIn(duration: 0.22)) {
            drag = CGSize(width: keep ? 720 : -720, height: keep ? -20 : 20)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            finishFly(keep: keep)
        }
    }

    private func finishFly(keep: Bool) {
        var revealNow = false
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            revealNow = keep ? commitKeep() : commitSkip()
            drag = .zero
            flying = false
        }
        if revealNow {
            reveal()
        }
    }

    private func commitKeep() -> Bool {
        guard let recipe = remaining.first else { return false }
        remaining.removeFirst()
        kept.append(recipe)
        history.append(.keep(recipe.objectID))
        return shouldReveal
    }

    private func commitSkip() -> Bool {
        guard let recipe = remaining.first else { return false }
        remaining.removeFirst()
        skipped.append(recipe)
        history.append(.skip(recipe.objectID))
        if remaining.isEmpty, kept.isEmpty, !skipped.isEmpty {
            remaining = skipped
            skipped.removeAll()
            return false
        }
        return shouldReveal
    }

    private var shouldReveal: Bool {
        if openCount > 0, kept.count >= openCount { return true }
        if remaining.isEmpty, !kept.isEmpty { return true }
        return false
    }

    private func undo() {
        guard !flying, let action = history.popLast() else { return }
        switch action {
        case .keep(let id):
            kept.removeAll { $0.objectID == id }
            if let recipe = recipe(id) {
                remaining.insert(recipe, at: 0)
            }
        case .skip(let id):
            if let index = skipped.firstIndex(where: { $0.objectID == id }) {
                let recipe = skipped.remove(at: index)
                remaining.insert(recipe, at: 0)
            } else if let recipe = recipe(id) {
                remaining.removeAll { $0.objectID == id }
                remaining.insert(recipe, at: 0)
            }
        }
        impact(.light)
    }

    private func reveal() {
        guard !showSummary else { return }
        dealNewKeeps()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            showSummary = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Puts kept recipes that do not have a day yet onto open days, in a shuffled order.
    private func dealNewKeeps() {
        let keptIDs = Set(kept.map(\.objectID))
        for index in planDays.indices {
            if let planned = planDays[index].planned, !keptIDs.contains(planned.objectID) {
                planDays[index].planned = nil
            }
        }
        let placed = Set(planDays.compactMap { $0.planned?.objectID })
        var incoming = kept.filter { !placed.contains($0.objectID) }
        incoming.shuffle()
        var openIndexes = planDays.indices.filter { planDays[$0].existing.isEmpty && planDays[$0].planned == nil }
        openIndexes.shuffle()
        for recipe in incoming {
            guard let slot = openIndexes.first else { break }
            openIndexes.removeFirst()
            planDays[slot].planned = recipe
        }
    }

    private func reshuffleSlots() -> [Int] {
        planDays.indices.filter { index in
            planDays[index].planned != nil || planDays[index].existing.isEmpty
        }
    }

    private func reshuffle() {
        var recipes = placedRecipes
        var slots = reshuffleSlots()
        guard recipes.count >= 2, slots.count >= 2 else { return }
        let before = recipes.map(\.objectID)
        recipes.shuffle()
        slots.shuffle()
        if recipes.map(\.objectID) == before {
            recipes = Array(recipes.dropFirst()) + Array(recipes.prefix(1))
        }
        for index in planDays.indices where planDays[index].planned != nil {
            planDays[index].planned = nil
        }
        for (recipe, slot) in zip(recipes, slots) {
            planDays[slot].planned = recipe
        }
        impact(.medium)
    }

    private func requestClose() {
        if hasDraft {
            showDiscard = true
        } else {
            dismiss()
        }
    }

    private func savePlan() {
        guard canSave, !isSaving else { return }
        isSaving = true
        for day in planDays {
            guard let recipe = day.planned else { continue }
            if !day.existing.isEmpty {
                dataManager.deleteMealPlans(day.existing)
            }
            _ = dataManager.createMealPlan(
                title: displayName(for: recipe),
                date: day.date,
                mealType: Self.plannedMealType,
                notes: nil,
                ingredients: ingredientString(for: recipe),
                recipe: recipe
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: - Drag

    private func dragItem(_ recipe: Recipe) -> NSItemProvider {
        NSItemProvider(object: recipe.objectID.uriRepresentation().absoluteString as NSString)
    }

    private func dropBinding(for date: Date) -> Binding<Bool> {
        Binding(
            get: { dropTarget == date },
            set: { targeted in
                if targeted {
                    dropTarget = date
                } else if dropTarget == date {
                    dropTarget = nil
                }
            }
        )
    }

    private func acceptDrop(_ providers: [NSItemProvider], on index: Int) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let uri: String?
            if let text = object as? String {
                uri = text
            } else if let text = object as? NSString {
                uri = text as String
            } else {
                uri = nil
            }
            guard let uri else { return }
            DispatchQueue.main.async {
                place(uri: uri, on: index)
            }
        }
        return true
    }

    /// Moves a kept recipe onto a day. Dropping on a day that already has dinner replaces it.
    private func place(uri: String, on target: Int) {
        guard planDays.indices.contains(target), let recipe = recipe(uri: uri) else { return }
        guard kept.contains(where: { $0.objectID == recipe.objectID }) else { return }
        let source = planDays.firstIndex { $0.planned?.objectID == recipe.objectID }
        if source == target { return }
        let displaced = planDays[target].planned
        if let source {
            planDays[source].planned = displaced
        }
        planDays[target].planned = recipe
        impact(.light)
    }

    // MARK: - Helpers

    private func dinners(on date: Date, from meals: [MealPlan]) -> [MealPlan] {
        let calendar = Calendar.current
        return meals.filter { meal in
            guard let mealDate = meal.date, calendar.isDate(mealDate, inSameDayAs: date) else { return false }
            return (meal.mealType ?? "dinner").lowercased() == "dinner"
        }
    }

    private func recipe(_ id: NSManagedObjectID) -> Recipe? {
        sourceRecipes.first { $0.objectID == id }
    }

    private func recipe(uri: String) -> Recipe? {
        let cleaned = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        return sourceRecipes.first { $0.objectID.uriRepresentation().absoluteString == cleaned }
    }

    private func rowTitle(_ day: PlannerDay) -> String? {
        if let recipe = day.planned {
            return displayName(for: recipe)
        }
        guard let meal = day.existing.first else { return nil }
        let title = meal.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Dinner" : title
    }

    private func recipeImage(_ recipe: Recipe) -> UIImage? {
        guard let data = recipe.imageData else { return nil }
        return UIImage(data: data)
    }

    private func meta(for recipe: Recipe) -> String? {
        var bits: [String] = []
        let minutes = Int(recipe.prepTime) + Int(recipe.cookTime)
        if minutes > 0 {
            bits.append("\(minutes) min")
        }
        if recipe.servings > 0 {
            bits.append("\(recipe.servings) servings")
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private func displayName(for recipe: Recipe) -> String {
        let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Recipe" : name
    }

    private func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// Same `0|text` lines AddMealSheet writes, so shopping sync can read them.
    private func ingredientString(for recipe: Recipe) -> String? {
        let items = dataManager.sortedIngredients(for: recipe).map { ingredient -> String in
            let text = CookingAmount.line(
                amount: ingredient.amount,
                unit: ingredient.unit ?? "",
                name: ingredient.name ?? "",
                notes: ingredient.notes ?? ""
            )
            return "0|\(text)"
        }
        guard !items.isEmpty else { return nil }
        return items.joined(separator: "\n")
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

private struct DayDrop: ViewModifier {
    let planned: Recipe?
    let dropTypes: [UTType]
    let isTargeted: Binding<Bool>
    let drag: (Recipe) -> NSItemProvider
    let accept: ([NSItemProvider]) -> Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if let planned {
            content
                .onDrag { drag(planned) }
                .onDrop(of: dropTypes, isTargeted: isTargeted, perform: accept)
        } else {
            content
                .onDrop(of: dropTypes, isTargeted: isTargeted, perform: accept)
        }
    }
}

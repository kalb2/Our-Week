//
//  WeekPlannerView.swift
//  OurWeek
//
//  Swipe planner for the Monday–Sunday week shown on Home.
//  Every new slot is Dinner, matching AddMealSheet.quickSave.
//  Takeout and Leftovers are normal MealPlan rows (titles "Take Out" and
//  "Leftovers", no recipe), matching AddMealSheet, so they show on the
//  week grid and meal carousel.
//  Nothing is written until the review screen confirms.
//  Full week moves forward and opens Review at the end instead of wrapping.
//  This day keeps swipes on the selected day.
//  Randomize, inside this screen, sends each planned meal to a random open day.
//  Surprise me fills the open days and opens Review. Nothing is chosen on Home.
//  Review shows each dinner's photo. Change opens Add a Meal. Shuffle stays on Review.
//  A committed swipe flies that recipe off-screen. The next recipe is a new
//  card at rest — the deck does not advance while the card is still moving.
//

import SwiftUI
import Foundation
import CoreData
import UIKit

struct WeekPlannerView: View {
    /// First day of the week to plan. Home passes the Monday already used by `weekDates`.
    let weekStart: Date

    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss

    /// Meal type for every slot this flow creates. Kept aligned with AddMealSheet.
    private static let plannedMealType = "Dinner"
    private static let takeoutTitle = "Take Out"
    private static let leftoversTitle = "Leftovers"
    /// Dark brown for labels on the light review cards. terra600 is too faint on terra100.
    private static let reviewInk = Color(red: 0.29, green: 0.17, blue: 0.13)

    private enum PlanScope {
        case week
        case day
    }

    private enum ReviewReason {
        case browsing
        case weekComplete
        case endOfWeek
        case randomized
    }

    private enum WeekSlotPlan {
        case recipe(Recipe)
        case takeout
        case leftovers
        case named(String)

        var title: String {
            switch self {
            case .recipe(let recipe):
                let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? "Recipe" : name
            case .takeout:
                return WeekPlannerView.takeoutTitle
            case .leftovers:
                return WeekPlannerView.leftoversTitle
            case .named(let title):
                return title
            }
        }
    }

    private struct DayReplacement: Identifiable {
        let index: Int
        var id: Int { index }
    }

    @State private var didLoad = false
    @State private var existingMeals: [MealPlan] = []
    @State private var sourceRecipes: [Recipe] = []
    @State private var libraryHasRecipes = false
    @State private var deck: [Recipe] = []
    @State private var deckIndex = 0
    @State private var assignments: [Int: WeekSlotPlan] = [:]
    @State private var currentDayIndex = 0
    @State private var showReview = false
    @State private var dragOffset: CGSize = .zero
    @State private var exitOffset: CGSize = .zero
    @State private var exitingRecipe: Recipe?
    @State private var swipeTicket = 0
    @State private var isResolvingSwipe = false
    @State private var isSaving = false
    @State private var showDiscardAlert = false
    @State private var replacingDay: DayReplacement?
    @State private var planScope: PlanScope = .week
    @State private var randomizeDays = false
    @State private var reviewReason: ReviewReason = .browsing

    private var weekDates: [Date] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: weekStart)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var dayCount: Int { weekDates.count }

    private var currentRecipe: Recipe? {
        guard deck.indices.contains(deckIndex) else { return nil }
        return deck[deckIndex]
    }

    private var upcomingRecipe: Recipe? {
        guard deck.count > 1 else { return nil }
        return deck[(deckIndex + 1) % deck.count]
    }

    private var openCount: Int {
        (0..<dayCount).filter { isOpen($0) }.count
    }

    private var filledCount: Int { dayCount - openCount }

    var body: some View {
        ZStack {
            Group {
                if didLoad {
                    plannerContent
                } else {
                    Color.bgBase
                }
            }
            if showDiscardAlert {
                discardPrompt
            }
        }
        .onAppear(perform: load)
    }

    private var discardPrompt: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Discard this plan?")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Button {
                        showDiscardAlert = false
                    } label: {
                        Text("Keep planning")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.terra500)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                            .boldShadow(Color.black, size: 3, radius: 14)
                    }
                    .buttonStyle(.plain)

                    Button {
                        dismiss()
                    } label: {
                        Text("Discard")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                            .boldShadow(Color.terra200, size: 3, radius: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.bgBase)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black, lineWidth: 2.5))
            .boldShadow(Color.terra500, size: 4, radius: 18)
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.light)
    }

    private var plannerContent: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 10)

            if showReview {
                reviewList
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                saveBar
                    .transition(.opacity)
            } else {
                dayStrip
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)

                planningControls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                dayHeading
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                slotContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if isOpen(currentDayIndex) {
                    decisionBar
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: 560, maxHeight: .infinity)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase.ignoresSafeArea())
        .preferredColorScheme(.light)
        .allowsHitTesting(!isSaving && !isResolvingSwipe)
        .sheet(item: $replacingDay) { day in
            AddMealSheet(
                date: weekDates.indices.contains(day.index) ? weekDates[day.index] : weekStart,
                dataManager: dataManager,
                onSelect: { title, recipe in
                    applyMealChoice(title: title, recipe: recipe, to: day.index)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PLAN WEEK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.terra500)
                Text(weekRangeLabel)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Text(progressLine)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.7))
            }

            Spacer(minLength: 8)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    if showReview {
                        showReview = false
                    } else {
                        reviewReason = .browsing
                        showReview = true
                    }
                }
            } label: {
                Text(showReview ? "PLAN" : "REVIEW")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            Button(action: requestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .background(Circle().fill(.black).offset(x: 2, y: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var progressLine: String {
        let counts = "\(filledCount) filled · \(openCount) open"
        if showReview {
            return counts
        }
        if randomizeDays {
            return "Random day · \(counts)"
        }
        if planScope == .day, weekDates.indices.contains(currentDayIndex) {
            return "\(formatted(weekDates[currentDayIndex], "EEE")) only · \(counts)"
        }
        return "Day \(currentDayIndex + 1) of \(dayCount) · \(counts)"
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "This week" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: first)
        if calendar.component(.month, from: first) == calendar.component(.month, from: last) {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "d"
            return "\(start) – \(dayFormatter.string(from: last))"
        }
        return "\(start) – \(formatter.string(from: last))"
    }

    // MARK: - Day strip

    private var dayStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<dayCount, id: \.self) { index in
                    Capsule()
                        .fill(segmentColor(for: index))
                        .frame(height: 6)
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<dayCount, id: \.self) { index in
                    dayChip(index)
                }
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        if index == currentDayIndex { return Color.terra500 }
        if assignments[index] != nil { return Color.terra300 }
        if existingDinner(on: index) != nil { return Color.lilac400 }
        return Color(red: 0.91, green: 0.86, blue: 0.83)
    }

    private func dayChip(_ index: Int) -> some View {
        let date = weekDates[index]
        let isCurrent = index == currentDayIndex
        let planned = assignments[index] != nil
        let locked = existingDinner(on: index) != nil

        return Button {
            selectDay(index)
        } label: {
            VStack(spacing: 1) {
                Text(formatted(date, "EEE"))
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(isCurrent ? WeekPlannerView.reviewInk : Color(red: 0.35, green: 0.28, blue: 0.25))
                Text(formatted(date, "d"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(chipFill(isCurrent: isCurrent, planned: planned, locked: locked))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isCurrent ? Color.black : Color.black.opacity(0.15), lineWidth: isCurrent ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chipAccessibility(index: index, date: date, planned: planned, locked: locked))
    }

    private func chipFill(isCurrent: Bool, planned: Bool, locked: Bool) -> Color {
        if planned { return Color.terra100 }
        if locked { return Color.lilac100 }
        if isCurrent { return Color.white }
        return Color.bgBase
    }

    private func chipAccessibility(index: Int, date: Date, planned: Bool, locked: Bool) -> String {
        let name = formatted(date, "EEEE")
        if planned { return "\(name), planned in this session" }
        if locked { return "\(name), already has dinner" }
        if index == currentDayIndex {
            if randomizeDays { return "\(name), random open day. The next plan lands here." }
            if planScope == .day { return "\(name), selected. Swipes plan only this day." }
            return "\(name), current day in the week"
        }
        return "\(name), open"
    }

    private var planningControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                modeButton(
                    title: "RANDOMIZE",
                    icon: "shuffle",
                    selected: randomizeDays,
                    fill: randomizeDays ? Color.terra500 : Color.white,
                    foreground: randomizeDays ? .white : .black
                ) {
                    setRandomizeDays(!randomizeDays)
                }
                .accessibilityHint("Each meal you plan goes to a random open day")

                modeButton(
                    title: "SURPRISE ME",
                    icon: "sparkles",
                    selected: false,
                    fill: Color.lilac100,
                    foreground: Color.lilac600
                ) {
                    surpriseMe()
                }
                .disabled(!canSurprise)
                .opacity(canSurprise ? 1 : 0.45)
                .accessibilityHint("Fills open days with shuffled mains and opens Review. Nothing is saved yet.")
            }

            if !randomizeDays {
                HStack(spacing: 8) {
                    scopeButton(title: "THIS DAY", selected: planScope == .day) {
                        planScope = .day
                    }
                    scopeButton(title: "FULL WEEK", selected: planScope == .week) {
                        planScope = .week
                    }
                }
            }
        }
    }

    private func modeButton(
        title: String,
        icon: String,
        selected: Bool,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.4)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.black, lineWidth: selected ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var canSurprise: Bool {
        !sourceRecipes.isEmpty && (0..<dayCount).contains(where: { isOpen($0) })
    }

    private func scopeButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(selected ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(selected ? Color.terra500 : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black, lineWidth: selected ? 2 : 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private var scopeCaption: String {
        if randomizeDays {
            return "Each meal you plan lands on a random open day. Tap a day to choose it yourself."
        }
        if planScope == .day {
            return "Swipes stay on this day. Full week moves you forward again."
        }
        if currentDayIndex >= dayCount - 1 {
            return "Last day. Planning it opens Review — you won’t loop back."
        }
        return "Swipes move through the week. Tap a day to plan just that one."
    }

    private var swipeHint: String {
        if randomizeDays {
            return "Swipe right to plan this random day"
        }
        if planScope == .day {
            return "This day only · right plans it and stays here"
        }
        if currentDayIndex >= dayCount - 1 {
            return "Last day · right plans it, then Review"
        }
        return "Swipe right to plan · left to skip"
    }

    private var plannedDayMessage: String {
        let day = weekDates.indices.contains(currentDayIndex) ? formatted(weekDates[currentDayIndex], "EEEE") : "This day"
        if randomizeDays {
            return "\(day) is set. The next open day is chosen at random."
        }
        if planScope == .day {
            return "\(day) is set. Stay here, pick another day, or review to save."
        }
        return "On the plan for this day. Save from Review when the week looks right."
    }

    private var dayHeading: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(weekDates.indices.contains(currentDayIndex) ? formatted(weekDates[currentDayIndex], "EEEE") : "DAY")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
            Spacer()
            Text("DINNER")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.terra500)
        }
    }

    // MARK: - Slot

    @ViewBuilder
    private var slotContent: some View {
        if let plan = assignments[currentDayIndex] {
            statusCard(
                title: plan.title,
                message: plannedDayMessage,
                icon: iconName(for: plan),
                tint: tint(for: plan),
                iconFill: surface(for: plan),
                actionTitle: "Choose again",
                action: { clearAssignment(at: currentDayIndex) }
            )
        } else if let dinner = existingDinner(on: currentDayIndex) {
            statusCard(
                title: dinner.title ?? "Dinner",
                message: "Dinner is already on this day. Pick another day, or leave it as is.",
                icon: "checkmark.seal.fill",
                tint: Color.lilac500,
                iconFill: Color.lilac100,
                actionTitle: nextOpenIndex(after: currentDayIndex) == nil ? nil : "Next open day",
                action: jumpToNextOpen
            )
        } else {
            deckStack
                .padding(.horizontal, 20)
        }
    }

    private var deckStack: some View {
        ZStack {
            if exitingRecipe == nil, let upcoming = upcomingRecipe {
                recipeCard(upcoming, showStamp: false)
                    .scaleEffect(0.95)
                    .offset(y: 12)
                    .allowsHitTesting(false)
            }

            if exitingRecipe == nil, let recipe = currentRecipe {
                recipeCard(recipe, showStamp: true)
                    .id(cardLayerID("live", recipe))
                    .offset(x: dragOffset.width, y: dragOffset.height)
                    .rotationEffect(.degrees(Double(dragOffset.width / 18)))
                    .gesture(deckDrag)
                    .zIndex(1)
            } else if exitingRecipe == nil {
                emptyDeckCard
            }

            if let recipe = exitingRecipe {
                recipeCard(recipe, showStamp: true)
                    .id(cardLayerID("exit", recipe))
                    .offset(x: exitOffset.width, y: exitOffset.height)
                    .rotationEffect(.degrees(Double(exitOffset.width / 18)))
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Live and exit layers stay distinct even when the next card is the same recipe.
    private func cardLayerID(_ layer: String, _ recipe: Recipe) -> String {
        "\(layer):\(recipe.objectID.uriRepresentation().absoluteString)"
    }

    private func recipeCard(_ recipe: Recipe, showStamp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                recipeImage(recipe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                if showStamp {
                    stampOverlay
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 176)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if recipe.isFavorite {
                        Label("Favorite", systemImage: "heart.fill")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.peach500)
                    }
                    Spacer(minLength: 0)
                    if recipe.prepTime + recipe.cookTime > 0 {
                        Label("\(recipe.prepTime + recipe.cookTime) min", systemImage: "clock")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.terra600)
                    }
                }

                Text(displayName(for: recipe))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)

                Text(swipeHint)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.55))
            }
            .padding(16)
        }
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black, lineWidth: 2.5)
        )
        .boldShadow(Color.terra500, size: 4, radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(displayName(for: recipe))
        .accessibilityHint(swipeHint)
    }

    private func recipeImage(_ recipe: Recipe, emojiSize: CGFloat = 42) -> some View {
        Group {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color.terra100, Color.terra300],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text("🍽️")
                        .font(.system(size: emojiSize))
                )
            }
        }
    }

    private var stampOverlay: some View {
        let width = exitingRecipe == nil ? dragOffset.width : exitOffset.width
        return ZStack {
            if width > 16 {
                stamp("PLAN", color: Color.lime500, rotation: -14)
                    .opacity(min(1, Double(width / 110)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
            }
            if width < -16 {
                stamp("SKIP", color: Color.lilac600, rotation: 14)
                    .opacity(min(1, Double(-width / 110)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(16)
            }
        }
    }

    private func stamp(_ text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .black, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color, lineWidth: 3)
            )
            .rotationEffect(.degrees(rotation))
    }

    private var emptyDeckCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.terra500)
            Text(libraryHasRecipes ? "No mains to swipe" : "No recipes to swipe")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(libraryHasRecipes
                 ? "Mark a recipe Main or Full meal, or Dinner without Side, Dessert, Snack, Appetizer, or Drink. Takeout and leftovers still work."
                 : "Add some in Meals, or mark this day as takeout or leftovers.")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.black, lineWidth: 2.5)
        )
        .boldShadow(Color.terra400, size: 4, radius: 18)
    }

    private func statusCard(
        title: String,
        message: String,
        icon: String,
        tint: Color,
        iconFill: Color,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(iconFill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 1.5))

            Text(title)
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(3)

            Text(message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.7))

            if let actionTitle {
                Button(action: action) {
                    Text(actionTitle.uppercased())
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black, lineWidth: 2.5))
        .boldShadow(tint, size: 4, radius: 18)
        .padding(.horizontal, 20)
    }

    // MARK: - Decisions

    private var decisionBar: some View {
        VStack(spacing: 10) {
            Text(scopeCaption)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                choiceButton(
                    title: "SKIP",
                    icon: "arrow.left",
                    fill: Color.white,
                    foreground: .black
                ) {
                    fly(accept: false)
                }
                .disabled(currentRecipe == nil || isResolvingSwipe)
                .opacity(currentRecipe == nil ? 0.45 : 1)

                choiceButton(
                    title: "PLAN",
                    icon: "arrow.right",
                    fill: Color.terra500,
                    foreground: .white
                ) {
                    fly(accept: true)
                }
                .disabled(currentRecipe == nil || isResolvingSwipe)
                .opacity(currentRecipe == nil ? 0.45 : 1)
            }

            HStack(spacing: 10) {
                specialButton(
                    title: "TAKEOUT",
                    subtitle: "Eat out",
                    icon: "takeoutbag.and.cup.and.straw.fill",
                    fill: Color.lilac100,
                    foreground: Color.lilac600
                ) {
                    assign(.takeout)
                }

                specialButton(
                    title: "LEFTOVERS",
                    subtitle: "No recipe",
                    icon: "fork.knife",
                    fill: Color.sky100,
                    foreground: Color.sky500
                ) {
                    assign(.leftovers)
                }
            }
        }
    }

    private func choiceButton(
        title: String,
        icon: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(0.6)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
            .boldShadowSm(.black, radius: 12)
        }
        .buttonStyle(.plain)
    }

    private func specialButton(
        title: String,
        subtitle: String,
        icon: String,
        fill: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.4)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
            .boldShadowSm(foreground.opacity(0.45), radius: 12)
        }
        .buttonStyle(.plain)
        .disabled(isResolvingSwipe)
    }

    private var deckDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !isResolvingSwipe, currentRecipe != nil else { return }
                dragOffset = CGSize(width: value.translation.width, height: value.translation.height * 0.12)
            }
            .onEnded { value in
                guard !isResolvingSwipe else { return }
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.width
                if dx > 110 || (dx > 48 && predicted > 240) {
                    fly(accept: true)
                } else if dx < -110 || (dx < -48 && predicted < -240) {
                    fly(accept: false)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Review

    private var reviewList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(0..<dayCount, id: \.self) { index in
                    reviewRow(index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    private func reviewRow(_ index: Int) -> some View {
        let date = weekDates[index]
        let plan = assignments[index]
        let dinner = existingDinner(on: index)
        let title: String? = {
            if let plan { return plan.title }
            if let dinner { return dinner.title }
            return nil
        }()
        let canEdit = dinner == nil

        return HStack(alignment: .center, spacing: 12) {
            Button {
                guard canEdit else { return }
                replacingDay = DayReplacement(index: index)
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    reviewThumbnail(plan: plan, dinner: dinner)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(formatted(date, "EEE")) \(formatted(date, "d"))")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.black)

                        if let title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title.map { "\(formatted(date, "EEEE")), \($0)" } ?? formatted(date, "EEEE"))
            .accessibilityHint(canEdit ? "Opens meal search for this day" : "This day already has dinner")

            if canEdit || plan != nil {
                VStack(spacing: 6) {
                    if plan != nil {
                        Button {
                            clearAssignment(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 28, height: 28)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(title ?? "dinner")")
                    }

                    if canEdit {
                        Button {
                            replacingDay = DayReplacement(index: index)
                        } label: {
                            Text(plan == nil ? "Choose" : "Change")
                                .font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 5)
                                .background(Color.terra100)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(plan == nil ? "Choose dinner" : "Change dinner")
                    }
                }
            }
        }
        .padding(12)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
        .boldShadow(Color.terra300, size: 3, radius: 16)
    }

    private func reviewThumbnail(plan: WeekSlotPlan?, dinner: MealPlan?) -> some View {
        Group {
            if let recipe = reviewRecipe(plan: plan, dinner: dinner) {
                recipeImage(recipe, emojiSize: 28)
            } else {
                reviewIconTile(plan: plan, dinner: dinner)
            }
        }
        .frame(width: 64, height: 64)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
    }

    private func reviewRecipe(plan: WeekSlotPlan?, dinner: MealPlan?) -> Recipe? {
        if case .recipe(let recipe) = plan { return recipe }
        return dinner?.recipe
    }

    private func reviewIconTile(plan: WeekSlotPlan?, dinner: MealPlan?) -> some View {
        let icon: String
        let fill: Color
        let foreground: Color
        if let plan {
            switch plan {
            case .recipe, .named:
                icon = "fork.knife"
                fill = Color.terra100
                foreground = Color.terra600
            case .takeout:
                icon = "takeoutbag.and.cup.and.straw.fill"
                fill = Color.lilac100
                foreground = Color.lilac600
            case .leftovers:
                icon = "refrigerator.fill"
                fill = Color.sky100
                foreground = Color.sky500
            }
        } else if dinner != nil {
            icon = "fork.knife"
            fill = Color.lilac100
            foreground = Color.lilac600
        } else {
            icon = "plus"
            fill = Color.terra50
            foreground = WeekPlannerView.reviewInk
        }

        return ZStack {
            fill
            Image(systemName: icon)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(foreground)
        }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            Button(action: reshuffleAssignments) {
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 14, weight: .bold))
                    Text("Shuffle")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.black)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(Color.terra200, size: 3, radius: 14)
            }
            .buttonStyle(.plain)
            .disabled(!canReshuffle || isSaving)
            .opacity(canReshuffle ? 1 : 0.4)
            .accessibilityLabel("Shuffle days")
            .accessibilityHint("Reassigns planned recipes across open days. Takeout and leftovers stay put.")

            Button(action: savePlan) {
                Text(assignments.isEmpty ? "Save" : (assignments.count == 1 ? "Save dinner" : "Save dinners"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(assignments.isEmpty ? WeekPlannerView.reviewInk : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(assignments.isEmpty ? Color.terra100 : Color.terra500)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                    .boldShadow(assignments.isEmpty ? Color.terra200 : Color.black, size: 3, radius: 14)
            }
            .buttonStyle(.plain)
            .disabled(assignments.isEmpty || isSaving)
            .accessibilityLabel(assignments.isEmpty ? "Save" : "Save \(assignments.count) dinners")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Color.bgBase)
    }

    // MARK: - Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        existingMeals = dataManager.fetchWeekMealPlans(from: weekStart)
        let library = dataManager.fetchRecipes(sortBy: .favoritesFirst)
        libraryHasRecipes = !library.isEmpty
        sourceRecipes = library.filter {
            RecipePlannerMeals.includes(categories: $0.categories, tags: $0.tags)
        }
        deck = buildDeck(from: sourceRecipes)
        deckIndex = 0
        if let first = firstOpenIndex() {
            currentDayIndex = first
        } else {
            showReview = true
        }
    }

    private func buildDeck(from recipes: [Recipe]) -> [Recipe] {
        let favorites = recipes.filter { $0.isFavorite }.shuffled()
        let others = recipes.filter { !$0.isFavorite }.shuffled()
        return favorites + others
    }

    private func fly(accept: Bool) {
        guard !isResolvingSwipe else { return }
        if accept {
            guard let recipe = currentRecipe else { return }
            beginExit(recipe: recipe, accept: true)
        } else if deck.count < 2 {
            // One recipe left: spring the same card back. Skip does not advance the day.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                dragOffset = .zero
            }
            impact(.light)
        } else if let recipe = currentRecipe {
            beginExit(recipe: recipe, accept: false)
        }
    }

    /// Pins the recipe on its own layer, then animates that layer off-screen.
    /// The deck updates only after the layer has left, so the next card is born at rest.
    private func beginExit(recipe: Recipe, accept: Bool) {
        swipeTicket += 1
        let ticket = swipeTicket
        isResolvingSwipe = true

        var seed = Transaction()
        seed.disablesAnimations = true
        seed.animation = nil
        withTransaction(seed) {
            exitingRecipe = recipe
            exitOffset = dragOffset
            dragOffset = .zero
        }

        let travel = CGSize(width: accept ? 840 : -840, height: accept ? -28 : 28)
        // Let the exit layer render at the finger position before it moves.
        // Animating in this same turn would start from zero and retarget the card.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            guard swipeTicket == ticket else { return }
            withAnimation(.easeIn(duration: 0.26)) {
                exitOffset = travel
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                guard swipeTicket == ticket else { return }
                finishExit(accept: accept)
            }
        }
    }

    private func finishExit(accept: Bool) {
        var accepted = false
        var reset = Transaction()
        reset.disablesAnimations = true
        reset.animation = nil
        withTransaction(reset) {
            if accept {
                accepted = commitAccept()
            } else {
                commitSkip()
            }
            exitingRecipe = nil
            exitOffset = .zero
            dragOffset = .zero
            if accepted {
                advanceAfterSwipe()
            }
        }
        isResolvingSwipe = false
    }

    /// Applies the day change in the same non-animated transaction as the new card.
    /// A spring here would retarget the incoming card and replay the rebound.
    private func advanceAfterSwipe() {
        switch advanceForAssign() {
        case .stay:
            impact(.medium)
        case .day(let next):
            impact(.medium)
            currentDayIndex = next
        case .review(let reason):
            DispatchQueue.main.async {
                presentReview(reason)
            }
        }
    }

    @discardableResult
    private func commitAccept() -> Bool {
        guard isOpen(currentDayIndex) else { return false }
        let recipe = exitingRecipe ?? currentRecipe
        guard let recipe else { return false }
        assignments[currentDayIndex] = .recipe(recipe)
        deck.removeAll { $0.objectID == recipe.objectID }
        if deck.isEmpty {
            deck = buildDeck(from: recipesForRefill())
        }
        if deckIndex >= deck.count {
            deckIndex = 0
        }
        return true
    }

    private func commitSkip() {
        guard !deck.isEmpty else { return }
        deckIndex = (deckIndex + 1) % deck.count
        impact(.light)
    }

    private func assign(_ plan: WeekSlotPlan) {
        guard isOpen(currentDayIndex), !isResolvingSwipe else { return }
        assignments[currentDayIndex] = plan
        moveAfterAssign()
    }

    private func clearAssignment(at index: Int) {
        guard let plan = assignments[index] else { return }
        assignments[index] = nil
        if case .recipe(let recipe) = plan, !deck.contains(where: { $0.objectID == recipe.objectID }) {
            let insertAt = min(deckIndex, deck.count)
            deck.insert(recipe, at: insertAt)
        }
    }

    private func moveAfterAssign() {
        switch advanceForAssign() {
        case .stay:
            impact(.medium)
        case .day(let next):
            impact(.medium)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                currentDayIndex = next
            }
        case .review(let reason):
            presentReview(reason)
        }
    }

    private enum AssignAdvance {
        case stay
        case day(Int)
        case review(ReviewReason)
    }

    /// Randomize picks any other open day. Full week walks forward. This day stays.
    private func advanceForAssign() -> AssignAdvance {
        if randomizeDays {
            if let next = randomOpenIndex() {
                return .day(next)
            }
            return .review(openCount == 0 ? .weekComplete : .endOfWeek)
        }
        if planScope == .day {
            return .stay
        }
        let onLastDay = currentDayIndex >= dayCount - 1
        if !onLastDay, let next = forwardOpenIndex(after: currentDayIndex) {
            return .day(next)
        }
        return .review(openCount == 0 ? .weekComplete : .endOfWeek)
    }

    private func randomOpenIndex() -> Int? {
        (0..<dayCount).filter { isOpen($0) }.randomElement()
    }

    private func setRandomizeDays(_ on: Bool) {
        randomizeDays = on
        guard on, let pick = randomOpenIndex() else { return }
        planScope = .week
        currentDayIndex = pick
    }

    private func surpriseMe() {
        guard !isResolvingSwipe, assignRandomDinners() else { return }
        presentReview(.randomized)
    }

    private func presentReview(_ reason: ReviewReason) {
        reviewReason = reason
        withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
            showReview = true
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func selectDay(_ index: Int) {
        guard weekDates.indices.contains(index) else { return }
        currentDayIndex = index
        planScope = .day
        randomizeDays = false
        reviewReason = .browsing
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showReview = false
        }
    }

    /// Fills open days only. Takeout and leftovers stay manual. Nothing is saved here.
    @discardableResult
    private func assignRandomDinners() -> Bool {
        let targets = (0..<dayCount).filter { isOpen($0) }
        guard !targets.isEmpty, !sourceRecipes.isEmpty else { return false }

        var pool = buildDeck(from: sourceRecipes)
        var cursor = 0
        var placed = 0
        for index in targets {
            if pool.isEmpty || cursor >= pool.count {
                pool = buildDeck(from: sourceRecipes)
                cursor = 0
            }
            guard pool.indices.contains(cursor) else { break }
            assignments[index] = .recipe(pool[cursor])
            cursor += 1
            placed += 1
        }

        deck = buildDeck(from: recipesForRefill())
        deckIndex = 0
        return placed > 0
    }

    private var canReshuffle: Bool {
        sessionRecipes().count >= 1 && reshuffleSlots().count >= 2
    }

    /// Moves planned recipes onto a new mix of those days and any still-open days.
    /// Takeout, leftovers, and dinners already on the calendar stay where they are.
    private func reshuffleAssignments() {
        let recipes = sessionRecipes().shuffled()
        var days = reshuffleSlots().shuffled()
        guard recipes.count >= 1, days.count >= 2 else { return }
        if placementUnchanged(recipes: recipes, days: days), days.count > 1 {
            days = Array(days.dropFirst()) + Array(days.prefix(1))
        }
        for index in days where assignments[index] != nil {
            if case .recipe = assignments[index] {
                assignments[index] = nil
            }
        }
        for (recipe, day) in zip(recipes, days) {
            assignments[day] = .recipe(recipe)
        }
        deck = buildDeck(from: recipesForRefill())
        deckIndex = 0
        impact(.medium)
    }

    private func sessionRecipes() -> [Recipe] {
        (0..<dayCount).compactMap { index in
            if case .recipe(let recipe) = assignments[index] { return recipe }
            return nil
        }
    }

    private func reshuffleSlots() -> [Int] {
        (0..<dayCount).filter { index in
            if case .recipe = assignments[index] { return true }
            return isOpen(index)
        }
    }

    private func placementUnchanged(recipes: [Recipe], days: [Int]) -> Bool {
        for (recipe, day) in zip(recipes, days) {
            if case .recipe(let existing) = assignments[day], existing.objectID == recipe.objectID {
                continue
            }
            return false
        }
        return true
    }

    private func applyMealChoice(title: String, recipe: Recipe?, to index: Int) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let recipe {
            replaceDay(index, with: .recipe(recipe))
        } else if trimmed == Self.takeoutTitle {
            replaceDay(index, with: .takeout)
        } else if trimmed == Self.leftoversTitle {
            replaceDay(index, with: .leftovers)
        } else {
            replaceDay(index, with: .named(trimmed))
        }
    }

    private func replaceDay(_ index: Int, with plan: WeekSlotPlan) {
        guard weekDates.indices.contains(index), existingDinner(on: index) == nil else { return }
        releaseRecipe(at: index)
        assignments[index] = plan
        if case .recipe(let recipe) = plan {
            deck.removeAll { $0.objectID == recipe.objectID }
            if deck.isEmpty {
                deck = buildDeck(from: recipesForRefill())
            }
            if deckIndex >= deck.count {
                deckIndex = 0
            }
        }
        replacingDay = nil
    }

    private func releaseRecipe(at index: Int) {
        guard case .recipe(let recipe) = assignments[index] else { return }
        let usedElsewhere = assignments.contains { day, plan in
            guard day != index, case .recipe(let other) = plan else { return false }
            return other.objectID == recipe.objectID
        }
        if !usedElsewhere, !deck.contains(where: { $0.objectID == recipe.objectID }) {
            deck.insert(recipe, at: min(deckIndex, deck.count))
        }
    }

    private func jumpToNextOpen() {
        guard let next = nextOpenIndex(after: currentDayIndex) ?? firstOpenIndex() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            currentDayIndex = next
        }
    }

    private func requestClose() {
        if assignments.isEmpty {
            dismiss()
        } else {
            showDiscardAlert = true
        }
    }

    private func savePlan() {
        guard !assignments.isEmpty, !isSaving else { return }
        isSaving = true

        for index in assignments.keys.sorted() {
            guard weekDates.indices.contains(index) else { continue }
            let date = weekDates[index]
            switch assignments[index] {
            case .recipe(let recipe):
                _ = dataManager.createMealPlan(
                    title: displayName(for: recipe),
                    date: date,
                    mealType: Self.plannedMealType,
                    notes: nil,
                    ingredients: ingredientString(for: recipe),
                    recipe: recipe
                )
            case .takeout:
                _ = dataManager.createMealPlan(
                    title: Self.takeoutTitle,
                    date: date,
                    mealType: Self.plannedMealType
                )
            case .leftovers:
                _ = dataManager.createMealPlan(
                    title: Self.leftoversTitle,
                    date: date,
                    mealType: Self.plannedMealType
                )
            case .named(let title):
                _ = dataManager.createMealPlan(
                    title: title,
                    date: date,
                    mealType: Self.plannedMealType
                )
            case .none:
                break
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: - Day queries

    private func isOpen(_ index: Int) -> Bool {
        guard weekDates.indices.contains(index) else { return false }
        if assignments[index] != nil { return false }
        return existingDinner(on: index) == nil
    }

    private func existingDinner(on index: Int) -> MealPlan? {
        guard weekDates.indices.contains(index) else { return nil }
        let day = weekDates[index]
        let calendar = Calendar.current
        return existingMeals.first { meal in
            guard let date = meal.date, calendar.isDate(date, inSameDayAs: day) else { return false }
            return (meal.mealType ?? "dinner").lowercased() == "dinner"
        }
    }

    private func firstOpenIndex() -> Int? {
        (0..<dayCount).first(where: { isOpen($0) })
    }

    private func forwardOpenIndex(after index: Int) -> Int? {
        ((index + 1)..<dayCount).first(where: { isOpen($0) })
    }

    private func nextOpenIndex(after index: Int) -> Int? {
        let forward = Array((index + 1)..<dayCount)
        let wrapped = Array(0..<index)
        return (forward + wrapped).first(where: { isOpen($0) })
    }

    private func recipesForRefill() -> [Recipe] {
        var used = Set<NSManagedObjectID>()
        for plan in assignments.values {
            if case .recipe(let recipe) = plan {
                used.insert(recipe.objectID)
            }
        }
        let remaining = sourceRecipes.filter { !used.contains($0.objectID) }
        return remaining.isEmpty ? sourceRecipes : remaining
    }

    // MARK: - Formatting

    private func formatted(_ date: Date, _ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: date).uppercased()
    }

    private func displayName(for recipe: Recipe) -> String {
        let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Recipe" : name
    }

    private func iconName(for plan: WeekSlotPlan) -> String {
        switch plan {
        case .recipe, .named: return "fork.knife"
        case .takeout: return "takeoutbag.and.cup.and.straw.fill"
        case .leftovers: return "refrigerator.fill"
        }
    }

    private func tint(for plan: WeekSlotPlan) -> Color {
        switch plan {
        case .recipe, .named: return Color.terra500
        case .takeout: return Color.lilac500
        case .leftovers: return Color.sky500
        }
    }

    /// Opaque light fills. Translucent tints were blending to dark brown on Review.
    private func surface(for plan: WeekSlotPlan) -> Color {
        switch plan {
        case .recipe, .named: return Color.terra100
        case .takeout: return Color.lilac100
        case .leftovers: return Color.sky100
        }
    }

    /// Same `0|text` lines AddMealSheet writes, so shopping sync can read them.
    private func ingredientString(for recipe: Recipe) -> String? {
        let recipeIngredients = dataManager.sortedIngredients(for: recipe)
        let items = recipeIngredients.map { ingredient -> String in
            let name = ingredient.name ?? ""
            let amount = ingredient.amount
            let unit = ingredient.unit ?? ""
            var text = name
            if amount > 0 {
                text = CookingAmount.line(amount: amount, unit: unit, name: name)
            }
            return "0|\(text)"
        }
        guard !items.isEmpty else { return nil }
        return items.joined(separator: "\n")
    }

    private func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
}

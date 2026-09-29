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
//  This day keeps swipes on the selected day. Randomize fills open days only.
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

        var title: String {
            switch self {
            case .recipe(let recipe):
                let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return name.isEmpty ? "Recipe" : name
            case .takeout:
                return WeekPlannerView.takeoutTitle
            case .leftovers:
                return WeekPlannerView.leftoversTitle
            }
        }
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
    @State private var isResolvingSwipe = false
    @State private var isSaving = false
    @State private var showDiscardAlert = false
    @State private var planScope: PlanScope = .week
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
        Group {
            if didLoad {
                plannerContent
            } else {
                Color.bgBase
            }
        }
        .onAppear(perform: load)
        .alert("Discard this plan?", isPresented: $showDiscardAlert) {
            Button("Keep planning", role: .cancel) {}
            Button("Discard", role: .destructive) { dismiss() }
        } message: {
            Text("Dinners you just picked won't be saved.")
        }
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
        .allowsHitTesting(!isSaving && !isResolvingSwipe)
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
            switch reviewReason {
            case .weekComplete:
                return "Week complete · \(counts)"
            case .endOfWeek:
                return "End of the week · \(counts)"
            case .randomized:
                return "Shuffled · \(counts)"
            case .browsing:
                return "Review · \(counts)"
            }
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
        return Color.black.opacity(0.08)
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
                    .foregroundStyle(isCurrent ? Color.terra600 : .gray)
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
        return Color.white.opacity(0.55)
    }

    private func chipAccessibility(index: Int, date: Date, planned: Bool, locked: Bool) -> String {
        let name = formatted(date, "EEEE")
        if planned { return "\(name), planned in this session" }
        if locked { return "\(name), already has dinner" }
        if index == currentDayIndex {
            if planScope == .day { return "\(name), selected. Swipes plan only this day." }
            return "\(name), current day in the week"
        }
        return "\(name), open"
    }

    private var planningControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                scopeButton(title: "THIS DAY", selected: planScope == .day) {
                    planScope = .day
                }
                scopeButton(title: "FULL WEEK", selected: planScope == .week) {
                    planScope = .week
                }
            }

            Button(action: randomizeWeek) {
                HStack(spacing: 8) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 13, weight: .bold))
                    Text("RANDOMIZE WEEK")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    Text(randomizeDetail)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.lime100)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
                .boldShadowSm(Color.lime500, radius: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canRandomize)
            .opacity(canRandomize ? 1 : 0.45)
            .accessibilityHint("Fills open days with shuffled mains and full meals, then opens Review. Takeout and leftovers are left alone. Nothing is saved yet.")
        }
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

    private var canRandomize: Bool {
        !sourceRecipes.isEmpty && (0..<dayCount).contains(where: { isOpen($0) })
    }

    private var randomizeDetail: String {
        if sourceRecipes.isEmpty { return "Add recipes" }
        if !canRandomize { return "Week is full" }
        return "Mains only"
    }

    private var scopeCaption: String {
        if planScope == .day {
            return "Swipes stay on this day. Full week moves you forward again."
        }
        if currentDayIndex >= dayCount - 1 {
            return "Last day. Planning it opens Review — you won’t loop back."
        }
        return "Swipes move through the week. Tap a day to plan just that one."
    }

    private var swipeHint: String {
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
                actionTitle: "Choose again",
                action: { clearAssignment(at: currentDayIndex) }
            )
        } else if let dinner = existingDinner(on: currentDayIndex) {
            statusCard(
                title: dinner.title ?? "Dinner",
                message: "Dinner is already on this day. Pick another day, or leave it as is.",
                icon: "checkmark.seal.fill",
                tint: Color.lilac500,
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
            if let upcoming = upcomingRecipe {
                recipeCard(upcoming, showStamp: false)
                    .scaleEffect(0.95)
                    .offset(y: 12)
                    .allowsHitTesting(false)
            }

            if let recipe = currentRecipe {
                recipeCard(recipe, showStamp: true)
                    .offset(x: dragOffset.width, y: dragOffset.height)
                    .rotationEffect(.degrees(Double(dragOffset.width / 18)))
                    .gesture(deckDrag)
                    .zIndex(1)
            } else {
                emptyDeckCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func recipeImage(_ recipe: Recipe) -> some View {
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
                        .font(.system(size: 42))
                )
            }
        }
    }

    private var stampOverlay: some View {
        let width = dragOffset.width
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
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.15))
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
                reviewIntro
                    .transition(.move(edge: .top).combined(with: .opacity))

                ForEach(0..<dayCount, id: \.self) { index in
                    reviewRow(index)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var reviewIntro: some View {
        switch reviewReason {
        case .browsing:
            Text("Dinner is saved for each new day. Open days stay empty.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.65))
                .frame(maxWidth: .infinity, alignment: .leading)
        case .weekComplete:
            reviewBanner(
                kicker: "WEEK COMPLETE",
                message: "You're done planning. Review the dinners below, then save.",
                fill: Color.lime100,
                accent: Color.lime500
            )
        case .endOfWeek:
            reviewBanner(
                kicker: currentDayIndex >= dayCount - 1 ? "END OF THE WEEK" : "NO DAYS AFTER THIS",
                message: currentDayIndex >= dayCount - 1
                    ? "That's the last day. Review and save, or jump back to any day you left open. Nothing is saved until you confirm."
                    : "No open days left after this one. Review and save, or jump back to a day you skipped. Nothing is saved until you confirm.",
                fill: Color.terra100,
                accent: Color.terra500
            )
        case .randomized:
            reviewBanner(
                kicker: "WEEK SHUFFLED",
                message: "Open days got a shuffled mix of mains and full meals, favorites first. Takeout and leftovers stay manual. Edit any day, then save.",
                fill: Color.lilac100,
                accent: Color.lilac500
            )
        }
    }

    private func reviewBanner(kicker: String, message: String, fill: Color, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .tracking(1)
                .foregroundStyle(accent)
            Text(message)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(accent, size: 3, radius: 14)
    }

    private func reviewRow(_ index: Int) -> some View {
        let date = weekDates[index]
        let plan = assignments[index]
        let dinner = existingDinner(on: index)
        let title: String = {
            if let plan { return plan.title }
            if let dinner { return dinner.title ?? "Dinner" }
            return "Nothing planned"
        }()
        let subtitle: String = {
            if let plan { return reviewSubtitle(for: plan) }
            if dinner != nil { return "Already on this day" }
            return "Still open"
        }()
        let fill: Color = {
            if let plan { return tint(for: plan).opacity(0.18) }
            if dinner != nil { return Color.lilac100 }
            return Color.white
        }()

        return HStack(spacing: 8) {
            Button {
                selectDay(index)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(formatted(date, "EEE"))
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.terra600)
                        Text(formatted(date, "d"))
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .frame(width: 42, alignment: .leading)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.6))
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

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
                .accessibilityLabel("Remove \(title)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadowSm(.black, radius: 14)
    }

    private func reviewSubtitle(for plan: WeekSlotPlan) -> String {
        switch plan {
        case .recipe:
            return "New dinner · recipe"
        case .takeout:
            return "New dinner · takeout"
        case .leftovers:
            return "New dinner · leftovers"
        }
    }

    private var saveBar: some View {
        VStack(spacing: 8) {
            Button(action: savePlan) {
                Text(assignments.isEmpty ? "NOTHING NEW TO SAVE" : "SAVE \(assignments.count) DINNER\(assignments.count == 1 ? "" : "S")")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(assignments.isEmpty ? Color.gray.opacity(0.45) : Color.terra500)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                    .boldShadow(assignments.isEmpty ? Color.gray.opacity(0.3) : Color.black, size: 3, radius: 14)
            }
            .buttonStyle(.plain)
            .disabled(assignments.isEmpty || isSaving)

            if filledCount == dayCount && assignments.isEmpty {
                Text("Every day already has dinner.")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.6))
            }
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
            guard currentRecipe != nil else { return }
        } else if deck.count < 2 {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                dragOffset = .zero
            }
            impact(.light)
            return
        }

        isResolvingSwipe = true
        let width: CGFloat = accept ? 560 : -560
        withAnimation(.easeIn(duration: 0.18)) {
            dragOffset = CGSize(width: width, height: accept ? -16 : 16)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            var accepted = false
            withTransaction(transaction) {
                if accept {
                    accepted = commitAccept()
                } else {
                    commitSkip()
                }
                dragOffset = .zero
            }
            if accepted {
                moveAfterAssign()
            }
            isResolvingSwipe = false
        }
    }

    @discardableResult
    private func commitAccept() -> Bool {
        guard isOpen(currentDayIndex), let recipe = currentRecipe else { return false }
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
        if planScope == .day {
            impact(.medium)
            return
        }

        let onLastDay = currentDayIndex >= dayCount - 1
        if !onLastDay, let next = forwardOpenIndex(after: currentDayIndex) {
            impact(.medium)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                currentDayIndex = next
            }
            return
        }

        presentReview(openCount == 0 ? .weekComplete : .endOfWeek)
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
        reviewReason = .browsing
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            showReview = false
        }
    }

    private func randomizeWeek() {
        let targets = (0..<dayCount).filter { isOpen($0) }
        guard !targets.isEmpty, !sourceRecipes.isEmpty else { return }

        var pool = buildDeck(from: sourceRecipes)
        var cursor = 0
        for index in targets {
            if pool.isEmpty || cursor >= pool.count {
                pool = buildDeck(from: sourceRecipes)
                cursor = 0
            }
            guard pool.indices.contains(cursor) else { break }
            assignments[index] = .recipe(pool[cursor])
            cursor += 1
        }

        deck = buildDeck(from: recipesForRefill())
        deckIndex = 0
        presentReview(.randomized)
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
        case .recipe: return "fork.knife"
        case .takeout: return "takeoutbag.and.cup.and.straw.fill"
        case .leftovers: return "refrigerator.fill"
        }
    }

    private func tint(for plan: WeekSlotPlan) -> Color {
        switch plan {
        case .recipe: return Color.terra500
        case .takeout: return Color.lilac500
        case .leftovers: return Color.sky500
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
                let formatter = NumberFormatter()
                formatter.minimumFractionDigits = 0
                formatter.maximumFractionDigits = 2
                let amountString = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
                text = "\(amountString) \(unit) \(name)".trimmingCharacters(in: .whitespaces)
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

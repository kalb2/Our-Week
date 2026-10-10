//
//  PlanWeekWizard.swift
//  OurWeek
//
//  Plan my week: pick categories, drag them onto the days Home is showing,
//  tap a recipe for each day, then save dinners the same way Swipe to plan does.
//

import SwiftUI
import UIKit
import CoreData

struct PlanPick: Identifiable, Hashable {
    var id: String
    var title: String
    var detail: String
    var emoji: String
    /// Library recipe URI. Nil means takeout or leftovers.
    var recipeURI: String?
}

struct PlanWeekWizard: View {
    /// The days Home is listing right now. Not always Monday–Sunday.
    let weekDays: [Date]
    var onSwipe: () -> Void

    @Environment(DataManager.self) private var dataManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Step: Equatable {
        case categories
        case days
        case pick
        case done
    }

    private enum PlanCover: Identifiable {
        case preview(PlanPick, Date)
        case recipe(Recipe)

        var id: String {
            switch self {
            case .preview(let pick, _):
                return "preview:\(pick.id)"
            case .recipe(let recipe):
                return "recipe:\(recipe.objectID.uriRepresentation().absoluteString)"
            }
        }
    }

    private static let dinnerType = "Dinner"
    private let chipColumns = [GridItem(.adaptive(minimum: 148), spacing: 10)]

    @State private var step: Step = .categories
    @State private var selected: [PlanCategory] = []
    @State private var customs: [PlanCategory] = []
    @State private var customName = ""
    @FocusState private var customFocused: Bool
    @FocusState private var restaurantFocused: Bool
    @State private var restaurantName = ""
    @State private var assignments: [Date: PlanCategory] = [:]
    @State private var seededIDs: Set<String> = []
    @State private var pickIndex = 0
    @State private var pickForward = true
    @State private var picks: [Date: PlanPick] = [:]
    @State private var recipes: [Recipe] = []
    @State private var existingDinners: [Date: [MealPlan]] = [:]
    @State private var didLoad = false
    @State private var isSaving = false
    @State private var showReplace = false
    @State private var showLeave = false
    @State private var leaveOpensSwipe = false
    @State private var armed: PlanCategory?
    @State private var dragCategory: PlanCategory?
    @State private var dragPoint: CGPoint = .zero
    @State private var hoverDay: Date?
    @State private var dayFrames: [Date: CGRect] = [:]
    @State private var boardOrigin: CGPoint = .zero
    @State private var limitNote: String?
    @State private var planSheet: PlanCover?
    @State private var showAddRecipe = false
    @State private var showTagNudge = false
    @State private var showTagWizard = false
    /// The tagging nudge shows at most once per app session.
    @MainActor private static var tagNudgeHandled = false
    /// Bumped when a night tag is toggled so menu and preview labels re-read the recipe's tags.
    @State private var tagRevision = 0

    /// Below this many category matches, the rest of his main dishes are listed too.
    private let matchPlenty = 4

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var categoryChoices: [PlanCategory] {
        PlanCategory.builtIn + customs
    }

    /// Chosen categories that are not sitting on a day yet.
    private var trayCategories: [PlanCategory] {
        let placed = Set(assignments.values.map(\.id))
        return selected.filter { !placed.contains($0.id) }
    }

    /// Nights in the week Home is showing. From-today can be fewer than seven.
    private var nightLimit: Int { weekDays.count }

    private var nightsAreFull: Bool {
        nightLimit > 0 && selected.count >= nightLimit
    }

    private var nightsLabel: String {
        nightsAreFull ? "Week full" : "\(selected.count) of \(nightLimit) nights"
    }

    private var daysAreFull: Bool {
        nightLimit > 0 && assignments.count >= nightLimit
    }

    private var daysFilledLabel: String {
        daysAreFull ? "Week full" : "\(assignments.count) of \(nightLimit) days filled"
    }

    private var assignedDays: [(date: Date, category: PlanCategory)] {
        weekDays.compactMap { date in
            guard let category = assignments[dayKey(date)] else { return nil }
            return (date, category)
        }
    }

    private var currentAssignment: (date: Date, category: PlanCategory)? {
        guard assignedDays.indices.contains(pickIndex) else { return nil }
        return assignedDays[pickIndex]
    }

    var body: some View {
        ZStack {
            Color.bgBase.ignoresSafeArea()
                .onTapGesture {
                    customFocused = false
                    restaurantFocused = false
                }
            VStack(spacing: 0) {
                header
                switch step {
                case .categories:
                    if showTagNudge {
                        tagNudge
                    } else {
                        categoriesStep
                    }
                case .days:
                    daysStep
                case .pick:
                    pickStep
                case .done:
                    doneStep
                }
            }
            if let dragCategory {
                paletteChip(dragCategory, lifted: true)
                    .position(x: dragPoint.x, y: dragPoint.y - 28.0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: "planWeek")
        .background(originReader)
        .onPreferenceChange(DayFrameKey.self) { dayFrames = $0 }
        .onPreferenceChange(BoardOriginKey.self) { boardOrigin = $0 }
        .preferredColorScheme(.light)
        .onAppear(perform: load)
        .fullScreenCover(isPresented: $showTagWizard, onDismiss: {
            recipes = dataManager.fetchRecipes(sortBy: .favoritesFirst)
            showTagNudge = false
        }) {
            TagRecipesWizard()
        }
        .onChange(of: pickIndex) { _, _ in syncRestaurantField() }
        .onChange(of: step) { _, new in
            if new == .pick { syncRestaurantField() }
        }
        .confirmationDialog(
            "Some days already have dinner",
            isPresented: $showReplace,
            titleVisibility: .visible
        ) {
            Button("Replace planned meals") { save(replacing: true) }
            Button("Only fill empty days") { save(replacing: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Replace the dinners already planned, or only fill days that are still open.")
        }
        .confirmationDialog(
            "Leave without saving?",
            isPresented: $showLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                if leaveOpensSwipe {
                    leaveOpensSwipe = false
                    onSwipe()
                } else {
                    dismiss()
                }
            }
            Button("Keep planning", role: .cancel) { leaveOpensSwipe = false }
        } message: {
            Text("The meals you picked stay off the week until you save.")
        }
        .sheet(item: $planSheet) { cover in
            switch cover {
            case .preview(let pick, let date):
                previewSheet(pick, day: date)
            case .recipe(let recipe):
                RecipeDetailView(recipe: recipe)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showAddRecipe, onDismiss: reloadRecipes) {
            QuickRecipeAddHost()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text(headerTitle)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            HStack {
                if step == .categories {
                    iconButton("xmark", label: "Close", action: requestClose)
                } else {
                    iconButton("chevron.left", label: "Back", action: goBack)
                }
                Spacer()
                if step != .categories {
                    iconButton("xmark", label: "Close", action: requestClose)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var headerTitle: String {
        switch step {
        case .categories: return "Plan my week"
        case .days: return "Assign days"
        case .pick: return "Pick meals"
        case .done: return "Your week"
        }
    }

    // MARK: - Categories

    private var categoriesStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What kind of week?")
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Text("Pick the kinds of night you want.")
                    .font(.system(size: 16))
                    .foregroundStyle(HomeQuiet.quiet)
                nightCounter
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 10) {
                        ForEach(categoryChoices) { category in
                            categoryChip(category)
                        }
                    }
                    customField
                    Button(action: requestSwipe) {
                        Text("or swipe through recipes")
                            .font(.system(size: 15))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { customFocused = false }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            if !selected.isEmpty {
                primaryButton("Next", action: enterDays)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
    }

    private func categoryChip(_ category: PlanCategory) -> some View {
        let on = selected.contains { $0.id == category.id }
        return Button {
            toggle(category)
        } label: {
            HStack(spacing: 8) {
                Text(category.emoji)
                Text(category.name)
                    .font(.system(size: 15, weight: .regular))
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(on ? Color.white : HomeQuiet.ink)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(on ? Color.terra500 : Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(on ? Color.clear : HomeQuiet.buttonStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var nightCounter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(nightsLabel)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(nightsAreFull ? Color.terra500 : HomeQuiet.ink)
            Text(limitNote ?? "That's every night.")
                .font(.system(size: 13))
                .foregroundStyle(limitNote == nil ? Color.clear : Color.terra600)
                .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                .accessibilityHidden(limitNote == nil)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(limitNote.map { "\(nightsLabel). \($0)" } ?? nightsLabel)
    }

    private var customField: some View {
        HStack(spacing: 10) {
            TextField("Your category", text: $customName)
                .font(.system(size: 17))
                .foregroundStyle(HomeQuiet.ink)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($customFocused)
                .onSubmit(addCustom)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(HomeQuiet.buttonStroke, lineWidth: 1)
                )
            if !customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(action: addCustom) {
                    Text("Add")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 52)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Days

    private var daysStep: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(daysFilledLabel)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(daysAreFull ? Color.terra500 : HomeQuiet.ink)
                Text(armed.map { "Tap a day for \($0.name)" } ?? "Drag onto a day, or tap one and then the day.")
                    .font(.system(size: 13))
                    .foregroundStyle(armed == nil ? HomeQuiet.quiet : Color.terra600)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
            GeometryReader { geo in
                let gap: CGFloat = 8
                let left = (geo.size.width - gap) * 0.55
                HStack(alignment: .top, spacing: gap) {
                    VStack(spacing: 6) {
                        ForEach(weekDays, id: \.self) { date in
                            dayTarget(date)
                        }
                    }
                    .frame(width: left, alignment: .top)
                    VStack(spacing: 4) {
                        if trayCategories.isEmpty {
                            Text("All set")
                                .font(.system(size: 13))
                                .foregroundStyle(HomeQuiet.quiet)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        } else {
                            ForEach(trayCategories) { category in
                                draggableChip(category)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, 12)
            if !assignments.isEmpty {
                primaryButton("Pick meals", action: enterPick)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
            }
        }
    }

    private func dayTarget(_ date: Date) -> some View {
        let key = dayKey(date)
        let category = assignments[key]
        let hovered = hoverDay == key
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(shortWeekday(date))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(HomeQuiet.quiet)
                Text(dayNumber(date))
                    .font(.system(size: 13, weight: .regular, design: .serif))
                    .foregroundStyle(Calendar.current.isDateInToday(date) ? Color.terra500 : HomeQuiet.ink)
            }
            .frame(width: 30, alignment: .leading)
            if let category {
                HStack(spacing: 4) {
                    Text(category.emoji)
                        .font(.system(size: 12))
                    Text(category.name)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Button {
                        armed = nil
                        clearDay(date)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(weekdayName(date))")
                }
                .padding(.leading, 6)
                .padding(.trailing, 2)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .background(Color.terra100)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text("Drop")
                    .font(.system(size: 12))
                    .foregroundStyle(HomeQuiet.quiet)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { placeArmed(on: date) }
        .background(hovered ? Color.terra50 : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(hovered ? Color.terra500 : HomeQuiet.cardStroke, lineWidth: hovered ? 1.5 : 1)
        )
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: DayFrameKey.self, value: [key: geo.frame(in: .global)])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dayAccessibilityLabel(date: date, category: category))
        .accessibilityHint(armed.map { "Places \($0.name) on this day" } ?? "Drop a category here")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            placeArmed(on: date)
        }
        .modifier(ClearDayAction(enabled: category != nil) { clearDay(date) })
    }

    private func draggableChip(_ category: PlanCategory) -> some View {
        compactChipLabel(category)
            .opacity(dragCategory?.id == category.id ? 0 : 1)
            .overlay {
                ChipGrab(
                    onChanged: { point in
                        dragCategory = category
                        dragPoint = local(point)
                        hoverDay = day(at: point)
                    },
                    onEnded: { point, translation, cancelled in
                        let distance = hypot(translation.x, translation.y)
                        if !cancelled, distance < 14.0 {
                            toggleArmed(category)
                        } else if !cancelled, let day = day(at: point) {
                            assign(category, to: day)
                        }
                        dragCategory = nil
                        hoverDay = nil
                    },
                    onTap: { toggleArmed(category) }
                )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(category.name)
            .accessibilityHint("Double tap, then double tap a day. You can also drag it onto a day.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(armed?.id == category.id ? .isSelected : [])
            .accessibilityAction { toggleArmed(category) }
    }

    private func compactChipLabel(_ category: PlanCategory) -> some View {
        let armedOn = armed?.id == category.id
        return HStack(alignment: .center, spacing: 5) {
            Text(category.emoji)
                .font(.system(size: 13))
            Text(category.name)
                .font(.system(size: 12, weight: .regular))
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
        .background(Color.terra500)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(armedOn ? 0.95 : 0), lineWidth: 2)
        )
    }

    private func paletteChip(_ category: PlanCategory, lifted: Bool) -> some View {
        chipLabel(category, lifted: lifted)
            .fixedSize(horizontal: true, vertical: false)
    }

    private func chipLabel(_ category: PlanCategory, lifted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(category.emoji)
            Text(category.name)
                .font(.system(size: 15, weight: .regular))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .frame(minHeight: 48, alignment: .leading)
        .background(Color.terra500)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(
                Color.white.opacity((armed?.id == category.id || lifted) ? 0.9 : 0),
                lineWidth: 2
            )
        )
        .shadow(color: lifted ? Color.black.opacity(0.16) : Color.clear, radius: 12, y: 6)
    }

    // MARK: - Pick

    private var pickStep: some View {
        VStack(spacing: 0) {
            dayStrip
                .padding(.horizontal, 20)
                .padding(.top, 8)
            ZStack {
                if let current = currentAssignment {
                    pickBody(current)
                        .id(dayKey(current.date))
                        .transition(pickTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Button(action: skipDay) {
                Text("Skip this day")
                    .font(.system(size: 16))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .accessibilityHint("Leaves this day open and moves on")
        }
    }

    private var dayStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(assignedDays.enumerated()), id: \.offset) { index, day in
                    let on = index == pickIndex
                    let picked = picks[dayKey(day.date)] != nil
                    Button {
                        jump(to: index)
                    } label: {
                        Text(shortWeekday(day.date))
                            .font(.system(size: 13, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? Color.white : HomeQuiet.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(on ? Color.terra500 : Color.white)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(
                                    !on && picked ? Color.terra500 : HomeQuiet.cardStroke,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(weekdayName(day.date)), \(day.category.name)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func pickBody(_ day: (date: Date, category: PlanCategory)) -> some View {
        if day.category.usesSingleChoice {
            return AnyView(simpleNight(day))
        }
        let menu = nightMenu(for: day.date, category: day.category)
        let currentID = picks[dayKey(day.date)]?.id
        let showOthers = menu.matches.count < matchPlenty
        return AnyView(VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekdayName(day.date))
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Text("\(day.category.emoji)  \(day.category.name)")
                    .font(.system(size: 16))
                    .foregroundStyle(HomeQuiet.quiet)
            }
            .padding(.horizontal, 24)
            if recipes.isEmpty {
                emptyLibrary
                    .padding(.horizontal, 24)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if menu.matches.isEmpty && menu.others.isEmpty {
                            Text("No main dishes in your recipe book yet.")
                                .font(.system(size: 17))
                                .foregroundStyle(HomeQuiet.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(menu.matches) { option in
                            optionCard(option, day: day.date, category: day.category, selected: option.id == currentID)
                        }
                        if showOthers {
                            tagHint(day.category)
                            if !menu.others.isEmpty {
                                Text("Other recipes")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(HomeQuiet.quiet)
                                    .padding(.top, 8)
                                ForEach(menu.others) { option in
                                    optionCard(option, day: day.date, category: day.category, selected: option.id == currentID)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                }
            }
        }
        .padding(.top, 16))
    }

    private func tagHint(_ category: PlanCategory) -> some View {
        Text("Tag recipes as \(category.name) to see them here.")
            .font(.system(size: 14))
            .foregroundStyle(HomeQuiet.quiet)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    private var emptyLibrary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your recipe book is empty.")
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            primaryButton("Add a recipe") { showAddRecipe = true }
        }
        .padding(.top, 8)
    }

    private func simpleNight(_ day: (date: Date, category: PlanCategory)) -> some View {
        let key = dayKey(day.date)
        let current = picks[key]
        let chosen = current != nil
        let title = day.category.id == "leftovers" ? "Leftovers" : "Takeout / eat out"
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(weekdayName(day.date))
                    .font(.system(size: 32, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Text("\(day.category.emoji)  \(day.category.name)")
                    .font(.system(size: 16))
                    .foregroundStyle(HomeQuiet.quiet)
            }
            .contentShape(Rectangle())
            .onTapGesture { restaurantFocused = false }
            Button {
                confirmSimple(day.category)
            } label: {
                HStack(spacing: 14) {
                    Text(day.category.emoji)
                        .font(.system(size: 36))
                    Text(title)
                        .font(.system(size: 26, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Spacer(minLength: 0)
                    if chosen {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.terra500)
                    }
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(chosen ? Color.terra500 : HomeQuiet.cardStroke, lineWidth: chosen ? 1.5 : 1)
                )
            }
            .buttonStyle(.plain)
            if day.category.id == "takeout" {
                TextField("Restaurant name", text: $restaurantName)
                    .font(.system(size: 17))
                    .foregroundStyle(HomeQuiet.ink)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($restaurantFocused)
                    .onSubmit { confirmSimple(day.category) }
                    .padding(.horizontal, 16)
                    .frame(height: 52)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(HomeQuiet.buttonStroke, lineWidth: 1)
                    )
            }
            Spacer(minLength: 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { restaurantFocused = false }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func optionCard(_ option: PlanPick, day: Date, category: PlanCategory, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                choose(option)
            } label: {
                optionLabel(option, selected: selected)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Pick for \(weekdayName(day))") { choose(option) }
                if libraryRecipe(option) != nil {
                    Button(tagActionTitle(option, category: category)) {
                        toggleNightTag(option, category: category)
                    }
                    Button("Open recipe") { openRecipe(option) }
                }
            } preview: {
                previewBody(option)
                    .frame(width: 300)
            }
            .id("\(option.id)-\(tagRevision)")
            Button {
                planSheet = .preview(option, day)
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(option.title)")
        }
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selected ? Color.terra500 : HomeQuiet.cardStroke, lineWidth: selected ? 1.5 : 1)
        )
    }

    private func optionLabel(_ option: PlanPick, selected: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            planThumb(image: rowImage(for: option))
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !option.detail.isEmpty {
                    Text(option.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(HomeQuiet.quiet)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 4)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.terra500)
            }
        }
        .padding(.leading, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func planThumb(image: UIImage?) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "fork.knife")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(HomeQuiet.quiet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.bgBase)
        }
    }

    private var pickTransition: AnyTransition {
        if reduceMotion { return .opacity }
        if pickForward {
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
        return .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }

    // MARK: - Done

    private var doneStep: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The week")
                            .font(.system(size: 32, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                        if !rangeLabel.isEmpty {
                            Text(rangeLabel)
                                .font(.system(size: 16))
                                .foregroundStyle(HomeQuiet.quiet)
                        }
                    }
                    VStack(spacing: 8) {
                        ForEach(weekDays, id: \.self) { date in
                            summaryRow(date)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            if !picks.isEmpty {
                primaryButton("Save week", action: requestSave)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
    }

    private func summaryRow(_ date: Date) -> some View {
        let key = dayKey(date)
        let pick = picks[key]
        let existing = existingTitle(on: date)
        return HStack(alignment: .center, spacing: 12) {
            VStack(spacing: 0) {
                Text(shortWeekday(date))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(HomeQuiet.quiet)
                Text(dayNumber(date))
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                if let pick {
                    Text(pick.title)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    if let existing {
                        Text("Replaces \(existing)")
                            .font(.system(size: 13))
                            .foregroundStyle(HomeQuiet.quiet)
                    } else if let category = assignments[key] {
                        Text(category.name)
                            .font(.system(size: 13))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                } else if let existing {
                    Text(existing)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Text("Already planned")
                        .font(.system(size: 13))
                        .foregroundStyle(HomeQuiet.quiet)
                } else {
                    Text("Open")
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.quiet)
                }
            }
            Spacer(minLength: 0)
            if let pick {
                Text(pick.emoji)
                    .font(.system(size: 22))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HomeQuiet.cardStroke, lineWidth: 1)
        )
    }

    // MARK: - Controls

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.terra500)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(HomeQuiet.ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var originReader: some View {
        GeometryReader { geo in
            Color.clear.preference(key: BoardOriginKey.self, value: geo.frame(in: .global).origin)
        }
    }

    // MARK: - Flow

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        recipes = dataManager.fetchRecipes(sortBy: .favoritesFirst)
        showTagNudge = !Self.tagNudgeHandled && TagRecipesWizard.needsTagging(recipes)
        refreshExisting()
    }

    private var tagNudge: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tag your recipes first so each night has good picks.")
                .font(.system(size: 26, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Text("It takes a minute. Obvious matches are already checked.")
                .font(.system(size: 15))
                .foregroundStyle(HomeQuiet.quiet)
            Button {
                Self.tagNudgeHandled = true
                showTagWizard = true
            } label: {
                Text("Tag recipes")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.terra500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Button {
                Self.tagNudgeHandled = true
                showTagNudge = false
            } label: {
                Text("Skip for now")
                    .font(.system(size: 16))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func toggle(_ category: PlanCategory) {
        customFocused = false
        if let index = selected.firstIndex(where: { $0.id == category.id }) {
            selected.remove(at: index)
            if selected.count < nightLimit { limitNote = nil }
            return
        }
        guard selected.count < nightLimit else {
            refuseAnotherNight()
            return
        }
        selected.append(category)
        if selected.count >= nightLimit { limitNote = nil }
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard selected.count < nightLimit else {
            refuseAnotherNight()
            return
        }
        let category = PlanCategory.custom(name: name)
        customs.append(category)
        selected.append(category)
        customName = ""
        customFocused = false
        if selected.count >= nightLimit { limitNote = nil }
    }

    private func refuseAnotherNight() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        limitNote = "That's every night."
    }

    private func enterDays() {
        customFocused = false
        pruneAssignments()
        seedDefaultsIfNeeded()
        armed = nil
        withAnimation(motion) { step = .days }
    }

    private func pruneAssignments() {
        let ids = Set(selected.map(\.id))
        let stale = assignments.keys.filter { !ids.contains(assignments[$0]?.id ?? "") }
        for key in stale {
            assignments[key] = nil
            picks[key] = nil
        }
    }

    private func toggleArmed(_ category: PlanCategory) {
        if armed?.id == category.id {
            armed = nil
        } else {
            armed = category
        }
    }

    private func seedDefaultsIfNeeded() {
        let calendar = Calendar.current
        for category in selected {
            guard let weekday = category.defaultWeekday, !seededIDs.contains(category.id) else { continue }
            seededIDs.insert(category.id)
            if assignments.values.contains(where: { $0.id == category.id }) { continue }
            guard let date = weekDays.first(where: { calendar.component(.weekday, from: $0) == weekday }) else { continue }
            let key = dayKey(date)
            if assignments[key] == nil {
                assignments[key] = category
            }
        }
    }

    private func enterPick() {
        let days = assignedDays
        guard !days.isEmpty else { return }
        let keys = Set(days.map { dayKey($0.date) })
        picks = picks.filter { keys.contains($0.key) }
        if pickIndex >= days.count {
            pickIndex = days.count - 1
        }
        armed = nil
        withAnimation(motion) { step = .pick }
    }

    private func assign(_ category: PlanCategory, to date: Date) {
        let key = dayKey(date)
        let displaced = assignments.keys.filter { $0 != key && assignments[$0]?.id == category.id }
        withAnimation(motion) {
            for other in displaced {
                assignments[other] = nil
                picks[other] = nil
            }
            if assignments[key]?.id != category.id {
                picks[key] = nil
            }
            assignments[key] = category
            armed = nil
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func placeArmed(on date: Date) {
        guard let armed else { return }
        assign(armed, to: date)
    }

    private func clearDay(_ date: Date) {
        let key = dayKey(date)
        assignments[key] = nil
        picks[key] = nil
    }

    private func confirmSimple(_ category: PlanCategory) {
        restaurantFocused = false
        let title: String
        let detail: String
        if category.id == "leftovers" {
            title = "Leftovers"
            detail = "Eat what you already cooked."
        } else {
            let place = restaurantName.trimmingCharacters(in: .whitespacesAndNewlines)
            if place.isEmpty {
                title = "Takeout / eat out"
                detail = "Order in or go out."
            } else {
                title = "Takeout: \(place)"
                detail = place
            }
        }
        choose(PlanPick(
            id: "s:\(category.id)",
            title: title,
            detail: detail,
            emoji: category.emoji,
            recipeURI: nil
        ))
    }

    private func syncRestaurantField() {
        restaurantFocused = false
        guard let current = currentAssignment, current.category.id == "takeout" else {
            restaurantName = ""
            return
        }
        let title = picks[dayKey(current.date)]?.title ?? ""
        let prefix = "Takeout: "
        if title.hasPrefix(prefix) {
            restaurantName = String(title.dropFirst(prefix.count))
        } else {
            restaurantName = ""
        }
    }

    private func choose(_ pick: PlanPick) {
        guard let current = currentAssignment else { return }
        picks[dayKey(current.date)] = pick
        advance()
    }

    private func skipDay() {
        guard let current = currentAssignment else { return }
        picks[dayKey(current.date)] = nil
        advance()
    }

    private func advance() {
        pickForward = true
        withAnimation(motion) {
            if pickIndex + 1 >= assignedDays.count {
                refreshExisting()
                step = .done
            } else {
                pickIndex += 1
            }
        }
    }

    private func jump(to index: Int) {
        guard assignedDays.indices.contains(index), index != pickIndex else { return }
        pickForward = index > pickIndex
        withAnimation(motion) { pickIndex = index }
    }

    private func goBack() {
        customFocused = false
        switch step {
        case .categories:
            break
        case .days:
            withAnimation(motion) { step = .categories }
        case .pick:
            if pickIndex == 0 {
                withAnimation(motion) { step = .days }
            } else {
                pickForward = false
                withAnimation(motion) { pickIndex -= 1 }
            }
        case .done:
            let last = max(assignedDays.count - 1, 0)
            pickIndex = last
            pickForward = false
            withAnimation(motion) { step = assignedDays.isEmpty ? .days : .pick }
        }
    }

    private func requestClose() {
        customFocused = false
        leaveOpensSwipe = false
        if picks.isEmpty {
            dismiss()
        } else {
            showLeave = true
        }
    }

    private func requestSwipe() {
        customFocused = false
        if picks.isEmpty {
            onSwipe()
        } else {
            leaveOpensSwipe = true
            showLeave = true
        }
    }

    private func requestSave() {
        guard !picks.isEmpty, !isSaving else { return }
        refreshExisting()
        let conflict = picks.keys.contains { !(existingDinners[$0] ?? []).isEmpty }
        if conflict {
            showReplace = true
        } else {
            save(replacing: true)
        }
    }

    private func save(replacing: Bool) {
        guard !isSaving else { return }
        isSaving = true
        for date in weekDays {
            let key = dayKey(date)
            guard let pick = picks[key] else { continue }
            let existing = existingDinners[key] ?? []
            if !existing.isEmpty {
                if !replacing { continue }
                dataManager.deleteMealPlans(existing)
            }
            if let uri = pick.recipeURI, let recipe = recipe(uri: uri) {
                _ = dataManager.createMealPlan(
                    title: displayName(recipe),
                    date: key,
                    mealType: Self.dinnerType,
                    notes: nil,
                    ingredients: ingredientString(for: recipe),
                    recipe: recipe
                )
            } else {
                _ = dataManager.createMealPlan(
                    title: pick.title,
                    date: key,
                    mealType: Self.dinnerType,
                    notes: nil,
                    ingredients: nil,
                    recipe: nil
                )
            }
        }
        NotificationCenter.default.post(name: .ourWeekPlansChanged, object: nil)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    // MARK: - Recipes

    private func nightMenu(for date: Date, category: PlanCategory) -> (matches: [PlanPick], others: [PlanPick]) {
        let key = dayKey(date)
        let taken = picks.filter { !Calendar.current.isDate($0.key, inSameDayAs: key) }
        let usedURIs = Set(taken.compactMap(\.value.recipeURI))
        let usedTitles = Set(taken.map { $0.value.title.lowercased() })

        var ranked: [(recipe: Recipe, score: Int)] = []
        for recipe in recipes {
            let uri = recipe.objectID.uriRepresentation().absoluteString
            if usedURIs.contains(uri) { continue }
            let name = displayName(recipe)
            if usedTitles.contains(name.lowercased()) { continue }
            guard PlanWeekCatalog.isDinnerMain(
                name: name,
                categories: recipe.categories,
                tags: recipe.tags,
                categoryID: category.id
            ) else { continue }
            let value = PlanWeekCatalog.score(
                name: name,
                categories: recipe.categories,
                tags: recipe.tags,
                minutes: Int(recipe.prepTime) + Int(recipe.cookTime),
                category: category
            )
            ranked.append((recipe, value))
        }

        let matches = ranked
            .filter { $0.score >= 10 }
            .sorted { recipeComesBefore($0, $1) }
            .map { libraryPick($0.recipe, category: category) }
        let others = ranked
            .filter { $0.score < 10 }
            .sorted { recipeComesBefore($0, $1) }
            .map { libraryPick($0.recipe, category: category) }
        return (matches, others)
    }

    private func recipeComesBefore(_ lhs: (recipe: Recipe, score: Int), _ rhs: (recipe: Recipe, score: Int)) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.recipe.isFavorite != rhs.recipe.isFavorite { return lhs.recipe.isFavorite && !rhs.recipe.isFavorite }
        return displayName(lhs.recipe).localizedCaseInsensitiveCompare(displayName(rhs.recipe)) == .orderedAscending
    }

    private func libraryPick(_ recipe: Recipe, category: PlanCategory) -> PlanPick {
        let name = displayName(recipe)
        let uri = recipe.objectID.uriRepresentation().absoluteString
        let about = recipe.recipeDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let minutes = Int(recipe.prepTime) + Int(recipe.cookTime)
        let detail: String
        if !about.isEmpty {
            detail = about
        } else if minutes > 0 {
            detail = "\(minutes) min"
        } else {
            detail = ""
        }
        return PlanPick(id: uri, title: name, detail: detail, emoji: category.emoji, recipeURI: uri)
    }

    private func reloadRecipes() {
        recipes = dataManager.fetchRecipes(sortBy: .favoritesFirst)
    }

    private func hasNightTag(_ recipe: Recipe, _ name: String) -> Bool {
        RecipeLabelFormatting.decodeTags(recipe.tags).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func tagActionTitle(_ option: PlanPick, category: PlanCategory) -> String {
        _ = tagRevision
        if let recipe = libraryRecipe(option), hasNightTag(recipe, category.name) {
            return "Remove \(category.name) tag"
        }
        return "Tag as \(category.name)"
    }

    private func toggleNightTag(_ option: PlanPick, category: PlanCategory) {
        guard let recipe = libraryRecipe(option) else { return }
        if hasNightTag(recipe, category.name) {
            let tags = RecipeLabelFormatting.decodeTags(recipe.tags)
                .filter { $0.caseInsensitiveCompare(category.name) != .orderedSame }
            dataManager.setRecipesTags([recipe], tags: tags.isEmpty ? nil : tags.joined(separator: ", "))
        } else {
            dataManager.addTagsToRecipes([recipe], tags: category.name)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadRecipes()
        tagRevision &+= 1
    }

    private func recipe(uri: String) -> Recipe? {
        recipes.first { $0.objectID.uriRepresentation().absoluteString == uri }
    }

    private func displayName(_ recipe: Recipe) -> String {
        let name = recipe.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Recipe" : name
    }

    /// Same `0|text` lines Swipe to plan writes, so a linked recipe can sync groceries.
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

    private func refreshExisting() {
        guard let first = weekDays.first, let last = weekDays.last else {
            existingDinners = [:]
            return
        }
        let meals = dataManager.fetchMealPlans(from: dayKey(first), through: dayKey(last))
        var map: [Date: [MealPlan]] = [:]
        for date in weekDays {
            let key = dayKey(date)
            map[key] = meals.filter { meal in
                guard let mealDate = meal.date, Calendar.current.isDate(mealDate, inSameDayAs: key) else { return false }
                return (meal.mealType ?? "dinner").lowercased() == "dinner"
            }
        }
        existingDinners = map
    }

    private func existingTitle(on date: Date) -> String? {
        guard let meal = existingDinners[dayKey(date)]?.first else { return nil }
        let title = meal.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "Dinner" : title
    }

    // MARK: - Preview

    private func previewSheet(_ option: PlanPick, day: Date) -> some View {
        ScrollView {
            previewBody(option)
        }
        .background(Color.bgBase)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button {
                    planSheet = nil
                    choose(option)
                } label: {
                    Text("Pick for \(weekdayName(day))")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                if libraryRecipe(option) != nil, let category = assignments[dayKey(day)] {
                    Button {
                        toggleNightTag(option, category: category)
                    } label: {
                        Text(tagActionTitle(option, category: category))
                            .font(.system(size: 16))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                    Button {
                        openRecipe(option)
                    } label: {
                        Text("Open recipe")
                            .font(.system(size: 16))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(Color.bgBase)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgBase)
    }

    private func previewBody(_ option: PlanPick) -> some View {
        let model = previewModel(for: option)
        return PlanPreviewBody(
            title: option.title,
            detail: model.detail,
            image: model.image,
            ingredients: model.ingredients,
            meta: model.meta
        )
    }

    private func openRecipe(_ option: PlanPick) {
        guard let recipe = libraryRecipe(option) else { return }
        if let cover = planSheet, case .preview(_, _) = cover {
            planSheet = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                planSheet = .recipe(recipe)
            }
        } else {
            planSheet = .recipe(recipe)
        }
    }

    private func libraryRecipe(_ option: PlanPick) -> Recipe? {
        guard let uri = option.recipeURI else { return nil }
        return recipe(uri: uri)
    }

    private func rowImage(for option: PlanPick) -> UIImage? {
        guard let recipe = libraryRecipe(option),
              let data = recipe.imageData,
              let image = UIImage(data: data) else { return nil }
        return image
    }

    private func previewModel(for option: PlanPick) -> PlanPreviewModel {
        guard let recipe = libraryRecipe(option) else {
            return PlanPreviewModel(image: nil, detail: option.detail, ingredients: [], meta: nil)
        }
        let about = recipe.recipeDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return PlanPreviewModel(
            image: recipe.imageData.flatMap { UIImage(data: $0) },
            detail: about,
            ingredients: libraryLines(recipe),
            meta: libraryMeta(recipe)
        )
    }

    private func libraryLines(_ recipe: Recipe) -> [String] {
        var seen = Set<String>()
        var lines: [String] = []
        for ingredient in dataManager.sortedIngredients(for: recipe) {
            let line = CookingAmount.line(
                amount: ingredient.amount,
                unit: ingredient.unit ?? "",
                name: ingredient.name ?? "",
                notes: ingredient.notes ?? ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, seen.insert(line).inserted else { continue }
            lines.append(line)
            if lines.count == 8 { break }
        }
        return lines
    }

    private func libraryMeta(_ recipe: Recipe) -> String? {
        let minutes = Int(recipe.prepTime) + Int(recipe.cookTime)
        let servings = Int(recipe.servings)
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) min") }
        if servings == 1 {
            parts.append("1 serving")
        } else if servings > 1 {
            parts.append("\(servings) servings")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Dates

    private func dayKey(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func local(_ global: CGPoint) -> CGPoint {
        CGPoint(x: global.x - boardOrigin.x, y: global.y - boardOrigin.y)
    }

    private func day(at global: CGPoint) -> Date? {
        dayFrames.first { $0.value.contains(global) }?.key
    }

    private func weekdayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func shortWeekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private var rangeLabel: String {
        guard let first = weekDays.first, let last = weekDays.last else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    private func dayAccessibilityLabel(date: Date, category: PlanCategory?) -> String {
        if let category {
            return "\(weekdayName(date)), \(category.name)"
        }
        return "\(weekdayName(date)), empty"
    }
}

private struct DayFrameKey: PreferenceKey {
    static var defaultValue: [Date: CGRect] = [:]
    static func reduce(value: inout [Date: CGRect], nextValue: () -> [Date: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct BoardOriginKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

private struct ClearDayAction: ViewModifier {
    var enabled: Bool
    var action: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.accessibilityAction(named: Text("Clear"), action)
        } else {
            content
        }
    }
}

private struct ChipGrab: UIViewRepresentable {
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint, CGPoint, Bool) -> Void
    var onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded, onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delegate = context.coordinator
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.require(toFail: pan)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGPoint) -> Void
        var onEnded: (CGPoint, CGPoint, Bool) -> Void
        var onTap: () -> Void

        init(
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping (CGPoint, CGPoint, Bool) -> Void,
            onTap: @escaping () -> Void
        ) {
            self.onChanged = onChanged
            self.onEnded = onEnded
            self.onTap = onTap
        }

        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: nil)
            switch gesture.state {
            case .began, .changed:
                onChanged(point)
            case .ended:
                onEnded(point, gesture.translation(in: nil), false)
            case .cancelled, .failed:
                onEnded(point, .zero, true)
            default:
                break
            }
        }

        @objc func tap(_ gesture: UITapGestureRecognizer) {
            onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            var view = otherGestureRecognizer.view
            while let current = view {
                if current is UIScrollView { return true }
                view = current.superview
            }
            return false
        }
    }
}

private struct PlanPreviewModel {
    var image: UIImage?
    var detail: String
    var ingredients: [String]
    var meta: String?
}

private struct PlanPreviewBody: View {
    var title: String
    var detail: String
    var image: UIImage?
    var ingredients: [String]
    var meta: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
            } else {
                Image(systemName: "fork.knife")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.bgBase)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.terra600)
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 15))
                        .foregroundStyle(HomeQuiet.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(ingredients.enumerated()), id: \.offset) { _, item in
                            Text(item)
                                .font(.system(size: 14))
                                .foregroundStyle(HomeQuiet.ink)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgBase)
    }
}

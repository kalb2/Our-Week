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
    /// Library recipe URI. Nil means a typed meal title.
    var recipeURI: String?
    /// True when the row is from the household library.
    var yours: Bool = false
    /// Asset catalog name for a curated photo.
    var imageName: String? = nil
    var ingredients: [String] = []
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
                    categoriesStep
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
            if let limitNote {
                Text(limitNote)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.terra600)
            }
        }
        .accessibilityElement(children: .combine)
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
                    VStack(spacing: 4) {
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
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
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
        let rows = options(for: day.date, category: day.category)
        let currentID = picks[dayKey(day.date)]?.id
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
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(rows) { option in
                        optionCard(option, day: day.date, selected: option.id == currentID)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .padding(.top, 16))
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

    private func optionCard(_ option: PlanPick, day: Date, selected: Bool) -> some View {
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
                    Button("Open recipe") { openRecipe(option) }
                }
            } preview: {
                previewBody(option)
                    .frame(width: 300)
            }
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
            planThumb(image: rowImage(for: option), emoji: option.emoji)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(option.title)
                        .font(.system(size: 18, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if option.yours {
                        Text("Yours")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.terra600)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.terra100)
                            .clipShape(Capsule())
                    }
                }
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
    private func planThumb(image: UIImage?, emoji: String) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Text(emoji)
                .font(.system(size: 28))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.terra50)
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
        refreshExisting()
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

    private func options(for date: Date, category: PlanCategory) -> [PlanPick] {
        let key = dayKey(date)
        let others = picks.filter { !Calendar.current.isDate($0.key, inSameDayAs: key) }
        let usedURIs = Set(others.compactMap(\.value.recipeURI))
        let usedTitles = Set(others.map { $0.value.title.lowercased() })

        let ranked = recipes.compactMap { recipe -> (Recipe, Int)? in
            let uri = recipe.objectID.uriRepresentation().absoluteString
            if usedURIs.contains(uri) { return nil }
            let name = displayName(recipe)
            if usedTitles.contains(name.lowercased()) { return nil }
            let value = PlanWeekCatalog.score(
                name: name,
                categories: recipe.categories,
                tags: recipe.tags,
                details: recipe.recipeDescription,
                ingredients: ingredientText(recipe),
                minutes: Int(recipe.prepTime) + Int(recipe.cookTime),
                category: category
            )
            guard value > 0 else { return nil }
            return (recipe, value)
        }
        .sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            if lhs.0.isFavorite != rhs.0.isFavorite { return lhs.0.isFavorite && !rhs.0.isFavorite }
            return displayName(lhs.0).localizedCaseInsensitiveCompare(displayName(rhs.0)) == .orderedAscending
        }

        var rows: [PlanPick] = []
        for recipe in ranked where recipe.1 >= 10 && rows.count < 10 {
            rows.append(libraryPick(recipe.0, category: category))
        }
        appendSuggestions(PlanWeekCatalog.rows(for: category), to: &rows, category: category, usedTitles: usedTitles)
        if rows.count < 10 {
            appendSuggestions(PlanWeekCatalog.general, to: &rows, category: category, usedTitles: usedTitles)
        }
        for recipe in ranked where recipe.1 < 10 && rows.count < 10 {
            rows.append(libraryPick(recipe.0, category: category))
        }

        if let current = picks[key], !rows.contains(where: { $0.id == current.id }) {
            rows.insert(current, at: 0)
        }
        return Array(rows.prefix(10))
    }

    private func appendSuggestions(
        _ suggestions: [PlanSuggestion],
        to rows: inout [PlanPick],
        category: PlanCategory,
        usedTitles: Set<String>
    ) {
        for suggestion in suggestions {
            if rows.count >= 10 { break }
            if usedTitles.contains(suggestion.title.lowercased()) { continue }
            if rows.contains(where: { $0.title.caseInsensitiveCompare(suggestion.title) == .orderedSame }) { continue }
            rows.append(suggestionPick(suggestion, category: category))
        }
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
        return PlanPick(id: uri, title: name, detail: detail, emoji: category.emoji, recipeURI: uri, yours: true)
    }

    private func suggestionPick(_ suggestion: PlanSuggestion, category: PlanCategory) -> PlanPick {
        PlanPick(
            id: "s:\(category.id):\(suggestion.title)",
            title: suggestion.title,
            detail: suggestion.detail,
            emoji: suggestion.emoji,
            recipeURI: nil,
            imageName: suggestion.image,
            ingredients: suggestion.ingredients
        )
    }

    private func ingredientText(_ recipe: Recipe) -> String {
        let names = dataManager.sortedIngredients(for: recipe).compactMap(\.name)
        return ([recipe.ingredients].compactMap { $0 } + names).joined(separator: " ")
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
            VStack(spacing: 8) {
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
                if libraryRecipe(option) != nil {
                    Button {
                        openRecipe(option)
                    } label: {
                        Text("Open recipe")
                            .font(.system(size: 16))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.bgBase)
    }

    private func previewBody(_ option: PlanPick) -> some View {
        let model = previewModel(for: option)
        return PlanPreviewBody(
            title: option.title,
            detail: model.detail,
            emoji: option.emoji,
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
        if let recipe = libraryRecipe(option),
           let data = recipe.imageData,
           let image = UIImage(data: data) {
            return image
        }
        return bundledPhoto(option.imageName)
    }

    private func bundledPhoto(_ name: String?) -> UIImage? {
        guard let name, !name.isEmpty else { return nil }
        return UIImage(named: name)
    }

    private func previewModel(for option: PlanPick) -> PlanPreviewModel {
        if let recipe = libraryRecipe(option) {
            let about = recipe.recipeDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return PlanPreviewModel(
                image: recipe.imageData.flatMap { UIImage(data: $0) },
                detail: about,
                ingredients: libraryLines(recipe),
                meta: libraryMeta(recipe)
            )
        }
        return PlanPreviewModel(
            image: bundledPhoto(option.imageName),
            detail: option.detail,
            ingredients: Array(option.ingredients.prefix(8)),
            meta: nil
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
    var emoji: String
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
                Text(emoji)
                    .font(.system(size: 56))
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                    .background(Color.terra50)
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

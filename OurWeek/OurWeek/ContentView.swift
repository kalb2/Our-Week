import SwiftUI
import UIKit
import PhotosUI
import EventKit
import CoreData

// MARK: - Design Tokens (from Tailwind config)
extension Color {
    // Background
    static let bgBase = Color(red: 1.0, green: 0.976, blue: 0.965)    // #fff9f6
    static let cardWhite = Color.white

    // Peach / Terracotta (Meals accent)
    static let peach50  = Color(red: 1.0, green: 0.957, blue: 0.941)
    static let peach500 = Color(red: 1.0, green: 0.400, blue: 0.224)   // #ff6639
    static let terra100 = Color(red: 1.0, green: 0.894, blue: 0.839)   // #ffe4d6
    static let terra200 = Color(red: 1.0, green: 0.800, blue: 0.722)   // #ffccb8
    static let terra300 = Color(red: 1.0, green: 0.698, blue: 0.600)   // #ffb299
    static let terra400 = Color(red: 1.0, green: 0.537, blue: 0.400)   // #ff8966
    static let terra500 = Color(red: 0.878, green: 0.478, blue: 0.373) // #e07a5f
    static let terra600 = Color(red: 0.761, green: 0.369, blue: 0.259) // #c25e42
    static let terra50  = Color(red: 1.0, green: 0.945, blue: 0.925)

    // Lilac (Events accent)
    static let lilac100 = Color(red: 0.953, green: 0.910, blue: 1.0)   // #f3e8ff
    static let lilac200 = Color(red: 0.914, green: 0.835, blue: 1.0)   // #e9d5ff
    static let lilac400 = Color(red: 0.753, green: 0.518, blue: 0.988) // #c084fc
    static let lilac500 = Color(red: 0.659, green: 0.333, blue: 0.969) // #a855f7
    static let lilac600 = Color(red: 0.576, green: 0.200, blue: 0.918) // #9333ea

    // Lime
    static let lime100 = Color(red: 0.925, green: 0.988, blue: 0.796)  // #ecfccb
    static let lime400 = Color(red: 0.639, green: 0.902, blue: 0.208)  // #a3e635
    static let lime500 = Color(red: 0.518, green: 0.800, blue: 0.086)  // #84cc16

    // Sky
    static let sky100 = Color(red: 0.878, green: 0.950, blue: 0.996)   // #e0f2fe
    static let sky200 = Color(red: 0.73, green: 0.90, blue: 0.98)
    static let sky400 = Color(red: 0.220, green: 0.741, blue: 0.973)   // #38bdf8
    static let sky500 = Color(red: 0.055, green: 0.647, blue: 0.914)   // #0ea5e9
}

// MARK: - Bold Shadow Modifier (Neo-Brutalist)
struct BoldShadow: ViewModifier {
    let color: Color
    let x: CGFloat
    let y: CGFloat

    init(color: Color, size: CGFloat = 4) {
        self.color = color
        self.x = size
        self.y = size
    }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(color)
                    .offset(x: x, y: y)
            )
    }
}

extension View {
    func boldShadow(_ color: Color, size: CGFloat = 4, radius: CGFloat = 16) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius)
                .fill(color)
                .offset(x: size, y: size)
        )
    }

    func boldShadowSm(_ color: Color, radius: CGFloat = 8) -> some View {
        self.background(
            RoundedRectangle(cornerRadius: radius)
                .fill(color)
                .offset(x: 2, y: 2)
        )
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @State private var showSharingSettings = false
    @State private var showAddSheet = false
    @State private var showAddMealSheet = false
    @State private var showAddEventSheet = false
    @State private var triggerAddTodo = false
    @State private var isKeyboardVisible = false
    @Environment(DataManager.self) private var dataManager

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:    HomeView(showSharingSettings: $showSharingSettings, triggerAddTodo: $triggerAddTodo)
                case .calendar: CalendarView()
                case .add:     PlaceholderView(title: "Add")
                case .meals:   RecipeLibraryView(showSharingSettings: $showSharingSettings)
                case .shop:    ShoppingListView(showSharingSettings: $showSharingSettings)
                }
            }
            if !isKeyboardVisible {
                MainTabBar(selectedTab: $selectedTab, onAddTapped: {
                    showAddSheet = true
                })
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) {
                isKeyboardVisible = false
            }
        }
        .sheet(isPresented: $showSharingSettings) {
            SharingSettingsView()
        }
        .sheet(isPresented: $showAddSheet) {
            AddActionSheet(
                onAddEvent: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAddEventSheet = true
                    }
                },
                onAddMeal: {
                    showAddSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showAddMealSheet = true
                    }
                },
                onAddTodo: {
                    showAddSheet = false
                    selectedTab = .home
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        triggerAddTodo = true
                    }
                },
                onAddShopping: {
                    showAddSheet = false
                    selectedTab = .shop
                }
            )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddMealSheet) {
            AddMealSheet(
                date: Date(),
                dataManager: dataManager
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddEventSheet) {
            AddEventSheet(
                date: Date(),
                dataManager: dataManager
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.light)
        .onAppear { openSharedImportIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: ShareImportStore.didArrive)) { _ in
            openSharedImportIfNeeded()
        }
    }

    private func openSharedImportIfNeeded() {
        if ShareImportStore.hasPending {
            selectedTab = .meals
        }
    }
}

// MARK: - Home View
struct HomeView: View {
    @Binding var showSharingSettings: Bool
    @Binding var triggerAddTodo: Bool
    @State private var keyboardOverlap: CGFloat = 0
    @State private var focusedLineID: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    GreetingHeader(showSharingSettings: $showSharingSettings)
                    WeeklyCalendarCard { id in
                        focusedLineID = id
                        reveal(id, proxy: proxy)
                    }
                    .padding(.bottom, 24)
                    TodoSection(triggerAdd: $triggerAddTodo)
                        .padding(.bottom, 24)
                    DailyGoalsSection()
                    Spacer().frame(height: 120 + keyboardOverlap)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .background(Color.bgBase)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                let overlap = keyboardOverlapHeight(from: note)
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardOverlap = overlap
                }
                if overlap > 0, let id = focusedLineID {
                    reveal(id, proxy: proxy)
                }
            }
        }
    }

    private func reveal(_ id: String, proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.28)) {
                proxy.scrollTo(id, anchor: UnitPoint(x: 0.5, y: 0.22))
            }
        }
    }

    private func keyboardOverlapHeight(from note: Notification) -> CGFloat {
        guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return 0 }
        let screenHeight = note.object.flatMap { $0 as? UIWindow }?.bounds.height ?? UIScreen.main.bounds.height
        return max(0, screenHeight - frame.minY)
    }
}

// MARK: - Greeting Header
struct GreetingHeader: View {
    @Binding var showSharingSettings: Bool
    @Environment(DataManager.self) var dataManager
    
    @AppStorage("profileImageData") private var profileImageData: Data?
    @AppStorage("userProfileName") private var profileName = ""
    @State private var showCalendarSettings = false
    @State private var showProfileMenu = false

    /// The person holding the phone. Local profile wins. Household owner is only a
    /// fallback. Never invent a demo name when both are empty.
    private var greetingName: String? {
        let profile = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profile.isEmpty { return profile }
        let owner = dataManager.currentHousehold?.ownerName?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !owner.isEmpty { return owner }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(greetingName == nil ? "Good Morning" : "Good Morning,")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .tracking(-0.5)
                    if let greetingName {
                        Text(greetingName)
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .italic()
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.peach500, Color.terra500],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                Spacer()
                Button(action: { showProfileMenu = true }) {
                    AvatarButton(imageData: profileImageData)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .sheet(isPresented: $showCalendarSettings) {
            CalendarSettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuSheet(
                onSharingTapped: { showSharingSettings = true },
                onCalendarTapped: { showCalendarSettings = true }
            )
            .presentationDetents([.height(290)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Avatar Button (Neo-Brutalist)
struct AvatarButton: View {
    let imageData: Data?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Container with bold shadow
            Circle()
                .fill(Color.black)
                .frame(width: 52, height: 52)
                .offset(x: 4, y: 4)

            Circle()
                .fill(Color.cardWhite)
                .frame(width: 52, height: 52)
                .overlay(
                    Circle().stroke(Color.black, lineWidth: 2)
                )
                .overlay(
                    Group {
                        if let imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.terra100, Color.terra200],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Color.terra500)
                                )
                        }
                    }
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().stroke(Color.black, lineWidth: 1)
                    )
                )

            // Green status dot
            Circle()
                .fill(Color.lime400)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.black, lineWidth: 2))
                .offset(x: -2, y: 2)
        }
    }
}

// MARK: - Weekly Calendar Card

private enum DinnerField: Hashable {
    case line(day: Date, id: String)
}

/// Tap outside a meal field to drop the keyboard. Text fields are left alone so a tap still focuses them.
private struct MealKeyboardDismissInstaller: UIViewRepresentable {
    var focusStamp: () -> Int
    var onDismiss: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        MealKeyboardDismissRelay.shared.focusStamp = focusStamp
        MealKeyboardDismissRelay.shared.onDismiss = onDismiss
        context.coordinator.scheduleInstall(from: uiView)
    }

    final class Coordinator: NSObject {
        private weak var installedOn: UIScrollView?
        private var waitingToInstall = false
        private let tapName = "ourweek.mealKeyboardDismiss"

        func scheduleInstall(from view: UIView) {
            guard installedOn == nil, !waitingToInstall else { return }
            waitingToInstall = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.waitingToInstall = false
                guard let view, self.installedOn == nil else { return }
                self.install(from: view)
                guard self.installedOn == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak view] in
                    guard let self, let view, self.installedOn == nil else { return }
                    self.install(from: view)
                }
            }
        }

        func install(from view: UIView) {
            guard installedOn == nil, let scroll = view.enclosingScrollView() else { return }
            if scroll.gestureRecognizers?.contains(where: { $0.name == tapName }) == true {
                installedOn = scroll
                return
            }
            let relay = MealKeyboardDismissRelay.shared
            let tap = UITapGestureRecognizer(target: relay, action: #selector(MealKeyboardDismissRelay.handleTap))
            tap.name = tapName
            tap.cancelsTouchesInView = false
            tap.delegate = relay
            scroll.addGestureRecognizer(tap)
            installedOn = scroll
        }
    }
}

/// Lives for the app so the scroll-view tap never points at a released coordinator.
private final class MealKeyboardDismissRelay: NSObject, UIGestureRecognizerDelegate {
    static let shared = MealKeyboardDismissRelay()

    var focusStamp: () -> Int = { 0 }
    var onDismiss: (Int) -> Void = { _ in }
    private var stampAtTouchDown = 0

    @objc func handleTap() {
        onDismiss(stampAtTouchDown)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        stampAtTouchDown = focusStamp()
        guard let view = touch.view else { return true }
        return !view.isInsideTextInput
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private extension UIView {
    func enclosingScrollView() -> UIScrollView? {
        var current: UIView? = self
        while let view = current {
            if let scroll = view as? UIScrollView { return scroll }
            current = view.superview
        }
        return nil
    }

    var isInsideTextInput: Bool {
        var current: UIView? = self
        while let view = current {
            if view is UITextField || view is UITextView { return true }
            current = view.superview
        }
        return false
    }

    var currentFirstResponder: UIView? {
        if isFirstResponder { return self }
        for subview in subviews {
            if let found = subview.currentFirstResponder { return found }
        }
        return nil
    }
}

private extension UIColor {
    /// White ink wins only when it contrasts more than black on this fill.
    var chipInkIsWhite: Bool {
        let lum = chipRelativeLuminance
        let whiteContrast = 1.05 / (lum + 0.05)
        let blackContrast = (lum + 0.05) / 0.05
        return whiteContrast > blackContrast
    }

    var chipRelativeLuminance: CGFloat {
        let source = resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).cgColor
        let rgb = source.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil) ?? source
        guard let comps = rgb.components, comps.count >= 3 else { return 1 }
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * channel(comps[0])) + (0.7152 * channel(comps[1])) + (0.0722 * channel(comps[2]))
    }
}

private struct DinnerLine: Identifiable {
    var id: String
    var mealID: NSManagedObjectID?
    var text: String
    var recipeID: NSManagedObjectID?
}

struct WeeklyCalendarCard: View {
    var onFocusScroll: (String) -> Void = { _ in }

    @Environment(DataManager.self) private var dataManager
    @Environment(CalendarSyncManager.self) private var calendarSyncManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var weekMeals: [MealPlan] = []
    @State private var weekEvents: [CalendarEvent] = []
    @State private var appleEvents: [AppleCalendarEvent] = []
    @State private var addingEventDate: Date?
    @State private var showEventSheet = false
    @State private var selectedEvent: CalendarEvent?
    @State private var selectedAppleEvent: AppleCalendarEvent?
    @State private var weekOffset: Int = 0
    @State private var showWeekPlanner = false
    @State private var recipes: [Recipe] = []
    @State private var linesByDay: [Date: [DinnerLine]] = [:]
    @State private var skipNextCommitID: String?
    @State private var suppressBlankEcho: [Date: String] = [:]
    @State private var showCalendarSettings = false
    @State private var showClearWeek = false
    @State private var suppressCommit = false
    @State private var expandedEventDays: Set<Date> = []
    @State private var mealFocusStamp = 0
    @AppStorage("homeLayoutMode") private var homeLayoutMode = "week"
    @FocusState private var focusedField: DinnerField?

    // Week dates (Mon-Sun) offset by weekOffset
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        guard let thisMonday = calendar.date(byAdding: .day, value: daysToMonday, to: today),
              let monday = calendar.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private var weekRangeLabel: String {
        guard let first = weekDates.first, let last = weekDates.last else { return "" }
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let firstStr = df.string(from: first)
        if cal.component(.month, from: first) == cal.component(.month, from: last) {
            let dayFmt = DateFormatter()
            dayFmt.dateFormat = "d"
            return "\(firstStr) – \(dayFmt.string(from: last))"
        }
        return "\(firstStr) – \(df.string(from: last))"
    }

    private func dayKey(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func meals(for date: Date) -> [MealPlan] {
        let calendar = Calendar.current
        return weekMeals.filter { meal in
            guard let d = meal.date else { return false }
            return calendar.isDate(d, inSameDayAs: date)
        }
    }

    private func dinners(for date: Date) -> [MealPlan] {
        meals(for: date)
            .filter { ($0.mealType ?? "dinner").lowercased() == "dinner" }
            .sorted { lhs, rhs in
                let left = lhs.date ?? .distantPast
                let right = rhs.date ?? .distantPast
                if left != right { return left < right }
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
    }

    private func events(for date: Date) -> [CalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return weekEvents.filter { event in
            guard let eventStart = event.date else { return false }
            if let eventEnd = event.endDate, eventEnd > eventStart {
                return eventStart < end && eventEnd > start
            }
            return calendar.isDate(eventStart, inSameDayAs: date)
        }
    }

    private func appleEventsForDate(_ date: Date) -> [AppleCalendarEvent] {
        appleEvents.filter { $0.occurs(on: date) }
    }

    var body: some View {
        homeSurface
            .padding(.horizontal, 24)
            .background {
                MealKeyboardDismissInstaller(
                    focusStamp: { mealFocusStamp },
                    onDismiss: dismissMealKeyboard(fromStamp:)
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
                let stamp = mealFocusStamp
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard stamp == mealFocusStamp, focusedField != nil, !Self.textInputIsFirstResponder() else { return }
                    focusedField = nil
                }
            }
            .onAppear {
                dataManager.replaceDemoOwnerNameIfNeeded()
                loadData()
                refreshAppleEvents()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshAppleEvents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                refreshAppleEvents()
            }
            .sheet(isPresented: $showCalendarSettings, onDismiss: { refreshAppleEvents() }) {
                CalendarSettingsView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .onChange(of: weekOffset) { _, _ in
                if case .line(let day, let id) = focusedField {
                    commitLine(day: day, lineID: id)
                }
                focusedField = nil
                loadData()
                refreshAppleEvents()
            }
            .onChange(of: focusedField) { old, new in
                if new != nil {
                    mealFocusStamp += 1
                }
                if case .line(let day, let id) = old {
                    DispatchQueue.main.async {
                        commitLine(day: day, lineID: id)
                    }
                }
                if case .line(let day, let id) = new {
                    onFocusScroll(scrollID(day: day, lineID: id))
                }
            }
            .onDisappear {
                if case .line(let day, let id) = focusedField {
                    commitLine(day: day, lineID: id)
                }
            }
            .sheet(isPresented: $showEventSheet, onDismiss: {
                loadData()
                refreshAppleEvents()
            }) {
            AddEventSheet(
                date: addingEventDate ?? Date(),
                dataManager: dataManager
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedEvent, onDismiss: {
            loadData()
            refreshAppleEvents()
        }) { event in
            EventDetailSheet(event: event)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedAppleEvent, onDismiss: {
            loadData()
            refreshAppleEvents()
        }) { appleEvent in
            AppleEventDetailSheet(event: appleEvent)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showWeekPlanner, onDismiss: {
            loadData()
            refreshAppleEvents()
        }) {
            WeekPlannerView(weekStart: weekDates.first ?? Date())
        }
        .fullScreenCover(isPresented: $showClearWeek) {
            clearWeekPrompt
                .presentationBackground(.clear)
        }
    }

    private var homeSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { dismissMealKeyboard() }
                layoutToggle
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            if let cue = calendarSyncManager.calendarSelectionCue {
                Button {
                    showCalendarSettings = true
                } label: {
                    Text(cue)
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.lilac600)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .accessibilityLabel("Choose calendars")
            }

            if homeLayoutMode == "today" {
                todayContent
            } else {
                weekContent
            }
        }
        .padding(.vertical, 12)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black, lineWidth: 2))
        .boldShadow(.black)
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekHeader
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            ForEach(Array(weekDates.enumerated()), id: \.offset) { index, date in
                dayRow(date, index: index)
                if index < weekDates.count - 1 {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 2)
                }
            }

            weekFooterActions
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 2)
        }
    }

    private var todayContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(todayDateLabel)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .contentShape(Rectangle())
                .onTapGesture { dismissMealKeyboard() }

            if let today = todayInWeek {
                todayHero(today)
            }

            if !upcomingDates.isEmpty {
                Text("UP NEXT")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.black.opacity(0.45))
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(Array(upcomingDates.enumerated()), id: \.offset) { index, date in
                    upcomingRow(date)
                    if index < upcomingDates.count - 1 {
                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            }

            Button {
                homeLayoutMode = "week"
            } label: {
                Text("See full week")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
                    .boldShadow(.black, size: 2, radius: 12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .accessibilityLabel("See full week")

            weekFooterActions
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 2)
        }
    }

    private var todayDateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    private var todayInWeek: Date? {
        weekDates.first { Calendar.current.isDateInToday($0) }
    }

    private var upcomingDates: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return weekDates.filter { dayKey($0) > start }
    }

    private func todayHero(_ date: Date) -> some View {
        let key = dayKey(date)
        let lines = linesByDay[key] ?? [blankLine(for: key)]
        return VStack(alignment: .leading, spacing: 8) {
            Text("TODAY")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.terra500)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black, lineWidth: 1.5))

            ForEach(lines) { line in
                dinnerLine(line, on: key, dayName: "Today")
                    .id(scrollID(day: key, lineID: line.id))
            }

            if !homeEventLines(on: date).isEmpty {
                denseEvents(on: date, limit: 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.terra500)
                .frame(width: 4)
        }
    }

    private func upcomingRow(_ date: Date) -> some View {
        let meal = upcomingMealText(date)
        let nameFormatter = DateFormatter()
        nameFormatter.dateFormat = "EEE"
        let numberFormatter = DateFormatter()
        numberFormatter.dateFormat = "d"
        return Button {
            homeLayoutMode = "week"
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(nameFormatter.string(from: date).uppercased())
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.gray)
                    Text(numberFormatter.string(from: date))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                }
                .frame(width: 36, alignment: .leading)

                Text(meal)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let eventLine = homeEventLines(on: date).first {
                    compactEventLabel(eventLine)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(nameFormatter.string(from: date)) \(meal)")
    }

    private func upcomingMealText(_ date: Date) -> String {
        dinners(for: date)
            .compactMap { $0.title?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var layoutToggle: some View {
        HStack(spacing: 0) {
            modeChip("Week", on: homeLayoutMode != "today") {
                homeLayoutMode = "week"
            }
            modeChip("Today", on: homeLayoutMode == "today") {
                if weekOffset != 0 {
                    weekOffset = 0
                }
                homeLayoutMode = "today"
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black, lineWidth: 2))
    }

    private func modeChip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(on ? Color.white : Color.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(on ? Color.terra500 : Color.white)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) layout")
    }

    private var weekHeader: some View {
        HStack(spacing: 8) {
            weekChevron("chevron.left") { weekOffset -= 1 }

            HStack(spacing: 6) {
                if let household = dataManager.currentHousehold, dataManager.persistenceController.isShared(object: household) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.sky500)
                }
                Text(weekOffset == 0 ? "This week" : weekRangeLabel)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if weekOffset == 0 {
                    Text(weekRangeLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onTapGesture { dismissMealKeyboard() }

            if weekOffset != 0 {
                Button(action: { weekOffset = 0 }) {
                    Text("Today")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.lime100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }

            weekChevron("chevron.right") { weekOffset += 1 }
        }
    }

    private func weekChevron(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.black)
                .frame(width: 26, height: 26)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var weekFooterActions: some View {
        HStack(alignment: .top, spacing: 12) {
            weekActionButton(
                title: "Swipe to plan",
                fill: Color.terra500,
                ink: .white
            ) {
                showWeekPlanner = true
            }
            .disabled(weekDates.isEmpty)
            .opacity(weekDates.isEmpty ? 0.45 : 1)

            if !weekMeals.isEmpty {
                weekActionButton(
                    title: "Clear week",
                    fill: Color.peach500,
                    ink: .black
                ) {
                    showClearWeek = true
                }
            }
        }
    }

    private func weekActionButton(
        title: String,
        fill: Color,
        ink: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(fill)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black, lineWidth: 2))
                .boldShadow(.black, size: 3, radius: 12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func dayStripe(index: Int) -> Color {
        index.isMultiple(of: 2) ? Color.terra50 : Color.sky100.opacity(0.45)
    }

    private func dayRow(_ date: Date, index: Int) -> some View {
        let calendar = Calendar.current
        let key = dayKey(date)
        let isToday = calendar.isDateInToday(date)
        let dayFocused = isDayFocused(key)
        let lines = linesByDay[key] ?? [blankLine(for: key)]
        let dayEvents = events(for: date)
        let dayApple = appleEventsForDate(date)
        let dayName: String = {
            if isToday { return "Today" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }()
        let dayNumber: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "d"
            return formatter.string(from: date)
        }()

        let showEvents = !dayFocused && !(dayEvents.isEmpty && dayApple.isEmpty)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                if isToday {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.terra500)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black, lineWidth: 1.5))
                } else {
                    Text(dayName)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.gray)
                }
                Text(dayNumber)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
            }
            .frame(width: 48, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { dismissMealKeyboard() }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines) { line in
                    dinnerLine(line, on: key, dayName: dayName)
                        .id(scrollID(day: key, lineID: line.id))
                }
            }
            .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            if showEvents {
                denseEvents(on: date, limit: 2)
                    .layoutPriority(1)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .padding(.leading, isToday ? 10 : 12)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(dayStripe(index: index))
        .overlay(alignment: .leading) {
            if isToday {
                Rectangle()
                    .fill(Color.terra500)
                    .frame(width: 3)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: dayFocused)
    }

    private func dinnerLine(_ line: DinnerLine, on day: Date, dayName: String) -> some View {
        let focused = focusedField == .line(day: day, id: line.id)
        let linked = linkedRecipe(for: line)
        let text = line.text
        let matches = focused ? suggestions(matching: text, excluding: linked?.objectID) : []

        let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("", text: lineBinding(day: day, lineID: line.id), axis: .vertical)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(linked == nil ? Color.black : Color.terra600)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.leading)
                        .lineLimit(focused ? 3 : 1)
                        .truncationMode(.tail)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .focused($focusedField, equals: .line(day: day, id: line.id))
                        .submitLabel(submitLabel(for: line, on: day))
                        .onSubmit { submitLine(day: day, lineID: line.id) }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .opacity(focused || shown.isEmpty ? 1 : 0)
                        .accessibilityLabel("\(dayName) dinner")
                    if !focused && !shown.isEmpty {
                        Text(shown)
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(linked == nil ? Color.black : Color.terra600)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                focusedField = .line(day: day, id: line.id)
                            }
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if focused && !shown.isEmpty {
                    Button {
                        clearLine(day: day, lineID: line.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.black.opacity(0.45))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear dinner")
                }
            }

            if focused || shown.isEmpty {
                Rectangle()
                    .fill(focused ? Color.black : Color.black.opacity(0.12))
                    .frame(height: focused ? 2 : 1)
            }

            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(matches, id: \.objectID) { recipe in
                        Button {
                            applyRecipe(recipe, on: day, lineID: line.id)
                        } label: {
                            HStack(spacing: 8) {
                                if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 1.5))
                                }
                                Text(recipe.name ?? "")
                                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.black)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.terra100)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Every home event chip uses this width so the week column lines up.
    private static let eventPillWidth: CGFloat = 144

    private struct HomeEventLine: Identifiable {
        let id: String
        let timeLabel: String
        let title: String
        let sortDate: Date
        /// EventKit calendar color. Nil keeps the cream chip.
        let calendarColor: UIColor?
        let open: () -> Void

        /// Start time plus the event name. The whole line truncates inside the pill.
        var sideText: String {
            if timeLabel.isEmpty { return title }
            if title.isEmpty { return timeLabel }
            return "\(timeLabel) · \(title)"
        }

        var detailText: String { sideText }
    }

    private func eventChipColors(_ calendarColor: UIColor?) -> (fill: Color, ink: Color) {
        guard let calendarColor else {
            return (Color.lime100, .black)
        }
        let ink: Color = calendarColor.chipInkIsWhite ? .white : .black
        return (Color(uiColor: calendarColor), ink)
    }

    /// Fixed-width chip. Calendar color tints the fill; cream is the fallback.
    private func compactEventLabel(_ line: HomeEventLine) -> some View {
        let colors = eventChipColors(line.calendarColor)
        return Text(line.sideText)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(colors.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: Self.eventPillWidth, alignment: .leading)
            .background(colors.fill)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 1.5))
            .accessibilityLabel(line.sideText)
    }

    private func eventTimeLabel(date: Date?, allDay: Bool) -> String {
        if allDay { return "All day" }
        return eventTime(date, allDay: false) ?? ""
    }

    private func homeEventLines(on date: Date) -> [HomeEventLine] {
        var lines: [HomeEventLine] = []
        for event in events(for: date) {
            let title = event.title ?? "Event"
            lines.append(HomeEventLine(
                id: event.objectID.uriRepresentation().absoluteString,
                timeLabel: eventTimeLabel(date: event.date, allDay: event.isAllDay),
                title: title,
                sortDate: event.date ?? .distantPast,
                calendarColor: uiColor(fromHex: event.color)
            ) {
                selectedAppleEvent = nil
                selectedEvent = event
            })
        }
        for event in appleEventsForDate(date) {
            lines.append(HomeEventLine(
                id: event.id,
                timeLabel: eventTimeLabel(date: event.startDate, allDay: event.isAllDay),
                title: event.title,
                sortDate: event.startDate,
                calendarColor: event.calendarColor
            ) {
                selectedEvent = nil
                selectedAppleEvent = event
            })
        }
        return lines.sorted {
            if $0.sortDate != $1.sortDate { return $0.sortDate < $1.sortDate }
            return $0.id < $1.id
        }
    }

    /// `limit` caps the visible lines until that day is expanded. `nil` shows every line.
    private func denseEvents(on date: Date, limit: Int?) -> some View {
        let key = dayKey(date)
        let lines = homeEventLines(on: date).filter { !$0.sideText.isEmpty }
        let expanded = limit == nil || expandedEventDays.contains(key)
        let shown = expanded ? lines : Array(lines.prefix(limit ?? lines.count))
        let hidden = lines.count - shown.count
        return VStack(alignment: .trailing, spacing: 4) {
            ForEach(shown) { line in
                Button(action: line.open) {
                    compactEventLabel(line)
                }
                .buttonStyle(.plain)
                .frame(width: Self.eventPillWidth, alignment: .leading)
            }
            if hidden > 0 {
                Button {
                    expandedEventDays.insert(key)
                } label: {
                    Text("+\(hidden)")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.lilac600)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(hidden) more events")
            }
        }
        .frame(width: Self.eventPillWidth, alignment: .trailing)
    }

    private func uiColor(fromHex token: String?) -> UIColor? {
        guard var hex = token?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let red = CGFloat((value >> 16) & 0xFF) / 255
        let green = CGFloat((value >> 8) & 0xFF) / 255
        let blue = CGFloat(value & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: 1)
    }

    /// Drops the keyboard unless this same tap moved focus into a meal field.
    private func dismissMealKeyboard() {
        dismissMealKeyboard(fromStamp: mealFocusStamp)
    }

    private func dismissMealKeyboard(fromStamp stamp: Int) {
        DispatchQueue.main.async {
            guard stamp == mealFocusStamp else { return }
            if focusedField != nil {
                focusedField = nil
            }
            KeyboardDismiss.resign()
        }
    }

    private static func textInputIsFirstResponder() -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) {
            if let responder = window.currentFirstResponder, responder.isInsideTextInput {
                return true
            }
        }
        return false
    }

    private func eventTime(_ date: Date?, allDay: Bool) -> String? {
        guard let date, !allDay else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private var clearWeekPrompt: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { showClearWeek = false }

            VStack(spacing: 18) {
                Text("Clear this week?")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text("Meals on this week will be removed. Events stay.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.black.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Button {
                        showClearWeek = false
                    } label: {
                        Text("Keep meals")
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
                        clearWeekMeals()
                    } label: {
                        Text("Clear week")
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

    private func clearWeekMeals() {
        suppressCommit = true
        focusedField = nil
        showClearWeek = false
        guard let monday = weekDates.first else {
            suppressCommit = false
            return
        }
        let meals = dataManager.fetchWeekMealPlans(from: monday)
        dataManager.deleteMealPlans(meals)
        loadData()
        DispatchQueue.main.async {
            suppressCommit = false
        }
    }

    private func lineBinding(day: Date, lineID: String) -> Binding<String> {
        Binding(
            get: { linesByDay[day]?.first { $0.id == lineID }?.text ?? "" },
            set: { newValue in
                if suppressCommit { return }
                let submitted = newValue.contains { $0 == "\n" || $0 == "\r" }
                let cleaned = newValue
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                if submitted, skipNextCommitID == lineID { return }
                guard var lines = linesByDay[day],
                      let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
                lines[index].text = cleaned
                if let recipeID = lines[index].recipeID,
                   let recipe = recipes.first(where: { $0.objectID == recipeID }),
                   !namesMatch(recipe.name, cleaned) {
                    lines[index].recipeID = nil
                }
                if !submitted && cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines[index].recipeID = nil
                    if let mealID = lines[index].mealID,
                       let meal = meal(mealID, on: day) {
                        lines[index].mealID = nil
                        DayDinnerStore.remove(meal, dataManager: dataManager)
                    }
                }
                linesByDay[day] = lines
                if submitted {
                    submitLine(day: day, lineID: lineID)
                }
            }
        )
    }

    private func suggestions(matching text: String, excluding linkedID: NSManagedObjectID?) -> [Recipe] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        return recipes
            .filter { recipe in
                let name = (recipe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, recipe.objectID != linkedID else { return false }
                let tags = (recipe.tags ?? "").lowercased()
                return name.lowercased().contains(needle) || tags.contains(needle)
            }
            .sorted { a, b in
                let rankA = matchRank(a, query: needle)
                let rankB = matchRank(b, query: needle)
                if rankA != rankB { return rankA < rankB }
                if a.isFavorite != b.isFavorite { return a.isFavorite }
                return (a.name ?? "").localizedCaseInsensitiveCompare(b.name ?? "") == .orderedAscending
            }
            .prefix(5)
            .map { $0 }
    }

    private func matchRank(_ recipe: Recipe, query: String) -> Int {
        let name = (recipe.name ?? "").lowercased()
        if name == query { return 0 }
        if name.hasPrefix(query) { return 1 }
        if name.contains(query) { return 2 }
        return 3
    }

    private func linkedRecipe(for line: DinnerLine) -> Recipe? {
        let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = line.recipeID else { return nil }
        guard let recipe = recipes.first(where: { $0.objectID == id }) else { return nil }
        return namesMatch(recipe.name, trimmed) ? recipe : nil
    }

    private func namesMatch(_ name: String?, _ text: String) -> Bool {
        (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(text) == .orderedSame
    }

    private func savedTitle(of recipe: Recipe) -> String? {
        let title = (recipe.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private func scrollID(day: Date, lineID: String) -> String {
        "dinner-\(day.timeIntervalSince1970)-\(lineID)"
    }

    private func blankID(for day: Date) -> String {
        "blank-\(day.timeIntervalSince1970)"
    }

    private func blankLine(for day: Date) -> DinnerLine {
        DinnerLine(id: blankID(for: day), mealID: nil, text: "", recipeID: nil)
    }

    private func lineID(for meal: MealPlan) -> String {
        meal.objectID.uriRepresentation().absoluteString
    }

    private func isDayFocused(_ day: Date) -> Bool {
        if case .line(let focusedDay, _) = focusedField {
            return focusedDay == day
        }
        return false
    }

    private func meal(_ id: NSManagedObjectID, on day: Date) -> MealPlan? {
        dinners(for: day).first { $0.objectID == id }
            ?? DayDinnerStore.dinners(on: day, dataManager: dataManager).first { $0.objectID == id }
    }

    private func submitLabel(for line: DinnerLine, on day: Date) -> SubmitLabel {
        if isLastWeekDay(day), line.id == blankID(for: day) { return .done }
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty, isLastWeekDay(day) { return .done }
        return .next
    }

    private func isLastWeekDay(_ date: Date) -> Bool {
        guard let last = weekDates.last else { return true }
        return Calendar.current.isDate(date, inSameDayAs: last)
    }

    private func submitLine(day: Date, lineID: String) {
        let text = (linesByDay[day]?.first { $0.id == lineID }?.text ?? "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            focusNextDay(after: day)
            return
        }
        commitLine(day: day, lineID: lineID)
        skipNextCommitID = lineID
        // The new row on the last day uses the blank id. Focusing that same id
        // never blurs, so Return stays in the field and the events column stays hidden.
        if isLastWeekDay(day), lineID == blankID(for: day) {
            focusedField = nil
            KeyboardDismiss.resign()
            return
        }
        focusedField = .line(day: day, id: blankID(for: day))
    }

    private func focusNextDay(after day: Date) {
        guard let index = weekDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: day) }),
              index + 1 < weekDates.count else {
            focusedField = nil
            return
        }
        let next = dayKey(weekDates[index + 1])
        let id = linesByDay[next]?.first?.id ?? blankID(for: next)
        focusedField = .line(day: next, id: id)
    }

    private func applyRecipe(_ recipe: Recipe, on day: Date, lineID: String) {
        guard let title = savedTitle(of: recipe) else { return }
        guard var lines = linesByDay[day],
              let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        lines[index].text = title
        lines[index].recipeID = recipe.objectID
        linesByDay[day] = lines
        skipNextCommitID = lineID
        let meal = lines[index].mealID.flatMap { meal($0, on: day) }
        if let meal {
            DayDinnerStore.update(meal, title: title, recipe: recipe, dataManager: dataManager)
        } else {
            let created = DayDinnerStore.append(on: day, title: title, recipe: recipe, dataManager: dataManager)
            lines[index].mealID = created.objectID
            lines[index].text = ""
            lines[index].recipeID = nil
            linesByDay[day] = lines
        }
        suppressBlankEcho[day] = title
        focusedField = nil
        reloadMeals()
    }

    private func clearLine(day: Date, lineID: String) {
        guard var lines = linesByDay[day],
              let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        // Hold commits until after the field blurs, so leaving focus cannot save the title again.
        suppressCommit = true
        if let mealID = lines[index].mealID, let meal = meal(mealID, on: day) {
            DayDinnerStore.remove(meal, dataManager: dataManager)
        }
        lines[index].text = ""
        lines[index].recipeID = nil
        lines[index].mealID = nil
        linesByDay[day] = lines
        focusedField = nil
        KeyboardDismiss.resign()
        reloadMeals()
        DispatchQueue.main.async {
            suppressCommit = false
        }
    }

    private func commitLine(day: Date, lineID: String) {
        if suppressCommit { return }
        if skipNextCommitID == lineID {
            skipNextCommitID = nil
            return
        }
        guard var lines = linesByDay[day],
              let index = lines.firstIndex(where: { $0.id == lineID }) else { return }
        let line = lines[index]
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            // The placeholder can briefly carry a meal id after save. Do not delete that dinner.
            if lineID != blankID(for: day) {
                if let mealID = line.mealID, let meal = meal(mealID, on: day) {
                    DayDinnerStore.remove(meal, dataManager: dataManager)
                }
                reloadMeals()
            }
            return
        }
        let recipe = linkedRecipe(for: line)
        let title = recipe.flatMap { savedTitle(of: $0) } ?? text
        lines[index].text = title
        lines[index].recipeID = recipe?.objectID
        linesByDay[day] = lines
        if let mealID = line.mealID, let meal = meal(mealID, on: day) {
            let sameTitle = (meal.title ?? "") == title
            let sameRecipe = meal.recipe?.objectID == recipe?.objectID
            if sameTitle && sameRecipe { return }
            DayDinnerStore.update(meal, title: title, recipe: recipe, dataManager: dataManager)
        } else {
            let created = DayDinnerStore.append(on: day, title: title, recipe: recipe, dataManager: dataManager)
            if var fresh = linesByDay[day], let blankIndex = fresh.firstIndex(where: { $0.id == lineID }) {
                fresh[blankIndex].mealID = created.objectID
                fresh[blankIndex].text = ""
                fresh[blankIndex].recipeID = nil
                linesByDay[day] = fresh
            }
            suppressBlankEcho[day] = title
        }
        reloadMeals()
    }

    private func loadData() {
        guard let monday = weekDates.first else { return }
        recipes = dataManager.fetchRecipes()
        weekMeals = dataManager.fetchWeekMealPlans(from: monday)
        weekEvents = dataManager.fetchWeekEvents(from: monday)
        syncLines()
    }

    /// Reload Apple events after the saved EventKit grant and calendar
    /// selection are applied. Does not rebuild dinner lines.
    private func refreshAppleEvents() {
        Task {
            await calendarSyncManager.prepareForReading()
            guard let monday = weekDates.first else { return }
            appleEvents = calendarSyncManager.fetchWeekEvents(from: monday)
        }
    }

    private func reloadMeals() {
        guard let monday = weekDates.first else { return }
        let focus = focusedField
        weekMeals = dataManager.fetchWeekMealPlans(from: monday)
        syncLines(keeping: focus)
        if focusedField != focus {
            focusedField = focus
        }
    }

    private func syncLines(keeping focus: DinnerField? = nil) {
        let protected = focus ?? focusedField
        var next: [Date: [DinnerLine]] = [:]
        for date in weekDates {
            let key = dayKey(date)
            var lines = dinners(for: date).map { meal in
                DinnerLine(
                    id: lineID(for: meal),
                    mealID: meal.objectID,
                    text: meal.title ?? "",
                    recipeID: meal.recipe?.objectID
                )
            }
            if case .line(let focusedDay, let lineID) = protected, focusedDay == key,
               let draft = linesByDay[key]?.first(where: { $0.id == lineID }),
               let index = lines.firstIndex(where: { $0.id == lineID }) {
                lines[index].text = draft.text
                lines[index].recipeID = draft.recipeID
            }
            let lastHasText = lines.last.map {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            } ?? false
            if lines.isEmpty || lastHasText {
                var blank = blankLine(for: key)
                if case .line(let focusedDay, let lineID) = protected,
                   focusedDay == key, lineID == blank.id,
                   let draft = linesByDay[key]?.first(where: { $0.id == lineID }) {
                    let draftText = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let echoed = suppressBlankEcho[key].map { namesMatch($0, draftText) } ?? false
                    let alreadyListed = lines.contains { namesMatch($0.text, draftText) }
                    if !echoed && !alreadyListed {
                        blank.text = draft.text
                        blank.recipeID = draft.recipeID
                    }
                }
                if suppressBlankEcho[key] != nil {
                    suppressBlankEcho[key] = nil
                }
                lines.append(blank)
            }
            next[key] = lines
        }
        linesByDay = next
    }
}

struct CalendarHeaderRow: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("DATE")
                .frame(width: 56, alignment: .leading)
                .foregroundStyle(.gray.opacity(0.6))
            Text("MEALS")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.terra500)
            Text("EVENTS")
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(Color.lilac500)
        }
        .font(.system(size: 10, weight: .heavy, design: .rounded))
        .tracking(1)
    }
}

struct CalDayRow: View {
    let date: Date
    let meals: [MealPlan]
    let events: [CalendarEvent]
    var appleEvents: [AppleCalendarEvent] = []
    let onMealTap: (MealPlan) -> Void
    var onRecipeViewTap: ((Recipe) -> Void)? = nil
    let onAddMealTap: () -> Void
    var onMealDelete: ((MealPlan) -> Void)? = nil
    var onEventTap: ((CalendarEvent) -> Void)? = nil
    var onAddEventTap: (() -> Void)? = nil
    var onAppleEventTap: ((AppleCalendarEvent) -> Void)? = nil

    private var allEventCount: Int { events.count + appleEvents.count }

    private var calendar: Calendar { Calendar.current }
    private var isToday: Bool { calendar.isDateInToday(date) }
    private var isPast: Bool {
        calendar.startOfDay(for: date) < calendar.startOfDay(for: Date())
    }
    private var isFaded: Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 // Sat/Sun
    }

    private var dayString: String {
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: date)
    }
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
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

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Date column
            VStack(alignment: .leading, spacing: 0) {
                Text(isToday ? "Today" : dayString)
                    .font(.system(size: isToday ? 12 : 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? Color.lime500 : (isFaded ? .gray.opacity(0.4) : .gray))
                    .textCase(.uppercase)
                Text(dateString)
                    .font(.system(size: isToday ? 24 : 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(isToday ? Color(red: 0.30, green: 0.52, blue: 0.15) : (isFaded ? .gray.opacity(0.4) : .primary))
            }
            .padding(.top, isToday ? 4 : 0)
            .frame(width: 56, alignment: .leading)

            // Meal column
            VStack(alignment: .leading, spacing: 6) {
                if meals.isEmpty {
                    // Add meal button
                    Button(action: onAddMealTap) {
                        dashedAddButton(
                            color1: isToday ? Color.terra200 : Color.gray.opacity(0.2),
                            fill: isToday ? Color.terra50 : Color.gray.opacity(0.03),
                            iconColor: isToday ? Color.terra400 : Color.gray.opacity(0.3)
                        )
                    }
                    .buttonStyle(.plain)
                } else if isToday || meals.count <= 2 {
                    // Show all meals with edit
                    ForEach(meals, id: \.objectID) { meal in
                        mealPillSplit(
                            meal: meal,
                            text: "\(mealEmoji(for: meal.mealType ?? "")) \(meal.title ?? "Untitled")",
                            filled: isToday && meal == meals.first
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
                    // Add more button for today
                    if isToday {
                        Button(action: onAddMealTap) {
                            dashedAddButton(
                                color1: Color.terra200,
                                fill: Color.terra50,
                                iconColor: Color.terra400
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Compact: show first meal + count
                    if let firstMeal = meals.first {
                        Button(action: { onMealTap(firstMeal) }) {
                            mealPill(
                                "\(mealEmoji(for: firstMeal.mealType ?? "")) \(firstMeal.title ?? "")",
                                filled: false
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let onDelete = onMealDelete {
                                Button(role: .destructive) {
                                    onDelete(firstMeal)
                                } label: {
                                    Label("Delete Meal", systemImage: "trash")
                                }
                            }
                        }
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.terra500)
                            .frame(width: 6, height: 6)
                        Text("+\(meals.count - 1) more")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer().frame(width: 12)

            // Event column
            VStack(alignment: .leading, spacing: 6) {
                if allEventCount == 0 {
                    Button(action: { onAddEventTap?() }) {
                        dashedAddButton(
                            color1: isToday ? Color.lilac200 : Color.gray.opacity(0.2),
                            fill: isToday ? Color.lilac100 : Color.gray.opacity(0.03),
                            iconColor: isToday ? Color.lilac400 : Color.gray.opacity(0.3)
                        )
                    }
                    .buttonStyle(.plain)
                } else if isToday || allEventCount <= 2 {
                    // OurWeek events
                    ForEach(events, id: \.objectID) { event in
                        Button(action: { onEventTap?(event) }) {
                            eventPill(
                                event.title ?? "Event",
                                filled: isToday && event == events.first && appleEvents.isEmpty
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    // Apple Calendar events
                    ForEach(appleEvents) { appleEvent in
                        Button(action: { onAppleEventTap?(appleEvent) }) {
                            appleEventPill(appleEvent, filled: isToday && events.isEmpty && appleEvent.id == appleEvents.first?.id)
                        }
                        .buttonStyle(.plain)
                    }
                    if isToday {
                        Button(action: { onAddEventTap?() }) {
                            dashedAddButton(
                                color1: Color.lilac200,
                                fill: Color.lilac100,
                                iconColor: Color.lilac400
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    // Show first item (prefer OurWeek, then Apple)
                    if let first = events.first {
                        Button(action: { onEventTap?(first) }) {
                            eventPill(first.title ?? "Event", filled: false)
                        }
                        .buttonStyle(.plain)
                    } else if let firstApple = appleEvents.first {
                        appleEventPill(firstApple, filled: false)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(Color.lilac500)
                            .frame(width: 6, height: 6)
                        Text("+\(allEventCount - 1) more")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, isToday ? 16 : 8)
        .padding(.horizontal, 16)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.lime100.opacity(0.6))
                    .overlay(alignment: .leading) {
                        UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 0, topTrailingRadius: 0)
                            .fill(Color.lime500)
                            .frame(width: 6)
                    }
            }
        }
    }

    // MARK: - Pill Helpers

    @ViewBuilder
    func mealPill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(filled ? .white : Color.terra600)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(filled ? Color.terra500 : Color.terra100)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(filled ? Color.terra600 : Color.terra200, lineWidth: 1)
            )
    }

    @ViewBuilder
    func mealPillSplit(meal: MealPlan, text: String, filled: Bool) -> some View {
        HStack(spacing: 0) {
            // Text area — tapping opens recipe if available, otherwise edit
            Button(action: {
                if let recipe = meal.recipe {
                    onRecipeViewTap?(recipe)
                } else {
                    onMealTap(meal)
                }
            }) {
                Text(text)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .foregroundStyle(filled ? .white : Color.terra600)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            // Pencil — opens add meal sheet to swap/replace
            Button(action: { onAddMealTap() }) {
                Image(systemName: "pencil")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(filled ? .white.opacity(0.9) : Color.terra600.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background(filled ? Color.terra500 : Color.terra100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(filled ? Color.terra600 : Color.terra200, lineWidth: 1)
        )
        .if(filled) { view in
            view.shadow(color: Color.terra500.opacity(0.3), radius: 2, x: 0, y: 1)
        }
    }

    @ViewBuilder
    func mealPillWithEdit(_ text: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "pencil")
                .font(.system(size: 9, weight: .medium))
                .opacity(filled ? 0.9 : 0.6)
        }
        .foregroundStyle(filled ? .white : Color.terra600)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(filled ? Color.terra500 : Color.terra100)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(filled ? Color.terra600 : Color.terra200, lineWidth: 1)
        )
        .if(filled) { view in
            view.shadow(color: Color.terra500.opacity(0.3), radius: 2, x: 0, y: 1)
        }
    }

    @ViewBuilder
    func eventPill(_ text: String, filled: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(filled ? .white : Color.lilac600)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(filled ? Color.lilac500 : Color.lilac100)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(filled ? Color.lilac600 : Color.lilac200, lineWidth: 1)
            )
            .if(filled) { view in
                view.boldShadowSm(Color.lilac600, radius: 6)
            }
    }

    @ViewBuilder
    func appleEventPill(_ event: AppleCalendarEvent, filled: Bool) -> some View {
        HStack(spacing: 0) {
            // Colored bar from Apple Calendar color
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(uiColor: event.calendarColor))
                .frame(width: 4)
                .padding(.vertical, 2)
            
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(filled ? .white.opacity(0.8) : Color(uiColor: event.calendarColor))
                Text(event.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
        }
        .foregroundStyle(filled ? .white : Color.lilac600)
        .padding(.vertical, 4)
        .background(filled ? Color(uiColor: event.calendarColor).opacity(0.85) : Color(uiColor: event.calendarColor).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(uiColor: event.calendarColor).opacity(filled ? 0.9 : 0.3), lineWidth: 1)
        )
    }

    @ViewBuilder
    func dashedAddButton(color1: Color, fill: Color, iconColor: Color) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 2, dash: [5, 4])
            )
            .foregroundStyle(color1)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(fill)
            )
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            )
    }

    @ViewBuilder
    func dashedPlaceholder() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                style: StrokeStyle(lineWidth: 2, dash: [5, 4])
            )
            .foregroundStyle(Color.gray.opacity(0.15))
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.03))
            )
    }
}

// Conditional modifier helper
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Today's To-Do Section
struct TodoSection: View {
    @Binding var triggerAdd: Bool
    
    @AppStorage("homeTodosWrapper") private var todosWrapper = TodosWrapper(todos: [
        TodoTask(title: "Morning Pilates", subtitle: "7:30 AM • Studio", subtitleColorHex: "terra"),
        TodoTask(title: "Grocery Run", subtitle: "Whole Foods", subtitleColorHex: "lilac")
    ])
    
    private var todos: [TodoTask] {
        get { todosWrapper.todos }
    }

    @State private var isAddingTodo = false
    @State private var newTodoTitle = ""
    @FocusState private var isNewTodoFocused: Bool
    
    @State private var selectedTodo: TodoTask?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text("Today's To-Do")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .tracking(-0.3)
                Spacer()
                Button(action: {
                    isAddingTodo = true
                    // Small delay to ensure the TextField is in the hierarchy before focusing
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewTodoFocused = true
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Color.lilac600)
                }
            }

            // Card
            VStack(spacing: 0) {
                if todos.isEmpty && !isAddingTodo {
                    Text("No tasks yet. Add one!")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.gray)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(todos.enumerated()), id: \.element.id) { index, todo in
                        TodoItem(
                            todo: binding(for: todo),
                            onTap: {
                                selectedTodo = todo
                            },
                            onDelete: {
                                var mutated = todos
                                mutated.removeAll { $0.id == todo.id }
                                todosWrapper = TodosWrapper(todos: mutated)
                            }
                        )
                        
                        if index < todos.count - 1 || isAddingTodo {
                            Divider().background(Color.terra100)
                        }
                    }
                }
                
                if isAddingTodo {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .stroke(Color.terra300, lineWidth: 2)
                                .frame(width: 24, height: 24)
                        }
                        
                        TextField("New task...", text: $newTodoTitle)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .focused($isNewTodoFocused)
                            .onSubmit {
                                submitNewTodo()
                            }
                            .submitLabel(.done)
                        
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .padding(20)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.terra500, lineWidth: 2)
            )
            .boldShadow(Color.terra500)
        }
        .padding(.horizontal, 24)
        .sheet(item: $selectedTodo) { todo in
            EditTodoSheet(
                todo: todo,
                onSave: { updatedTodo in
                    if let index = todos.firstIndex(where: { $0.id == updatedTodo.id }) {
                        var mutated = todos
                        mutated[index] = updatedTodo
                        todosWrapper = TodosWrapper(todos: mutated)
                    }
                },
                onDelete: { deletedTodo in
                    var mutated = todos
                    mutated.removeAll { $0.id == deletedTodo.id }
                    todosWrapper = TodosWrapper(todos: mutated)
                }
            )
            .presentationDetents([.fraction(0.45), .medium])
            .presentationDragIndicator(.visible)
        }
        .onChange(of: triggerAdd) { _, newValue in
            if newValue {
                triggerAdd = false
                isAddingTodo = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isNewTodoFocused = true
                }
            }
        }
    }
    
    private func submitNewTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespaces)
        if !title.isEmpty {
            let colors = ["terra", "lilac", "lime", "sky"]
            let color = colors[todos.count % colors.count]
            let newTask = TodoTask(title: title, subtitle: "", subtitleColorHex: color)
            var mutated = todos
            mutated.append(newTask)
            todosWrapper = TodosWrapper(todos: mutated)
        }
        newTodoTitle = ""
        isAddingTodo = false
        isNewTodoFocused = false
    }
    
    private func binding(for todo: TodoTask) -> Binding<TodoTask> {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else {
            return .constant(todo)
        }
        return Binding<TodoTask>(
            get: { todosWrapper.todos[index] },
            set: { newValue in
                var mutated = todosWrapper.todos
                mutated[index] = newValue
                todosWrapper = TodosWrapper(todos: mutated)
            }
        )
    }
}

struct TodoItem: View {
    @Binding var todo: TodoTask
    let onTap: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var offset: CGFloat = 0
    @GestureState private var isDragging = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete background (revealed on swipe)
            if onDelete != nil {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            onDelete?()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 16, weight: .bold))
                            Text("Delete")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(width: 80)
                    }
                }
                .background(Color.red)
            }

            // Foreground content
            HStack(spacing: 12) {
                // Circular checkbox
                ZStack {
                    Circle()
                        .stroke(todo.isChecked ? Color.terra500 : Color.terra300, lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(todo.isChecked ? Color.terra500 : Color.clear)
                        )

                    if todo.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .onTapGesture {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    todo.isChecked.toggle()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(todo.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(todo.isChecked ? .gray.opacity(0.4) : .primary)
                        .strikethrough(todo.isChecked, color: .gray.opacity(0.4))
                        .lineLimit(1)
                    if !todo.subtitle.isEmpty {
                        Text(todo.subtitle)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(todo.isChecked ? .gray.opacity(0.3) : todo.subtitleColor)
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .strikethrough(todo.isChecked, color: .gray.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if offset < 0 {
                        withAnimation(.spring()) { offset = 0 }
                    } else {
                        onTap()
                    }
                }

                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 2)
            .background(Color.cardWhite)
            .offset(x: offset)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 15)
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if onDelete != nil {
                        if value.translation.width < 0 {
                            offset = max(value.translation.width, -100)
                        } else if offset < 0 {
                            offset = min(0, offset + value.translation.width)
                        }
                    }
                }
                .onEnded { value in
                    if onDelete != nil {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if offset < -50 {
                                offset = -80
                            } else {
                                offset = 0
                            }
                        }
                    }
                }
        )
        .clipped()
    }
}

// MARK: - Models for To-Do List

struct TodoTask: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String = ""
    var subtitleColorHex: String = "terra"
    var isChecked: Bool = false

    var subtitleColor: Color {
        switch subtitleColorHex {
        case "terra": return Color.terra500
        case "lilac": return Color.lilac500
        case "lime": return Color.lime500
        case "sky": return Color.sky500
        default: return Color.terra500
        }
    }
}

struct TodosWrapper: RawRepresentable {
    var todos: [TodoTask]
    
    init(todos: [TodoTask]) {
        self.todos = todos
    }
    
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([TodoTask].self, from: data) else {
            return nil
        }
        self.todos = result
    }
    
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(todos),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return result
    }
}

struct EditTodoSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @State var todo: TodoTask
    var onSave: (TodoTask) -> Void
    var onDelete: (TodoTask) -> Void
    
    let colors = ["terra", "lilac", "lime", "sky"]
    
    private func colorFor(hex: String) -> Color {
        switch hex {
        case "terra": return Color.terra500
        case "lilac": return Color.lilac500
        case "lime": return Color.lime500
        case "sky": return Color.sky500
        default: return Color.terra500
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("EDIT TASK")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.terra500)
                Spacer()
                Button(action: {
                    onDelete(todo)
                    dismiss()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.top, 8)

            // Form
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Title")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    TextField("What needs to be done?", text: $todo.title)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(16)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Subtitle")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.8))
                        .textCase(.uppercase)
                        .tracking(0.5)
                    
                    TextField("e.g. 7:30 AM • Studio", text: $todo.subtitle)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(16)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
                
                // Color Picker for Subtitle
                HStack(spacing: 16) {
                    ForEach(colors, id: \.self) { hex in
                        Button(action: { todo.subtitleColorHex = hex }) {
                            Circle()
                                .fill(colorFor(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary, lineWidth: todo.subtitleColorHex == hex ? 3 : 0)
                                        .padding(-4)
                                )
                                .padding(4)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .opacity(todo.subtitle.isEmpty ? 0.4 : 1.0)
            }

            Spacer(minLength: 0)

            // Save Button
            Button(action: {
                onSave(todo)
                dismiss()
            }) {
                Text("Save Changes")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.terra500)
                    )
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}
// MARK: - Models for Daily Goals

struct DailyGoal: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var unit: String
    var unitShort: String
    var icon: String
    var rangeLower: Double
    var rangeUpper: Double
    var step: Double
    var current: Double = 0
    var target: Double
    var colorTheme: String = "sky"
    var isArchived: Bool = false
    
    var ringColor: Color { colorFor(hex: colorTheme, variant: "500") }
    var ringTrack: Color { colorFor(hex: colorTheme, variant: "100") }
    var borderColor: Color { colorFor(hex: colorTheme, variant: "400") }
    var shadowColor: Color { colorFor(hex: colorTheme, variant: "400") }
    
    private func colorFor(hex: String, variant: String) -> Color {
        switch hex {
        case "terra": return variant == "100" ? Color.terra100 : (variant == "400" ? Color.terra400 : Color.terra500)
        case "lilac": return variant == "100" ? Color.lilac100 : (variant == "400" ? Color.lilac400 : Color.lilac500)
        case "lime": return variant == "100" ? Color.lime100 : (variant == "400" ? Color.lime500 : Color.lime500) // Lime doesn't have 400? Using 500 for border/shadow
        case "sky": return variant == "100" ? Color.sky100 : (variant == "400" ? Color.sky400 : Color.sky500)
        default: return Color.sky500
        }
    }
}

struct DailyGoalsWrapper: RawRepresentable {
    var goals: [DailyGoal]
    
    init(goals: [DailyGoal]) {
        self.goals = goals
    }
    
    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode([DailyGoal].self, from: data) else {
            return nil
        }
        self.goals = result
    }
    
    var rawValue: String {
        guard let data = try? JSONEncoder().encode(goals),
              let result = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return result
    }
}

// MARK: - Daily Goals Section
struct DailyGoalsSection: View {
    @AppStorage("userDailyGoals") private var goalsWrapper: DailyGoalsWrapper = DailyGoalsWrapper(goals: [])
    @AppStorage("goalsLastResetDate") private var goalsLastResetDate: String = ""

    // Legacy data for migration
    @AppStorage("waterCurrent") private var legacyWaterCurrent: Double = 0
    @AppStorage("stepsCurrent") private var legacyStepsCurrent: Double = 0
    @AppStorage("sleepCurrent") private var legacySleepCurrent: Double = 0
    @AppStorage("waterTarget") private var legacyWaterTarget: Double = 2.0
    @AppStorage("stepsTarget") private var legacyStepsTarget: Double = 10.0
    @AppStorage("sleepTarget") private var legacySleepTarget: Double = 8.0
    @AppStorage("goalsMigratedToDynamic") private var hasMigrated: Bool = false

    @State private var showEditSheet = false
    @State private var showAddSheet = false
    @State private var editingGoal: DailyGoal? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text("DAILY GOALS")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .tracking(1)

                Spacer()

                // Badge pill
                Text("TAP TO LOG • HOLD TO EDIT")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color(red: 0.2, green: 0.2, blue: 0.25))
                    )
            }
            .padding(.horizontal, 24)

            // Horizontal scroll cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(goalsWrapper.goals.filter { !$0.isArchived }) { goal in
                        GoalRingCard(
                            goal: goal,
                            cardBg: Color.cardWhite,
                            onTap: { logTap(for: goal) },
                            onLongPress: {
                                editingGoal = goal
                                showEditSheet = true
                            }
                        )
                    }
                    
                    // Add Goal Button
                    Button(action: { showAddSheet = true }) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundStyle(.gray.opacity(0.3))
                                Image(systemName: "plus")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.gray.opacity(0.5))
                            }
                            .frame(width: 96, height: 96)
                            
                            Text("New Goal")
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.gray.opacity(0.6))
                        }
                        .padding(.vertical, 20)
                        .padding(.horizontal, 16)
                        .frame(width: 160)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color.gray.opacity(0.1), lineWidth: 2)
                        )
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .sheet(item: $editingGoal) { goal in
            QuickEditGoalSheet(
                goal: goal,
                onSave: { updatedGoal in
                    if let index = goalsWrapper.goals.firstIndex(where: { $0.id == updatedGoal.id }) {
                        goalsWrapper.goals[index] = updatedGoal
                    }
                },
                onDelete: { deletedGoal in
                    if let index = goalsWrapper.goals.firstIndex(where: { $0.id == deletedGoal.id }) {
                        goalsWrapper.goals[index].isArchived = true
                    }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAddSheet) {
            AddGoalSheet(onAdd: { newGoal in
                goalsWrapper.goals.append(newGoal)
            })
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            runMigrationIfNeeded()
            resetIfNewDay()
        }
    }
    
    private func logTap(for goal: DailyGoal) {
        if let index = goalsWrapper.goals.firstIndex(where: { $0.id == goal.id }) {
            var updated = goalsWrapper.goals[index]
            updated.current = min(updated.current + updated.step, updated.target)
            goalsWrapper.goals[index] = updated
        }
    }

    private func runMigrationIfNeeded() {
        if !hasMigrated {
            let water = DailyGoal(title: "Daily Water Intake", unit: "Water", unitShort: "L", icon: "drop.fill", rangeLower: 0.5, rangeUpper: 5.0, step: 0.25, current: legacyWaterCurrent, target: legacyWaterTarget, colorTheme: "sky")
            let steps = DailyGoal(title: "Daily Steps", unit: "Steps", unitShort: "k", icon: "figure.walk", rangeLower: 1.0, rangeUpper: 20.0, step: 0.5, current: legacyStepsCurrent, target: legacyStepsTarget, colorTheme: "lime")
            let sleep = DailyGoal(title: "Nightly Sleep", unit: "Sleep", unitShort: "hrs", icon: "moon.fill", rangeLower: 4.0, rangeUpper: 12.0, step: 0.5, current: legacySleepCurrent, target: legacySleepTarget, colorTheme: "lilac")
            
            if goalsWrapper.goals.isEmpty {
                goalsWrapper.goals = [water, steps, sleep]
            }
            hasMigrated = true
        }
    }

    private func resetIfNewDay() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayString = formatter.string(from: Date())

        if goalsLastResetDate != todayString {
            for i in 0..<goalsWrapper.goals.count {
                goalsWrapper.goals[i].current = 0
            }
            goalsLastResetDate = todayString
        }
    }
}

// MARK: - Goal Ring Card
struct GoalRingCard: View {
    let goal: DailyGoal
    let cardBg: Color
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var progress: Double {
        guard goal.target > 0 else { return 0 }
        return min(goal.current / goal.target, 1.0)
    }

    private var percentDone: Int {
        Int(progress * 100)
    }

    private var displayValue: String {
        if goal.current == floor(goal.current) {
            return String(format: "%.0f", goal.current)
        } else {
            return String(format: "%.1f", goal.current)
        }
    }

    private var displayUnitSuffix: String {
        goal.unitShort
    }

    var body: some View {
        VStack(spacing: 12) {
            // Circular progress ring with icon & percentage
            ZStack {
                // Track
                Circle()
                    .stroke(goal.ringTrack, lineWidth: 8)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        goal.ringColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)

                // Icon + percentage inside ring
                VStack(spacing: 2) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(goal.ringColor)

                    Text("\(percentDone)%")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 96, height: 96)

            // Value + unit below ring
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                if goal.unitShort != "k" {
                    Text(displayUnitSuffix)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.5))
                } else if goal.unitShort == "k" { // special case handling similar to old steps logic
                     Text("k")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .offset(x: -2)
                }
            }

            // Label
            Text(goal.unit)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.5))
                .tracking(0.5)
                .textCase(.uppercase)
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(width: 160)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(goal.borderColor, lineWidth: 2)
        )
        .boldShadow(goal.shadowColor, size: 6, radius: 24)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            onLongPress()
        }
    }
}

// MARK: - Quick Edit Goal Sheet
struct QuickEditGoalSheet: View {
    let goal: DailyGoal
    let onSave: (DailyGoal) -> Void
    let onDelete: (DailyGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editTarget: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            // Header with delete button
            HStack {
                Text("QUICK EDIT GOAL")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(goal.ringColor)
                Spacer()
                Button(action: {
                    onDelete(goal)
                    dismiss()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.top, 8)

            // Goal name
            Text(goal.title)
                .font(.system(size: 24, weight: .heavy, design: .rounded))

            // +/- controls
            HStack(spacing: 24) {
                // Minus button
                Button(action: {
                    editTarget = max(editTarget - goal.step, goal.rangeLower)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }

                // Current value display
                VStack(spacing: 2) {
                    Text(editTarget == floor(editTarget) ? String(format: "%.0f", editTarget) : String(format: "%.1f", editTarget))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: editTarget)

                    Text(goal.unit)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }

                // Plus button
                Button(action: {
                    editTarget = min(editTarget + goal.step, goal.rangeUpper)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 48, height: 48)
                            .overlay(
                                Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.primary)
                    }
                }
            }

            // Slider
            VStack(spacing: 4) {
                Slider(
                    value: $editTarget,
                    in: goal.rangeLower...goal.rangeUpper,
                    step: goal.step
                )
                .tint(goal.ringColor)

                HStack {
                    Text(formatRangeLabel(goal.rangeLower))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(goal.ringColor)
                    Spacer()
                    Text(formatRangeLabel(goal.rangeUpper))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.5))
                }
            }
            .padding(.horizontal, 8)

            // Set New Goal button
            Button(action: {
                var updated = goal
                updated.target = editTarget
                onSave(updated)
                dismiss()
            }) {
                Text("Set New Goal")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(goal.ringColor)
                    )
            }

            // Cancel
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 16)
        .onAppear {
            editTarget = goal.target
        }
    }

    private func formatRangeLabel(_ value: Double) -> String {
        let formatted = value == floor(value) ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formatted) \(goal.unit)"
    }
}

// MARK: - Add Goal Sheet
struct AddGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (DailyGoal) -> Void
    
    @State private var title: String = ""
    @State private var target: String = ""
    @State private var unit: String = ""
    @State private var unitShort: String = ""
    
    @State private var selectedIcon: String = "star.fill"
    let icons = ["star.fill", "flame.fill", "bolt.fill", "book.fill", "heart.fill", "brain.head.profile", "dumbbell.fill", "figure.mind.and.body"]
    
    @State private var selectedColor: String = "terra"
    let colors = ["terra", "lilac", "lime", "sky"]
    
    private func colorFor(hex: String) -> Color {
        switch hex {
        case "terra": return Color.terra500
        case "lilac": return Color.lilac500
        case "lime": return Color.lime500
        case "sky": return Color.sky500
        default: return Color.terra500
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Title")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        TextField("e.g. Reading", text: $title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(16)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Daily Target")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.gray.opacity(0.8))
                                .textCase(.uppercase)
                            
                            TextField("e.g. 30", text: $target)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .padding(16)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unit")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.gray.opacity(0.8))
                                .textCase(.uppercase)
                            
                            TextField("e.g. mins", text: $unit)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .padding(16)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Short Unit (Optional)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        TextField("e.g. m", text: $unitShort)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(16)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    // Icon Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(icons, id: \.self) { icon in
                                    Button(action: { selectedIcon = icon }) {
                                        Image(systemName: icon)
                                            .font(.system(size: 24))
                                            .frame(width: 56, height: 56)
                                            .background(selectedIcon == icon ? Color.gray.opacity(0.1) : Color.clear)
                                            .foregroundStyle(selectedIcon == icon ? Color.primary : Color.gray.opacity(0.4))
                                            .clipShape(Circle())
                                    }
                                }
                            }
                        }
                    }
                    
                    // Color Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Color")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        HStack(spacing: 16) {
                            ForEach(colors, id: \.self) { hex in
                                Button(action: { selectedColor = hex }) {
                                    Circle()
                                        .fill(colorFor(hex: hex))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary, lineWidth: selectedColor == hex ? 3 : 0)
                                                .padding(-4)
                                        )
                                        .padding(4)
                                }
                            }
                            Spacer()
                        }
                    }
                    
                    Spacer(minLength: 24)
                    
                    Button(action: {
                        let targetVal = Double(target) ?? 1.0
                        let shortU = unitShort.isEmpty ? unit : unitShort
                        let newGoal = DailyGoal(
                            title: title,
                            unit: unit,
                            unitShort: shortU,
                            icon: selectedIcon,
                            rangeLower: targetVal * 0.1,
                            rangeUpper: targetVal * 3.0,
                            step: max(1, targetVal * 0.1),
                            current: 0,
                            target: targetVal,
                            colorTheme: selectedColor
                        )
                        onAdd(newGoal)
                        dismiss()
                    }) {
                        Text("Add Goal")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(colorFor(hex: selectedColor))
                            )
                    }
                    .disabled(title.isEmpty || target.isEmpty || unit.isEmpty)
                    .opacity((title.isEmpty || target.isEmpty || unit.isEmpty) ? 0.5 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.gray)
                }
            }
        }
    }
}

// MARK: - Tab Bar
enum Tab: String, CaseIterable {
    case home, calendar, add, meals, shop
}

struct MainTabBar: View {
    @Binding var selectedTab: Tab
    var onAddTapped: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            // Home
            TabItem(icon: "house.fill", label: "Home",
                    isSelected: selectedTab == .home)
                .onTapGesture { selectedTab = .home }

            // Calendar
            TabItem(icon: "calendar", label: "Calendar",
                    isSelected: selectedTab == .calendar)
                .onTapGesture { selectedTab = .calendar }

            // Center FAB
            Button(action: { onAddTapped() }) {
                ZStack {
                    Circle()
                        .fill(Color.terra500)
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle().stroke(Color.white, lineWidth: 4)
                        )
                        .shadow(color: Color.terra500.opacity(0.4), radius: 10, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -20)
            .frame(maxWidth: .infinity)

            // Meals
            TabItem(icon: "fork.knife", label: "Meals",
                    isSelected: selectedTab == .meals)
                .onTapGesture { selectedTab = .meals }

            // Shop
            TabItem(icon: "bag.fill", label: "Shop",
                    isSelected: selectedTab == .shop)
                .onTapGesture { selectedTab = .shop }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 0)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28
            )
            .fill(Color.cardWhite)
            .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: -4)
            .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct TabItem: View {
    let icon: String
    let label: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Selected: pill bg behind icon
            if isSelected {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.lilac600)
                    .frame(width: 48, height: 32)
                    .background(Color.lilac100)
                    .clipShape(Capsule())
            } else {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(.gray.opacity(0.45))
                    .frame(width: 48, height: 32)
            }
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? Color.lilac600 : .gray.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Add Action Sheet
struct AddActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAddEvent: () -> Void = {}
    var onAddMeal: () -> Void = {}
    var onAddTodo: () -> Void = {}
    var onAddShopping: () -> Void = {}

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("QUICK ADD")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.terra500)
                .padding(.top, 8)

            Text("What would you like to add?")
                .font(.system(size: 22, weight: .heavy, design: .rounded))

            // 2×2 Grid of options
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                AddOptionButton(
                    icon: "calendar.badge.plus",
                    label: "Event",
                    subtitle: "Add to calendar",
                    iconBg: Color.lilac100,
                    iconColor: Color.lilac600,
                    borderColor: Color.lilac200,
                    shadowColor: Color.lilac400
                ) {
                    dismiss()
                    onAddEvent()
                }

                AddOptionButton(
                    icon: "fork.knife",
                    label: "Meal",
                    subtitle: "Plan a meal",
                    iconBg: Color.terra100,
                    iconColor: Color.terra500,
                    borderColor: Color.terra200,
                    shadowColor: Color.terra500
                ) {
                    dismiss()
                    onAddMeal()
                }

                AddOptionButton(
                    icon: "checkmark.circle",
                    label: "To-Do",
                    subtitle: "Add a task",
                    iconBg: Color.lime100,
                    iconColor: Color.lime500,
                    borderColor: Color(red: 0.80, green: 0.92, blue: 0.60),
                    shadowColor: Color.lime500
                ) {
                    dismiss()
                    onAddTodo()
                }

                AddOptionButton(
                    icon: "cart",
                    label: "Shopping",
                    subtitle: "Add to list",
                    iconBg: Color.sky100,
                    iconColor: Color.sky500,
                    borderColor: Color.sky200,
                    shadowColor: Color.sky400
                ) {
                    dismiss()
                    onAddShopping()
                }
            }
            .padding(.horizontal, 8)

            // Cancel
            Button(action: { dismiss() }) {
                Text("CANCEL")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }
}

struct AddOptionButton: View {
    let icon: String
    let label: String
    let subtitle: String
    let iconBg: Color
    let iconColor: Color
    let borderColor: Color
    let shadowColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(iconBg)
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle().stroke(borderColor, lineWidth: 1.5)
                        )
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(iconColor)
                }

                // Label
                Text(label)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)

                // Subtitle
                Text(subtitle)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.5))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(borderColor, lineWidth: 2)
            )
            .boldShadow(shadowColor, size: 3, radius: 16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Placeholder
struct PlaceholderView: View {
    let title: String
    var body: some View {
        VStack {
            Spacer()
            Text(title).font(.largeTitle.bold()).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(DataManager(persistenceController: .preview))
        .environment(SharingManager(persistenceController: .preview))
}

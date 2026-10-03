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
            .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

extension View {
    func boldShadow(_ color: Color, size: CGFloat = 4, radius: CGFloat = 16) -> some View {
        self.shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    func boldShadowSm(_ color: Color, radius: CGFloat = 8) -> some View {
        self.shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
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

// MARK: - Home quiet language
/// Shared by the week card and the rest of Home. Shop keeps its own controls.
enum HomeQuiet {
    static let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    static let quiet = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.45)
    static let rule = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.10)
    static let cardStroke = Color.black.opacity(0.06)
    static let buttonStroke = Color.black.opacity(0.14)
    /// Today's row. One step darker than the cream card: a warm stone.
    static let todayRow = Color(red: 0.937, green: 0.902, blue: 0.863)
    static var card: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }
}

extension View {
    func homeQuietCard() -> some View {
        background(Color.white)
            .clipShape(HomeQuiet.card)
            .overlay(HomeQuiet.card.stroke(HomeQuiet.cardStroke, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
    }
}

// MARK: - Home View
struct HomeView: View {
    @Binding var showSharingSettings: Bool
    @Binding var triggerAddTodo: Bool
    @State private var keyboardOverlap: CGFloat = 0
    @State private var focusedLineID: String?
    @AppStorage("homeShowShoppingList") private var showShoppingList = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    GreetingHeader(showSharingSettings: $showSharingSettings)
                    WeeklyCalendarCard { id in
                        focusedLineID = id
                        reveal(id, proxy: proxy)
                    }
                    if showShoppingList {
                        ShoppingListBoard(quietToolbar: true, showsSectionLabel: true)
                            .padding(.bottom, 24)
                    }
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
    private static let headerInk = Color(red: 0.12, green: 0.11, blue: 0.10)
    private static let headerQuiet = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.45)

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
                VStack(alignment: .leading, spacing: 2) {
                    if greetingName != nil {
                        Text("GOOD MORNING,")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(1.8)
                            .foregroundStyle(Self.headerQuiet)
                    }
                    Text(greetingName ?? "Good morning")
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .foregroundStyle(Self.headerInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("HERE'S YOUR WEEK.")
                        .font(.system(size: 12, weight: .regular))
                        .tracking(1.6)
                        .foregroundStyle(Self.headerQuiet)
                        .padding(.top, 6)
                }
                Spacer(minLength: 12)
                Button(action: { showProfileMenu = true }) {
                    AvatarButton(imageData: profileImageData, soft: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 18)
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

// MARK: - Avatar Button
struct AvatarButton: View {
    let imageData: Data?
    /// Thin ring. The heavier mark stays available for an explicit opt-out.
    var soft: Bool = true

    var body: some View {
        if soft {
            softMark
        } else {
            markedCircle
        }
    }

    private var softMark: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color(white: 0.94))
                .frame(width: 48, height: 48)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .overlay(face.frame(width: 40, height: 40))

            Circle()
                .fill(Color(red: 0.45, green: 0.70, blue: 0.32))
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.bgBase, lineWidth: 1))
                .offset(x: 1, y: 1)
        }
    }

    private var markedCircle: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.black)
                .frame(width: 52, height: 52)
                .offset(x: 4, y: 4)

            Circle()
                .fill(Color.cardWhite)
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .overlay(
                    face
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1))
                )

            Circle()
                .fill(Color.lime400)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                .offset(x: -2, y: 2)
        }
    }

    @ViewBuilder
    private var face: some View {
        if let imageData, let uiImage = UIImage(data: imageData) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else if soft {
            Image(systemName: "person.fill")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.28))
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
                .clipShape(Circle())
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

private struct DinnerLine: Identifiable {
    var id: String
    var mealID: NSManagedObjectID?
    var text: String
    var recipeID: NSManagedObjectID?
}

private struct WeekShareSnapshot {
    var title: String
    var range: String
    var days: [WeekShareDay]
}

private struct WeekShareDay: Identifiable {
    var id: String
    var weekday: String
    var dayNumber: String
    var isToday: Bool
    var groups: [WeekShareMealGroup]
    var events: [WeekShareEvent]
}

private struct WeekShareMealGroup: Identifiable {
    var id: String
    var label: String
    var titles: [String]
}

private struct WeekShareEvent: Identifiable {
    var id: String
    var text: String
    var color: UIColor?
}

/// The week card, without navigation, grocery, or the week action buttons.
private struct WeekShareCard: View {
    let snapshot: WeekShareSnapshot

    private var card: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(snapshot.title)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineLimit(1)
                Text(snapshot.range)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(HomeQuiet.rule)
                .frame(height: 1)

            ForEach(Array(snapshot.days.enumerated()), id: \.element.id) { index, day in
                dayRow(day)
                if index < snapshot.days.count - 1 {
                    Rectangle()
                        .fill(HomeQuiet.rule)
                        .frame(height: 1)
                }
            }
        }
        .background(Color.white)
        .clipShape(card)
        .overlay(card.stroke(HomeQuiet.cardStroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
    }

    private func dayRow(_ day: WeekShareDay) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(day.weekday)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(HomeQuiet.quiet)
                Text(day.dayNumber)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(day.isToday ? Color.terra500 : HomeQuiet.ink)
                if day.isToday {
                    Text("TODAY")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                        .padding(.top, 2)
                }
            }
            .frame(width: 56)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(day.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "fork.knife")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(HomeQuiet.quiet)
                            Text(group.label)
                                .font(.system(size: 10, weight: .medium))
                                .tracking(1.3)
                                .foregroundStyle(HomeQuiet.quiet)
                        }
                        ForEach(Array(group.titles.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.system(size: 20, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if !day.events.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(day.events) { event in
                            HStack(alignment: .center, spacing: 8) {
                                Circle()
                                    .fill(event.color.map { Color(uiColor: $0) } ?? Color.black.opacity(0.28))
                                    .frame(width: 7, height: 7)
                                Text(event.text)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(HomeQuiet.ink.opacity(0.55))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
        .background {
            if day.isToday {
                HomeQuiet.todayRow
            }
        }
    }
}

@MainActor
private enum WeekShareImage {
    /// Instagram story pixels. The card is drawn on the cream field and scaled to fit.
    static let storySize = CGSize(width: 1080, height: 1920)

    static func render(_ snapshot: WeekShareSnapshot) -> UIImage? {
        let card = WeekShareCard(snapshot: snapshot)
            .frame(width: 312)
            .padding(16)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = false
        guard let cardImage = renderer.uiImage else { return nil }
        return compose(cardImage)
    }

    private static func compose(_ card: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let canvas = storySize
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            UIColor(red: 1, green: 0.976, blue: 0.965, alpha: 1).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: canvas)).fill()
            let margin: CGFloat = 72
            let maxWidth = canvas.width - margin * 2
            let maxHeight = canvas.height - margin * 2
            let pixelSize = CGSize(
                width: card.size.width * card.scale,
                height: card.size.height * card.scale
            )
            guard pixelSize.width > 0, pixelSize.height > 0 else { return }
            let fit = min(maxWidth / pixelSize.width, maxHeight / pixelSize.height)
            let drawSize = CGSize(width: pixelSize.width * fit, height: pixelSize.height * fit)
            let rect = CGRect(
                x: (canvas.width - drawSize.width) / 2,
                y: (canvas.height - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            card.draw(in: rect)
        }
    }
}

/// How the home week lists its days. The first two match the original bool.
private enum HomeWeekDisplay: String {
    case fromToday
    case everyDay
    case rolling

    static func resolve(stored: String, showPastDays: Bool) -> HomeWeekDisplay {
        if let mode = HomeWeekDisplay(rawValue: stored) { return mode }
        return showPastDays ? .everyDay : .fromToday
    }
}

/// Quiet sheet for the Home display choices. Stored on this phone.
private struct HomeDisplaySheet: View {
    @AppStorage("homeWeekDisplay") private var homeWeekDisplayRaw = ""
    @AppStorage("homeShowPastDays") private var showPastDays = false
    @AppStorage("homeShowWeekEvents") private var showWeekEvents = true
    @AppStorage("homeShowShoppingList") private var showShoppingList = true

    private var weekDisplay: HomeWeekDisplay {
        HomeWeekDisplay.resolve(stored: homeWeekDisplayRaw, showPastDays: showPastDays)
    }

    private func selectWeek(_ mode: HomeWeekDisplay) {
        homeWeekDisplayRaw = mode.rawValue
        showPastDays = mode == .everyDay
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            options
        }
        .background(Color.bgBase)
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("HOME")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(HomeQuiet.quiet)
                Text("Display")
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("THIS WEEK")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.4)
                    .foregroundStyle(HomeQuiet.quiet)

                VStack(spacing: 0) {
                    weekChoice("From today", selected: weekDisplay == .fromToday) {
                        selectWeek(.fromToday)
                    }
                    Rectangle()
                        .fill(HomeQuiet.rule)
                        .frame(height: 1)
                    weekChoice("Every day", selected: weekDisplay == .everyDay) {
                        selectWeek(.everyDay)
                    }
                    Rectangle()
                        .fill(HomeQuiet.rule)
                        .frame(height: 1)
                    weekChoice("Next 7 days", selected: weekDisplay == .rolling) {
                        selectWeek(.rolling)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(HomeQuiet.cardStroke, lineWidth: 1)
                )
            }

            VStack(spacing: 0) {
                displayToggle("Events under meals", isOn: $showWeekEvents)
                Rectangle()
                    .fill(HomeQuiet.rule)
                    .frame(height: 1)
                displayToggle("Shopping list", isOn: $showShoppingList)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(HomeQuiet.cardStroke, lineWidth: 1)
            )
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func weekChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.terra500)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }

    private func displayToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .tint(Color.terra500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

@MainActor
private enum WeekSharePresenter {
    static func present(_ image: UIImage) {
        let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        guard let presenter = topViewController() else { return }
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let root = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
        var presenter = root
        while let presented = presenter?.presentedViewController {
            presenter = presented
        }
        return presenter
    }
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
    @State private var showHomeDisplay = false
    @State private var suppressCommit = false
    @State private var mealFocusStamp = 0
    @State private var expandedDay: Date?
    @FocusState private var focusedField: DinnerField?
    @AppStorage("homeWeekDisplay") private var homeWeekDisplayRaw = ""
    @AppStorage("homeShowPastDays") private var showPastDays = false
    @AppStorage("homeShowWeekEvents") private var showWeekEvents = true

    private var weekDisplay: HomeWeekDisplay {
        HomeWeekDisplay.resolve(stored: homeWeekDisplayRaw, showPastDays: showPastDays)
    }

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

    /// From today drops earlier days of this calendar week. Every day keeps all seven.
    /// Next 7 days, on this week only, is today and the six days after it.
    /// Another week is always that calendar week's seven days.
    private var listedWeekDates: [Date] {
        let calendar = Calendar.current
        if weekOffset == 0, weekDisplay == .rolling {
            let today = calendar.startOfDay(for: Date())
            return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        }
        guard weekOffset == 0, weekDisplay == .fromToday else { return weekDates }
        let today = calendar.startOfDay(for: Date())
        return weekDates.filter { calendar.startOfDay(for: $0) >= today }
    }

    /// Meals and events load with the days on screen. Other modes stay on the calendar week.
    private var loadedWeekStart: Date? {
        if weekOffset == 0, weekDisplay == .rolling {
            return Calendar.current.startOfDay(for: Date())
        }
        return weekDates.first
    }

    private var weekRangeLabel: String {
        let span = (weekOffset == 0 && weekDisplay == .rolling) ? listedWeekDates : weekDates
        guard let first = span.first, let last = span.last else { return "" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "\(df.string(from: first)) – \(df.string(from: last))"
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0: return "This week"
        case -1: return "Last week"
        case 1: return "Next week"
        default:
            let count = abs(weekOffset)
            return weekOffset < 0 ? "\(count) weeks ago" : "\(count) weeks ahead"
        }
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
            .onReceive(NotificationCenter.default.publisher(for: .shoppingItemFieldFocused)) { _ in
                if focusedField != nil {
                    focusedField = nil
                }
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
                expandedDay = nil
                if case .line(let day, let id) = focusedField {
                    commitLine(day: day, lineID: id)
                }
                focusedField = nil
                loadData()
                refreshAppleEvents()
            }
            .onChange(of: homeWeekDisplayRaw) { _, _ in
                expandedDay = nil
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
        .sheet(isPresented: $showHomeDisplay) {
            HomeDisplaySheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
    }

    /// Quiet cream card. Today is a terracotta pill. Meals stay near-black.
    private static let weekInk = Color(red: 0.12, green: 0.11, blue: 0.10)
    private static let weekQuiet = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.45)
    private static let weekRule = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.10)

    private var weekCardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    private var weekHairline: some View {
        Rectangle()
            .fill(Self.weekRule)
            .frame(height: 1)
    }

    private var homeSurface: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let cue = calendarSyncManager.calendarSelectionCue {
                Button {
                    showCalendarSettings = true
                } label: {
                    Text(cue)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Self.weekQuiet)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 8)
                .accessibilityLabel("Choose calendars")
            }

            VStack(alignment: .leading, spacing: 0) {
                if let expandedDay {
                    dayExpanded(expandedDay)
                } else {
                    weekContent
                }
                weekFooterActions
            }
            .background(Color.white)
            .clipShape(weekCardShape)
            .overlay(weekCardShape.stroke(Color.black.opacity(0.06), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 14, x: 0, y: 6)
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    private var weekContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            weekHeader

            weekHairline

            ForEach(Array(listedWeekDates.enumerated()), id: \.offset) { index, date in
                dayRow(date)
                if index < listedWeekDates.count - 1 {
                    weekHairline
                }
            }
        }
    }

    private func dayExpanded(_ date: Date) -> some View {
        let key = dayKey(date)
        let lines = linesByDay[key] ?? [blankLine(for: key)]
        let isToday = Calendar.current.isDateInToday(date)
        let title = expandedDayTitle(date)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    dismissMealKeyboard()
                    expandedDay = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Self.weekQuiet)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to week")

                Text(title)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Self.weekInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if isToday {
                    todayPill
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            if !otherMealGroups(on: date).isEmpty {
                otherMealBlocks(on: date)
                    .padding(.horizontal, 16)
            }

            dinnerBlock(lines, on: key, dayName: isToday ? "Today" : title)
                .padding(.horizontal, 16)

            if showWeekEvents, !homeEventLines(on: date).isEmpty {
                eventLines(on: date)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 16)
    }

    private func expandedDayTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private var weekHeader: some View {
        HStack(spacing: 4) {
            weekChevron("chevron.left") { weekOffset -= 1 }

            HStack(spacing: 8) {
                if let household = dataManager.currentHousehold, dataManager.persistenceController.isShared(object: household) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(Self.weekQuiet)
                }
                Text(weekTitle)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(Self.weekInk)
                    .lineLimit(1)
                Text(weekRangeLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Self.weekQuiet)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if weekOffset != 0 {
                    Button(action: { weekOffset = 0 }) {
                        Text("Today")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Color.terra600)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to this week")
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { dismissMealKeyboard() }

            weekChevron("chevron.right") { weekOffset += 1 }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func weekChevron(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Self.weekQuiet)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }

    private var weekFooterActions: some View {
        VStack(spacing: 0) {
            weekHairline
            HStack(spacing: 6) {
                weekActionButton("Swipe to plan", enabled: !weekDates.isEmpty) {
                    showWeekPlanner = true
                }
                weekActionButton("Share", enabled: !listedWeekDates.isEmpty) {
                    shareCurrentWeek()
                }
                .accessibilityLabel("Share week")
                if !weekMeals.isEmpty {
                    weekActionButton("Clear week") {
                        showClearWeek = true
                    }
                }
                Spacer(minLength: 6)
                Button {
                    showHomeDisplay = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Self.weekInk)
                        .frame(width: 34, height: 34)
                        .background(Color.terra100)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.terra200, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Home display")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
    }

    private func weekActionButton(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Self.weekInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Color.terra100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    /// Renders the week card off-screen and opens the system share sheet.
    private func shareCurrentWeek() {
        let snapshot = weekShareSnapshot()
        guard let image = WeekShareImage.render(snapshot) else { return }
        WeekSharePresenter.present(image)
    }

    /// Same rows the home week is showing. Titles only, no ingredients.
    private func weekShareSnapshot() -> WeekShareSnapshot {
        let days = listedWeekDates.map { date -> WeekShareDay in
            let calendar = Calendar.current
            let isToday = calendar.isDateInToday(date)
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.dateFormat = "EEE"
            let numberFormatter = DateFormatter()
            numberFormatter.dateFormat = "d"
            var groups: [WeekShareMealGroup] = []
            if isToday {
                groups.append(contentsOf: otherMealGroups(on: date).map {
                    WeekShareMealGroup(id: $0.id, label: $0.label, titles: $0.titles)
                })
            }
            let key = dayKey(date)
            let dinnerTitles = (linesByDay[key] ?? [])
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !dinnerTitles.isEmpty {
                groups.append(WeekShareMealGroup(id: "DINNER", label: "DINNER", titles: dinnerTitles))
            }
            let events = showWeekEvents
                ? homeEventLines(on: date)
                    .filter { !$0.sideText.isEmpty }
                    .map { WeekShareEvent(id: $0.id, text: $0.sideText, color: $0.calendarColor) }
                : []
            return WeekShareDay(
                id: String(calendar.startOfDay(for: date).timeIntervalSince1970),
                weekday: weekdayFormatter.string(from: date).uppercased(),
                dayNumber: numberFormatter.string(from: date),
                isToday: isToday,
                groups: groups,
                events: events
            )
        }
        return WeekShareSnapshot(title: weekTitle, range: weekRangeLabel, days: days)
    }

    private var todayPill: some View {
        Text("TODAY")
            .font(.system(size: 9, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.terra500)
            .clipShape(Capsule())
    }

    private func dayRow(_ date: Date) -> some View {
        let calendar = Calendar.current
        let key = dayKey(date)
        let isToday = calendar.isDateInToday(date)
        let dayFocused = isDayFocused(key)
        let lines = linesByDay[key] ?? [blankLine(for: key)]
        let dayEvents = events(for: date)
        let dayApple = appleEventsForDate(date)
        let weekday: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date).uppercased()
        }()
        let dayNumber: String = {
            let formatter = DateFormatter()
            formatter.dateFormat = "d"
            return formatter.string(from: date)
        }()
        let dayName = isToday ? "Today" : weekday
        let showEvents = showWeekEvents && !dayFocused && !(dayEvents.isEmpty && dayApple.isEmpty)

        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Text(weekday)
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(Self.weekQuiet)
                Text(dayNumber)
                    .font(.system(size: 28, weight: .regular, design: .serif))
                    .foregroundStyle(isToday ? Color.terra500 : Self.weekInk)
                if isToday {
                    todayPill
                        .padding(.top, 2)
                }
            }
            .frame(width: 56)
            .contentShape(Rectangle())
            .onTapGesture {
                dismissMealKeyboard()
                expandedDay = key
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isToday ? "Open today" : "Open \(weekday) \(dayNumber)")

            VStack(alignment: .leading, spacing: 10) {
                if isToday, !otherMealGroups(on: date).isEmpty {
                    otherMealBlocks(on: date)
                }
                dinnerBlock(lines, on: key, dayName: dayName)
                if showEvents {
                    eventLines(on: date)
                        .transition(.opacity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            if !dayFocused {
                Button {
                    dismissMealKeyboard()
                    expandedDay = key
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.22))
                        .frame(width: 18, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isToday ? "Open today" : "Open \(weekday) \(dayNumber)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 14)
        .background {
            if isToday {
                HomeQuiet.todayRow
            }
        }
        .animation(.easeInOut(duration: 0.22), value: dayFocused)
    }

    private struct MealTitleGroup: Identifiable {
        let id: String
        let label: String
        let titles: [String]
    }

    /// Breakfast, lunch, and anything that is not the editable dinner line.
    private func otherMealBlocks(on date: Date) -> some View {
        let groups = otherMealGroups(on: date)
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    mealKindLabel(group.label)
                    ForEach(Array(group.titles.enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(Self.weekInk)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func otherMealGroups(on date: Date) -> [MealTitleGroup] {
        let others = meals(for: date).filter { ($0.mealType ?? "dinner").lowercased() != "dinner" }
        let order = ["breakfast": 0, "lunch": 1, "snack": 2]
        let sorted = others.sorted { lhs, rhs in
            let left = order[(lhs.mealType ?? "").lowercased()] ?? 3
            let right = order[(rhs.mealType ?? "").lowercased()] ?? 3
            if left != right { return left < right }
            let leftDate = lhs.date ?? .distantPast
            let rightDate = rhs.date ?? .distantPast
            if leftDate != rightDate { return leftDate < rightDate }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
        var groups: [MealTitleGroup] = []
        for meal in sorted {
            let title = (meal.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let label = (meal.mealType ?? "Meal").trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (label.isEmpty ? "Meal" : label).uppercased()
            if let index = groups.firstIndex(where: { $0.label == name }) {
                groups[index] = MealTitleGroup(id: name, label: name, titles: groups[index].titles + [title])
            } else {
                groups.append(MealTitleGroup(id: name, label: name, titles: [title]))
            }
        }
        return groups
    }

    private func mealKindLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Self.weekQuiet)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(Self.weekQuiet)
        }
    }

    private func dinnerBlock(_ lines: [DinnerLine], on day: Date, dayName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "fork.knife")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Self.weekQuiet)
                Text("DINNER")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.3)
                    .foregroundStyle(Self.weekQuiet)
            }
            ForEach(lines) { line in
                dinnerLine(line, on: day, dayName: dayName, spare: lines.count > 1)
                    .id(scrollID(day: day, lineID: line.id))
            }
        }
    }

    private func dinnerLine(_ line: DinnerLine, on day: Date, dayName: String, spare: Bool) -> some View {
        let focused = focusedField == .line(day: day, id: line.id)
        let linked = linkedRecipe(for: line)
        let text = line.text
        let matches = focused ? suggestions(matching: text, excluding: linked?.objectID) : []
        let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mealFont = Font.system(size: 20, weight: .regular, design: .serif)
        let placeholder = spare ? "Add another" : "Add dinner"
        let placeholderFont = spare
            ? Font.system(size: 15, weight: .regular, design: .serif)
            : mealFont

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ZStack(alignment: .leading) {
                    TextField("", text: lineBinding(day: day, lineID: line.id), axis: .vertical)
                        .font(mealFont)
                        .foregroundStyle(Self.weekInk)
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
                        .opacity(focused ? 1 : 0)
                        .accessibilityLabel("\(dayName) dinner")
                    if !focused {
                        Text(shown.isEmpty ? placeholder : shown)
                            .font(shown.isEmpty ? placeholderFont : mealFont)
                            .foregroundStyle(shown.isEmpty ? Self.weekQuiet : Self.weekInk)
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
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Self.weekQuiet)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear dinner")
                }
            }

            if focused {
                Rectangle()
                    .fill(Self.weekRule)
                    .frame(height: 1)
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
                                }
                                Text(recipe.name ?? "")
                                    .font(.system(size: 16, weight: .regular, design: .serif))
                                    .foregroundStyle(Self.weekInk)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.bgBase)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Self.weekRule, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private struct HomeEventLine: Identifiable {
        let id: String
        let timeLabel: String
        let title: String
        let sortDate: Date
        /// EventKit or in-app calendar color. Nil uses a neutral dot.
        let calendarColor: UIColor?
        let open: () -> Void

        var sideText: String {
            if timeLabel.isEmpty { return title }
            if title.isEmpty { return timeLabel }
            return "\(timeLabel) · \(title)"
        }

        var detailText: String { sideText }
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

    /// Calendar events sit under the meal: one colored dot, then time · name.
    private func eventLines(on date: Date) -> some View {
        let lines = homeEventLines(on: date).filter { !$0.sideText.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                Button(action: line.open) {
                    HStack(alignment: .center, spacing: 8) {
                        Circle()
                            .fill(line.calendarColor.map { Color(uiColor: $0) } ?? Color.black.opacity(0.28))
                            .frame(width: 7, height: 7)
                        Text(line.sideText)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(Self.weekInk.opacity(0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(line.sideText)
            }
        }
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

            VStack(spacing: 16) {
                Text("Clear this week?")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text("Meals on this week will be removed. Events stay.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 10) {
                    Button {
                        showClearWeek = false
                    } label: {
                        Text("Keep meals")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.terra500)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        clearWeekMeals()
                    } label: {
                        Text("Clear week")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(HomeQuiet.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
            .background(Color.white)
            .clipShape(HomeQuiet.card)
            .overlay(HomeQuiet.card.stroke(HomeQuiet.cardStroke, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 8)
            .padding(.horizontal, 28)
        }
        .preferredColorScheme(.light)
    }

    private func clearWeekMeals() {
        suppressCommit = true
        focusedField = nil
        showClearWeek = false
        guard let start = loadedWeekStart else {
            suppressCommit = false
            return
        }
        let meals = dataManager.fetchWeekMealPlans(from: start)
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
        guard let last = listedWeekDates.last else { return true }
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
        guard let index = listedWeekDates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: day) }),
              index + 1 < listedWeekDates.count else {
            focusedField = nil
            return
        }
        let next = dayKey(listedWeekDates[index + 1])
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
        guard let start = loadedWeekStart else { return }
        recipes = dataManager.fetchRecipes()
        weekMeals = dataManager.fetchWeekMealPlans(from: start)
        weekEvents = dataManager.fetchWeekEvents(from: start)
        syncLines()
    }

    /// Reload Apple events after the saved EventKit grant and calendar
    /// selection are applied. Does not rebuild dinner lines.
    private func refreshAppleEvents() {
        Task {
            await calendarSyncManager.prepareForReading()
            guard let start = loadedWeekStart else { return }
            appleEvents = calendarSyncManager.fetchWeekEvents(from: start)
        }
    }

    private func reloadMeals() {
        guard let start = loadedWeekStart else { return }
        let focus = focusedField
        weekMeals = dataManager.fetchWeekMealPlans(from: start)
        syncLines(keeping: focus)
        if focusedField != focus {
            focusedField = focus
        }
    }

    private func syncLines(keeping focus: DinnerField? = nil) {
        let protected = focus ?? focusedField
        var next: [Date: [DinnerLine]] = [:]
        let dates = (weekOffset == 0 && weekDisplay == .rolling) ? listedWeekDates : weekDates
        for date in dates {
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
        .font(.system(size: 10, weight: .regular))
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
                            .font(.system(size: 9, weight: .regular))
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
                            .font(.system(size: 9, weight: .regular))
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
            .font(.system(size: 10, weight: .regular))
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
                    .font(.system(size: 10, weight: .regular))
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
                .font(.system(size: 10, weight: .regular))
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
            .font(.system(size: 10, weight: .regular))
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
                    .font(.system(size: 10, weight: .regular))
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
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
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
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TO-DO")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.4)
                        .foregroundStyle(HomeQuiet.quiet)
                    Text("Today")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                }
                Spacer()
                Button(action: {
                    isAddingTodo = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isNewTodoFocused = true
                    }
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                        .frame(width: 36, height: 36)
                        .background(Color.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }

            VStack(spacing: 0) {
                if todos.isEmpty && !isAddingTodo {
                    Text("No tasks yet")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
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
                            Rectangle()
                                .fill(HomeQuiet.rule)
                                .frame(height: 1)
                        }
                    }
                }
                
                if isAddingTodo {
                    HStack(spacing: 12) {
                        Circle()
                            .stroke(HomeQuiet.ink.opacity(0.28), lineWidth: 1)
                            .frame(width: 18, height: 18)
                        
                        TextField("New task", text: $newTodoTitle)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
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
            .padding(16)
            .homeQuietCard()
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
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(Color.terra600)
                            .frame(width: 36, height: 36)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                            .padding(.trailing, 8)
                    }
                }
            }

            // Foreground content
            HStack(spacing: 12) {
                // Circular checkbox
                ZStack {
                    Circle()
                        .stroke(todo.isChecked ? Color.terra500 : HomeQuiet.ink.opacity(0.28), lineWidth: 1)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(todo.isChecked ? Color.terra500 : Color.clear)
                        )

                    if todo.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .regular))
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
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(todo.isChecked ? HomeQuiet.quiet : HomeQuiet.ink)
                        .strikethrough(todo.isChecked, color: HomeQuiet.quiet)
                        .lineLimit(1)
                    if !todo.subtitle.isEmpty {
                        Text(todo.subtitle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .lineLimit(1)
                            .strikethrough(todo.isChecked, color: HomeQuiet.quiet)
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
            .background(Color.white)
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
                Text("Edit task")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
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
                    Text("TITLE")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                        .tracking(1.2)
                    
                    TextField("What needs to be done?", text: $todo.title)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(HomeQuiet.buttonStroke, lineWidth: 1)
                        )
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTE")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                        .tracking(1.2)
                    
                    TextField("e.g. 7:30 AM • Studio", text: $todo.subtitle)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(HomeQuiet.buttonStroke, lineWidth: 1)
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
                Text("Save")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.terra500))
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GOALS")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.4)
                        .foregroundStyle(HomeQuiet.quiet)
                    Text("Daily")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                }

                Spacer()

                Text("TAP TO LOG")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.1)
                    .foregroundStyle(HomeQuiet.quiet)
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
                                    .stroke(HomeQuiet.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(HomeQuiet.quiet)
                            }
                            .frame(width: 72, height: 72)
                            
                            Text("New goal")
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                        }
                        .padding(.vertical, 18)
                        .padding(.horizontal, 16)
                        .frame(width: 148)
                        .homeQuietCard()
                    }
                    .buttonStyle(.plain)
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
                Circle()
                    .stroke(HomeQuiet.rule, lineWidth: 1)

                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        Color.terra500,
                        style: StrokeStyle(lineWidth: 1, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: progress)

                VStack(spacing: 2) {
                    Image(systemName: goal.icon)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)

                    Text("\(percentDone)%")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                }
            }
            .frame(width: 72, height: 72)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(displayValue)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                if goal.unitShort != "k" {
                    Text(displayUnitSuffix)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                } else if goal.unitShort == "k" {
                     Text("k")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.quiet)
                        .offset(x: -2)
                }
            }

            Text(goal.unit.uppercased())
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(HomeQuiet.quiet)
                .tracking(1.1)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(width: 148)
        .background(cardBg)
        .homeQuietCard()
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
                Text("Edit goal")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
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
                .font(.system(size: 20, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)

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
                        .font(.system(size: 40, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: editTarget)

                    Text(goal.unit.uppercased())
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.1)
                        .foregroundStyle(HomeQuiet.quiet)
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
                .tint(Color.terra500)

                HStack {
                    Text(formatRangeLabel(goal.rangeLower))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(goal.ringColor)
                    Spacer()
                    Text(formatRangeLabel(goal.rangeUpper))
                        .font(.system(size: 10, weight: .regular))
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
                Text("Save")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.terra500))
            }

            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
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
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        TextField("e.g. Reading", text: $title)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .padding(16)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Daily Target")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.gray.opacity(0.8))
                                .textCase(.uppercase)
                            
                            TextField("e.g. 30", text: $target)
                                .keyboardType(.decimalPad)
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .padding(16)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Unit")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.gray.opacity(0.8))
                                .textCase(.uppercase)
                            
                            TextField("e.g. mins", text: $unit)
                                .font(.system(size: 16, weight: .regular, design: .serif))
                                .padding(16)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Short Unit (Optional)")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.gray.opacity(0.8))
                            .textCase(.uppercase)
                        
                        TextField("e.g. m", text: $unitShort)
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .padding(16)
                            .background(Color.gray.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    }
                    
                    // Icon Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icon")
                            .font(.system(size: 10, weight: .regular))
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
                            .font(.system(size: 10, weight: .regular))
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
                        Text("Add goal")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(Color.terra500))
                    }
                    .disabled(title.isEmpty || target.isEmpty || unit.isEmpty)
                    .opacity((title.isEmpty || target.isEmpty || unit.isEmpty) ? 0.5 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
            }
            .navigationTitle("New goal")
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
                        .frame(width: 48, height: 48)
                        .overlay(Circle().stroke(Color.bgBase, lineWidth: 3))
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                }
            }
            .offset(y: -10)
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
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(isSelected ? Color.terra600 : HomeQuiet.quiet)
                .frame(width: 48, height: 32)
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .tracking(0.6)
                .foregroundStyle(isSelected ? Color.terra600 : HomeQuiet.quiet)
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
                .font(.system(size: 11, weight: .regular))
                .tracking(1.5)
                .foregroundStyle(Color.terra500)
                .padding(.top, 8)

            Text("What would you like to add?")
                .font(.system(size: 22, weight: .regular, design: .serif))

            // 2×2 Grid of options
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 16) {
                AddOptionButton(
                    icon: "calendar.badge.plus",
                    label: "Event",
                    subtitle: "Add to calendar"
                ) {
                    dismiss()
                    onAddEvent()
                }

                AddOptionButton(
                    icon: "fork.knife",
                    label: "Meal",
                    subtitle: "Plan a meal"
                ) {
                    dismiss()
                    onAddMeal()
                }

                AddOptionButton(
                    icon: "checkmark.circle",
                    label: "To-Do",
                    subtitle: "Add a task"
                ) {
                    dismiss()
                    onAddTodo()
                }

                AddOptionButton(
                    icon: "cart",
                    label: "Shopping",
                    subtitle: "Add to list"
                ) {
                    dismiss()
                    onAddShopping()
                }
            }
            .padding(.horizontal, 8)

            // Cancel
            Button(action: { dismiss() }) {
                Text("Cancel")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
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
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(width: 36, height: 36)

                Text(label)
                    .font(.system(size: 18, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)

                Text(subtitle.uppercased())
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .tracking(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .homeQuietCard()
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

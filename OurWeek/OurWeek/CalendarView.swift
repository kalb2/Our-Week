import SwiftUI
import UIKit
import CoreData
import EventKit

struct CalendarView: View {
    @Environment(DataManager.self) private var dataManager
    @Environment(CalendarSyncManager.self) private var calendarSyncManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var monthOffset: Int = 0
    
    @State private var events: [CalendarEvent] = []
    @State private var meals: [MealPlan] = []
    @State private var appleEvents: [AppleCalendarEvent] = []
    @State private var monthEvents: [CalendarEvent] = []
    @State private var monthAppleEvents: [AppleCalendarEvent] = []
    @State private var editingTodo: TodoTask?
    @AppStorage("homeTodosWrapper") private var todosWrapper = TodosWrapper(todos: [
        TodoTask(title: "Morning Pilates", subtitle: "7:30 AM • Studio", subtitleColorHex: "terra"),
        TodoTask(title: "Grocery Run", subtitle: "Whole Foods", subtitleColorHex: "lilac")
    ])
    
    private var calendar: Calendar { Calendar.current }
    
    private var baseDate: Date {
        calendar.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: baseDate)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerView
                
                // Days of week
                HStack {
                    ForEach(calendar.shortWeekdaySymbols, id: \.self) { symbol in
                        Text(symbol.uppercased())
                            .font(.system(size: 10, weight: .regular))
                            .tracking(0.8)
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                
                // Grid
                TabView(selection: $monthOffset) {
                    ForEach(-12...12, id: \.self) { offset in
                        monthGrid(for: offset)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 320)
                
                Divider()
                
                // Day detail list
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(selectedDate, formatter: selectedDateFormatter)
                            .font(.system(size: 20, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                            .padding(.top, 16)
                            .padding(.horizontal)
                        
                        if events.isEmpty && meals.isEmpty && appleEvents.isEmpty && dayTodos.isEmpty {
                            Text("No events or meals")
                                .font(.system(size: 15, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.quiet)
                                .padding(.horizontal)
                        } else {
                            ForEach(meals, id: \.objectID) { meal in
                                MealListItem(meal: meal)
                                    .padding(.horizontal)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            dataManager.deleteMealPlan(meal)
                                            loadData()
                                        } label: {
                                            Label("Delete Meal", systemImage: "trash")
                                        }
                                    }
                            }
                            if !meals.isEmpty && !(events.isEmpty && appleEvents.isEmpty && dayTodos.isEmpty) {
                                Rectangle()
                                    .fill(HomeQuiet.rule)
                                    .frame(height: 1)
                                    .padding(.horizontal)
                            }
                            ForEach(dayTodos) { todo in
                                CalendarTodoItem(
                                    todo: todo,
                                    onToggle: { toggleTodo(todo) },
                                    onOpen: { editingTodo = todo }
                                )
                                .padding(.horizontal)
                            }
                            ForEach(events, id: \.objectID) { event in
                                EventListItem(event: event)
                                    .padding(.horizontal)
                            }
                            ForEach(appleEvents) { appleEvent in
                                AppleEventListItem(event: appleEvent)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.bottom, 120) // Tab bar clearance
                }
            }
            .navigationBarHidden(true)
            .background(Color.bgBase)
            .onAppear {
                loadData()
                refreshAppleEvents()
                loadMonthDots()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                refreshAppleEvents()
                loadMonthDots()
            }
            .onChange(of: selectedDate, loadData)
            .onChange(of: monthOffset) { _, _ in
                loadMonthDots()
            }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
                refreshAppleEvents()
                loadMonthDots()
            }
            .onReceive(NotificationCenter.default.publisher(for: .ourWeekPlansChanged)) { _ in
                loadData()
                refreshAppleEvents()
                loadMonthDots()
            }
            .sheet(item: $editingTodo) { todo in
                EditTodoSheet(
                    todo: todo,
                    onSave: { replaceTodo($0) },
                    onDelete: { deleted in
                        var items = todosWrapper.todos
                        items.removeAll { $0.id == deleted.id }
                        todosWrapper = TodosWrapper(todos: items)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
            }
        }
    }

    private var dayTodos: [TodoTask] {
        todosWrapper.todos.filter { $0.occurs(on: selectedDate) }
    }

    private func replaceTodo(_ todo: TodoTask) {
        guard let index = todosWrapper.todos.firstIndex(where: { $0.id == todo.id }) else { return }
        var items = todosWrapper.todos
        items[index] = todo
        todosWrapper = TodosWrapper(todos: items)
    }

    private func toggleTodo(_ todo: TodoTask) {
        var updated = todo
        updated.isChecked.toggle()
        HomeWidgetStore.discardWidgetToggle(id: updated.id)
        replaceTodo(updated)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private var headerView: some View {
        HStack {
            Text(monthYearString)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
            
            Spacer()
            
            Button {
                selectedDate = calendar.startOfDay(for: Date())
                monthOffset = 0
            } label: {
                Text("Today")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.terra600)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding()
    }
    
    private func monthGrid(for offset: Int) -> some View {
        let gridDays = days(for: offset)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(gridDays, id: \.self) { date in
                DayCell(
                    date: date,
                    isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                    isToday: calendar.isDateInToday(date),
                    isCurrentMonth: calendar.isDate(date, equalTo: calendar.date(byAdding: .month, value: offset, to: Date()) ?? Date(), toGranularity: .month),
                    dotColors: dotColors(on: date)
                )
                .onTapGesture {
                    selectedDate = calendar.startOfDay(for: date)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func days(for offset: Int) -> [Date] {
        guard let targetMonth = calendar.date(byAdding: .month, value: offset, to: Date()),
              let monthInterval = calendar.dateInterval(of: .month, for: targetMonth) else { return [] }
        
        var result: [Date] = []
        let startOfMonth = monthInterval.start
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let firstDayOffset = weekday - calendar.firstWeekday
        let startOffset = firstDayOffset >= 0 ? firstDayOffset : firstDayOffset + 7
        
        let firstDisplayDate = calendar.date(byAdding: .day, value: -startOffset, to: startOfMonth)!
        
        for i in 0..<42 {
            if let date = calendar.date(byAdding: .day, value: i, to: firstDisplayDate) {
                result.append(date)
            }
        }
        return result
    }
    
    private var selectedDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter
    }
    
    private func loadData() {
        events = dataManager.fetchEvents(for: selectedDate)
        meals = dataManager.fetchMealPlans(for: selectedDate)
        
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        appleEvents = calendarSyncManager.fetchEvents(from: start, to: end)
    }

    private func refreshAppleEvents() {
        Task {
            await calendarSyncManager.prepareForReading()
            let start = Calendar.current.startOfDay(for: selectedDate)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
            appleEvents = calendarSyncManager.fetchEvents(from: start, to: end)
            loadMonthDots()
        }
    }

    /// Dots for the visible month and its neighbors, so a swipe already has marks.
    private func loadMonthDots() {
        let gridDays = [-1, 0, 1].flatMap { days(for: monthOffset + $0) }
        guard let first = gridDays.min(), let last = gridDays.max(),
              let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: first)),
              let end = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: last)) else { return }
        monthEvents = dataManager.fetchEvents(from: start, to: end)
        monthAppleEvents = calendarSyncManager.fetchEvents(from: start, to: end)
    }

    /// Calendar events only. Meals stay in the day list and do not add a dot.
    private func dotColors(on date: Date) -> [Color] {
        var marks: [(when: Date, color: Color, id: String)] = []
        for event in monthEvents where appEvent(event, occursOn: date) {
            marks.append((
                event.date ?? .distantPast,
                dotColor(for: event),
                event.objectID.uriRepresentation().absoluteString
            ))
        }
        for event in monthAppleEvents where event.occurs(on: date) {
            marks.append((event.startDate, Color(uiColor: event.calendarColor), event.id))
        }
        return marks
            .sorted { lhs, rhs in
                if lhs.when != rhs.when { return lhs.when < rhs.when }
                return lhs.id < rhs.id
            }
            .map(\.color)
    }

    private func appEvent(_ event: CalendarEvent, occursOn date: Date) -> Bool {
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay),
              let eventStart = event.date else { return false }
        if let eventEnd = event.endDate, eventEnd > eventStart {
            return eventStart < endOfDay && eventEnd > startOfDay
        }
        return calendar.isDate(eventStart, inSameDayAs: date)
    }

    private func dotColor(for event: CalendarEvent) -> Color {
        if let color = uiColor(fromHex: event.color) {
            return Color(uiColor: color)
        }
        return Color.terra600
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
}

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let isCurrentMonth: Bool
    var dotColors: [Color] = []
    
    var body: some View {
        let dayString = String(Calendar.current.component(.day, from: date))
        let shownDots = Array(dotColors.prefix(3))
        
        VStack(spacing: 2) {
            ZStack {
                if isSelected {
                    Circle()
                        .fill(Color.terra500)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .stroke(Color.terra500, lineWidth: 1)
                        .frame(width: 32, height: 32)
                }
                
                Text(dayString)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(
                        isSelected ? Color.white :
                            (isToday ? Color.terra600 : (isCurrentMonth ? HomeQuiet.ink : HomeQuiet.quiet))
                    )
            }
            .frame(height: 32)

            HStack(spacing: 2) {
                ForEach(Array(shownDots.enumerated()), id: \.offset) { _, color in
                    Circle()
                        .fill(color)
                        .frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(isCurrentMonth ? 1 : 0.4)
        }
        .frame(height: 42)
        .contentShape(Rectangle())
        .accessibilityLabel(dotAccessibility)
    }

    private var dotAccessibility: String {
        let day = String(Calendar.current.component(.day, from: date))
        let count = dotColors.count
        if count == 0 { return day }
        if count == 1 { return "\(day), 1 calendar event" }
        return "\(day), \(count) calendar events"
    }
}

struct EventListItem: View {
    let event: CalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(HomeQuiet.ink.opacity(0.35))
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "Event")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                
                Text(timeString)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
            }
            Spacer()
        }
        .padding(14)
        .homeQuietCard()
    }
    
    private var timeString: String {
        if event.isAllDay { return "All Day" }
        let f = DateFormatter()
        f.timeStyle = .short
        var s = f.string(from: event.date ?? Date())
        if let end = event.endDate {
            s += " - " + f.string(from: end)
        }
        return s
    }
}

struct CalendarTodoItem: View {
    let todo: TodoTask
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(todo.isChecked ? Color.terra500 : HomeQuiet.ink.opacity(0.28), lineWidth: 1)
                        .background {
                            Circle().fill(todo.isChecked ? Color.terra500 : Color.clear)
                        }
                    if todo.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .regular))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 16, height: 16)
                .padding(1)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .layoutPriority(1)
            .accessibilityLabel(todo.isChecked ? "Mark not done, \(todo.title)" : "Mark done, \(todo.title)")

            Button(action: onOpen) {
                Text(todo.lineText)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(todo.isChecked ? HomeQuiet.quiet : HomeQuiet.ink)
                    .strikethrough(todo.isChecked, color: HomeQuiet.quiet)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .homeQuietCard()
    }
}

struct MealListItem: View {
    let meal: MealPlan

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.terra500)
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title ?? "Meal")
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                
                Text((meal.mealType ?? "Meal").uppercased())
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.1)
                    .foregroundStyle(HomeQuiet.quiet)
            }
            Spacer()
        }
        .padding(14)
        .homeQuietCard()
    }
}

struct AppleEventListItem: View {
    let event: AppleCalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(uiColor: event.calendarColor))
                .frame(width: 7, height: 7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                
                Text("\(appleTimeString) · \(event.calendarTitle)")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(HomeQuiet.quiet)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .homeQuietCard()
    }
    
    private var appleTimeString: String {
        if event.isAllDay { return "All Day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: event.startDate) + " - " + f.string(from: event.endDate)
    }
}

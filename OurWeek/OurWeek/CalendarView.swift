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
    @State private var showAddEventSheet = false
    
    @State private var events: [CalendarEvent] = []
    @State private var meals: [MealPlan] = []
    @State private var appleEvents: [AppleCalendarEvent] = []
    @State private var monthEvents: [CalendarEvent] = []
    @State private var monthAppleEvents: [AppleCalendarEvent] = []
    
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
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.gray)
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
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.top, 16)
                            .padding(.horizontal)
                        
                        if events.isEmpty && meals.isEmpty && appleEvents.isEmpty {
                            Text("No events or meals")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.gray)
                                .padding(.horizontal)
                        } else {
                            ForEach(events, id: \.objectID) { event in
                                EventListItem(event: event)
                                    .padding(.horizontal)
                            }
                            ForEach(appleEvents) { appleEvent in
                                AppleEventListItem(event: appleEvent)
                                    .padding(.horizontal)
                            }
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
            .sheet(isPresented: $showAddEventSheet, onDismiss: {
                loadData()
                loadMonthDots()
            }) {
                AddEventSheet(date: selectedDate, dataManager: dataManager)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text(monthYearString)
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.lilac600)
            
            Spacer()
            
            Button {
                selectedDate = calendar.startOfDay(for: Date())
                monthOffset = 0
            } label: {
                Text("Today")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.terra500)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.terra100)
                    .clipShape(Capsule())
            }
            
            Button {
                showAddEventSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(Color.lilac500)
                    .clipShape(Circle())
            }
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
        return Color.lilac500
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
                        .fill(Color.lilac500)
                        .frame(width: 32, height: 32)
                } else if isToday {
                    Circle()
                        .fill(Color.lime100)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().stroke(Color.lime500, lineWidth: 2))
                }
                
                Text(dayString)
                    .font(.system(size: 16, weight: isSelected || isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(
                        isSelected ? .white :
                            (isToday ? Color.lime500 : (isCurrentMonth ? .primary : .gray.opacity(0.4)))
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
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.lilac500)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title ?? "Event")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(timeString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .boldShadowSm(Color.lilac100)
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

struct MealListItem: View {
    let meal: MealPlan
    
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
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.terra500)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(mealEmoji(for: meal.mealType ?? "")) \(meal.title ?? "Meal")")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                HStack {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 10))
                    Text(meal.mealType ?? "Meal")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .boldShadowSm(Color.terra100)
    }
}

struct AppleEventListItem: View {
    let event: AppleCalendarEvent
    
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: event.calendarColor))
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(uiColor: event.calendarColor))
                    Text(event.title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text(appleTimeString)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    Text("·")
                    Text(event.calendarTitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .italic()
                }
                .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .boldShadowSm(Color(uiColor: event.calendarColor).opacity(0.25))
    }
    
    private var appleTimeString: String {
        if event.isAllDay { return "All Day" }
        let f = DateFormatter()
        f.timeStyle = .short
        return f.string(from: event.startDate) + " - " + f.string(from: event.endDate)
    }
}

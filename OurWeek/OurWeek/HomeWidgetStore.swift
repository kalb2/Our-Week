import CoreData
import Foundation
import WidgetKit

/// Today and tomorrow, shared with the Home Screen widget through the app group.
/// The widget is a separate process, so the snapshot is a file in the group container.
/// UserDefaults is only a backup of that same JSON.
enum HomeWidgetStore {
    static let kind = "HomeToday"
    static let snapshotKey = "home.widget.snapshot"
    static let fileName = "home-widget-snapshot.json"
    static let needsRefresh = Notification.Name("HomeWidgetNeedsRefresh")

    struct Line: Codable, Equatable {
        var time: String
        var title: String
    }

    struct Day: Codable, Equatable {
        var day: String
        var meals: [String]
        var events: [Line]
        var todos: [Line]
    }

    struct Snapshot: Codable, Equatable {
        var days: [Day]
        /// To-dos with no date. They stay on today, including after midnight refreshes the timeline.
        var undatedTodos: [Line]
    }

    private static var lastTodoRaw = ""
    private static var isPublishing = false

    /// Writes today and tomorrow from the store. One write, so meals, events, and to-dos cannot wipe each other.
    @MainActor
    static func publish(dataManager: DataManager, calendarSync: CalendarSyncManager) {
        guard !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }

        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: start) else { return }

        let meals = dataManager.fetchWeekMealPlans(from: start)
        let localEvents = dataManager.fetchEvents(from: start, to: dayAfterTomorrow)
        let appleEvents = calendarSync.fetchWeekEvents(from: start)
        let raw = UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
        lastTodoRaw = raw

        var days: [Day] = []
        for offset in 0..<2 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            days.append(
                makeDay(
                    date,
                    now: now,
                    meals: meals,
                    localEvents: localEvents,
                    appleEvents: appleEvents,
                    todosRaw: raw
                )
            )
        }
        save(Snapshot(days: days, undatedTodos: undatedTodos(raw: raw)))
        reload()
    }

    /// Reads the Home to-do list and refreshes those lines without erasing meals or events.
    static func noteTodosChanged() {
        let raw = UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
        guard raw != lastTodoRaw else { return }
        lastTodoRaw = raw

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        var snapshot = load()
        for offset in 0..<2 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let key = TodoTask.dayKey(for: date)
            let todos = todoLines(on: date, raw: raw)
            if let index = snapshot.days.firstIndex(where: { $0.day == key }) {
                snapshot.days[index].todos = todos
            } else {
                snapshot.days.append(Day(day: key, meals: [], events: [], todos: todos))
            }
        }
        snapshot.undatedTodos = undatedTodos(raw: raw)
        save(snapshot)
        reload()
    }

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func makeDay(
        _ date: Date,
        now: Date,
        meals: [MealPlan],
        localEvents: [CalendarEvent],
        appleEvents: [AppleCalendarEvent],
        todosRaw: String
    ) -> Day {
        Day(
            day: TodoTask.dayKey(for: date),
            meals: dinnerTitles(on: date, meals: meals),
            events: eventLines(on: date, now: now, localEvents: localEvents, appleEvents: appleEvents),
            todos: todoLines(on: date, raw: todosRaw)
        )
    }

    private static func dinnerTitles(on date: Date, meals: [MealPlan]) -> [String] {
        let calendar = Calendar.current
        return meals
            .filter { meal in
                guard let mealDate = meal.date else { return false }
                guard calendar.isDate(mealDate, inSameDayAs: date) else { return false }
                return (meal.mealType ?? "dinner").lowercased() == "dinner"
            }
            .sorted { lhs, rhs in
                let left = lhs.date ?? .distantPast
                let right = rhs.date ?? .distantPast
                if left != right { return left < right }
                return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
            }
            .compactMap { meal -> String? in
                let title = (meal.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return title.isEmpty ? nil : title
            }
    }

    private static func eventLines(
        on date: Date,
        now: Date,
        localEvents: [CalendarEvent],
        appleEvents: [AppleCalendarEvent]
    ) -> [Line] {
        guard showEvents else { return [] }
        var stamps: [EventStamp] = []
        for event in localEvents where eventOccurs(event, on: date) {
            let title = (event.title ?? "Event").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            stamps.append(
                EventStamp(
                    time: timeLabel(date: event.date, allDay: event.isAllDay),
                    title: title,
                    sort: event.date ?? .distantPast,
                    allDay: event.isAllDay
                )
            )
        }
        for event in appleEvents where event.occurs(on: date) {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            stamps.append(
                EventStamp(
                    time: timeLabel(date: event.startDate, allDay: event.isAllDay),
                    title: title,
                    sort: event.startDate,
                    allDay: event.isAllDay
                )
            )
        }
        stamps.sort {
            if $0.sort != $1.sort { return $0.sort < $1.sort }
            return $0.title < $1.title
        }

        let upcoming = stamps.filter { stamp in
            if stamp.allDay { return true }
            guard Calendar.current.isDateInToday(date) else { return true }
            return stamp.sort >= now.addingTimeInterval(-15 * 60)
        }
        let chosen = (upcoming.isEmpty ? stamps : upcoming).prefix(4)
        return chosen.map { Line(time: $0.time, title: $0.title) }
    }

    private struct EventStamp {
        var time: String
        var title: String
        var sort: Date
        var allDay: Bool
    }

    private static func eventOccurs(_ event: CalendarEvent, on date: Date) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start),
              let eventStart = event.date else { return false }
        if let eventEnd = event.endDate, eventEnd > eventStart {
            return eventStart < end && eventEnd > start
        }
        return calendar.isDate(eventStart, inSameDayAs: date)
    }

    private static func timeLabel(date: Date?, allDay: Bool) -> String {
        if allDay { return "All day" }
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Dated to-dos for that day. Undated to-dos are stored separately and shown on today.
    private static func todoLines(on date: Date, raw: String) -> [Line] {
        guard let wrapper = TodosWrapper(rawValue: raw) else { return [] }
        let key = TodoTask.dayKey(for: date)
        return lines(from: wrapper.todos.filter { $0.dueDay == key })
    }

    private static func undatedTodos(raw: String) -> [Line] {
        guard let wrapper = TodosWrapper(rawValue: raw) else { return [] }
        return lines(from: wrapper.todos.filter { $0.dueDay == nil })
    }

    private static func lines(from todos: [TodoTask]) -> [Line] {
        todos.compactMap { todo in
            guard !todo.isChecked else { return nil }
            let title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Line(time: todo.timeText ?? "", title: title)
        }
    }

    private static var showEvents: Bool {
        UserDefaults.standard.object(forKey: "homeShowWeekEvents") as? Bool ?? true
    }

    private static func load() -> Snapshot {
        if let data = fileData(),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        guard let defaults = UserDefaults(suiteName: ShareImportStore.appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(days: [], undatedTodos: [])
        }
        return snapshot
    }

    private static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let url = fileURL() {
            try? data.write(to: url, options: .atomic)
        }
        if let defaults = UserDefaults(suiteName: ShareImportStore.appGroupID) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    private static func fileData() -> Data? {
        guard let url = fileURL() else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(fileName)
    }
}

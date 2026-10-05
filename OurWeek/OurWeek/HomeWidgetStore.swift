import CoreData
import Foundation
import WidgetKit

/// Today and tomorrow, shared with the Home Screen widget through the app group.
/// The widget is a separate process, so the snapshot is a file in the group container.
/// The file is the only write. App-group UserDefaults would post didChangeNotification and publish again.
enum HomeWidgetStore {
    static let kind = "HomeToday"
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

    private static var lastTodoRaw: String?
    private static var lastWritten: Snapshot?
    private static var dataManager: DataManager?
    private static var appleEvents: [AppleCalendarEvent] = []
    private static var debounce: Task<Void, Never>?

    /// Coalesces widget updates. Returns immediately. Does not touch EventKit.
    /// Apple events must already be in memory; pass the week the UI has loaded.
    @MainActor
    static func schedule(dataManager: DataManager, appleEvents: [AppleCalendarEvent]) {
        self.dataManager = dataManager
        self.appleEvents = appleEvents
        arm()
    }

    /// To-do edits. Ignores every other UserDefaults change so a snapshot write cannot republish.
    @MainActor
    static func noteTodosChanged() {
        let raw = UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
        guard raw != lastTodoRaw else { return }
        lastTodoRaw = raw
        guard dataManager != nil else { return }
        arm()
    }

    /// Writes the pending snapshot now. Used when the app backgrounds, before the process is suspended.
    @MainActor
    static func flush() {
        debounce?.cancel()
        debounce = nil
        commit(reloadEvenIfUnchanged: true)
    }

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    @MainActor
    private static func arm() {
        debounce?.cancel()
        debounce = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            commit(reloadEvenIfUnchanged: false)
        }
    }

    /// Local Core Data and the to-do list only. Apple events are the array already loaded.
    @MainActor
    private static func commit(reloadEvenIfUnchanged: Bool) {
        guard let dataManager else {
            if reloadEvenIfUnchanged { reload() }
            return
        }
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        guard let dayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        let meals = dataManager.fetchWeekMealPlans(from: start)
        let localEvents = dataManager.fetchEvents(from: start, to: dayAfterTomorrow)
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
        let snapshot = Snapshot(days: days, undatedTodos: undatedTodos(raw: raw))
        if snapshot == lastWritten {
            if reloadEvenIfUnchanged { reload() }
            return
        }
        guard save(snapshot) else { return }
        lastWritten = snapshot
        reload()
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

    /// File only. Writing the app-group UserDefaults posts didChangeNotification and republishes.
    @discardableResult
    private static func save(_ snapshot: Snapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot), let url = fileURL() else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(fileName)
    }
}

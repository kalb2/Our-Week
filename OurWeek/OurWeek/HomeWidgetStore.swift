import CoreData
import CoreFoundation
import Foundation
import UIKit
import WidgetKit

/// Today and tomorrow, shared with the Home Screen widget through the app group.
/// The widget is a separate process, so the snapshot is a file in the group container.
/// The file is the only write. App-group UserDefaults would post didChangeNotification and publish again.
enum HomeWidgetStore {
    static let kind = "HomeToday"
    static let fileName = "home-widget-snapshot.json"
    static let todosFileName = "home-todos.json"
    static let togglesFileName = "home-todo-toggles.json"
    static let widgetTodoNote = "com.kalebjensen.OurWeek.widgetTodo" as CFString
    static let needsRefresh = Notification.Name("HomeWidgetNeedsRefresh")

    struct Line: Codable, Equatable {
        var time: String
        var title: String
        var id: String? = nil
        var done: Bool = false
        var red: Double? = nil
        var green: Double? = nil
        var blue: Double? = nil
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
    private static var observingWidgetToggles = false

    /// Copies checkbox taps from the widget into the to-do list. Safe to call on every foreground.
    @MainActor
    static func applyWidgetTodoEdits() {
        let toggles = readToggles()
        guard !toggles.isEmpty else { return }
        let raw = UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
        guard var wrapper = TodosWrapper(rawValue: raw) else { return }
        var changed = false
        for toggle in toggles {
            guard let index = wrapper.todos.firstIndex(where: { $0.id == toggle.id }) else { continue }
            guard wrapper.todos[index].isChecked != toggle.done else { continue }
            wrapper.todos[index].isChecked = toggle.done
            changed = true
        }
        if changed {
            UserDefaults.standard.set(TodosWrapper(todos: wrapper.todos).rawValue, forKey: "homeTodosWrapper")
        }
        clearToggles()
    }

    /// Drops a widget checkbox intent for this to-do so a later snapshot cannot undo an in-app tap.
    @MainActor
    static func discardWidgetToggle(id: UUID) {
        guard let url = groupFileURL(togglesFileName),
              let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        let remaining = items.filter { item in
            guard let text = item["id"] as? String, let parsed = UUID(uuidString: text) else { return true }
            return parsed != id
        }
        guard remaining.count != items.count else { return }
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let written = try? JSONSerialization.data(withJSONObject: remaining) {
            try? written.write(to: url, options: .atomic)
        }
    }

    /// Wakes when a widget checkbox writes the shared toggle file.
    @MainActor
    static func startObservingWidgetToggles() {
        guard !observingWidgetToggles else { return }
        observingWidgetToggles = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            homeWidgetTodoNotificationCallback,
            widgetTodoNote,
            nil,
            .deliverImmediately
        )
    }

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
        applyWidgetTodoEdits()
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
        saveTodosRaw(raw)

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
            let parts = colorParts(fromHex: event.color)
            stamps.append(
                EventStamp(
                    time: timeLabel(date: event.date, allDay: event.isAllDay),
                    title: title,
                    sort: event.date ?? .distantPast,
                    allDay: event.isAllDay,
                    red: parts?.0,
                    green: parts?.1,
                    blue: parts?.2
                )
            )
        }
        for event in appleEvents where event.occurs(on: date) {
            let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let parts = colorParts(of: event.calendarColor)
            stamps.append(
                EventStamp(
                    time: timeLabel(date: event.startDate, allDay: event.isAllDay),
                    title: title,
                    sort: event.startDate,
                    allDay: event.isAllDay,
                    red: parts?.0,
                    green: parts?.1,
                    blue: parts?.2
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
        return chosen.map {
            Line(time: $0.time, title: $0.title, red: $0.red, green: $0.green, blue: $0.blue)
        }
    }

    private struct EventStamp {
        var time: String
        var title: String
        var sort: Date
        var allDay: Bool
        var red: Double?
        var green: Double?
        var blue: Double?
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
            let title = todo.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Line(
                time: todo.timeText ?? "",
                title: title,
                id: todo.id.uuidString,
                done: todo.isChecked
            )
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

    private static func colorParts(of color: UIColor) -> (Double, Double, Double)? {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (Double(red), Double(green), Double(blue))
        }
        guard let components = resolved.cgColor.components, components.count >= 3 else { return nil }
        return (Double(components[0]), Double(components[1]), Double(components[2]))
    }

    private static func colorParts(fromHex token: String?) -> (Double, Double, Double)? {
        guard var hex = token?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return (red, green, blue)
    }

    /// The widget reads this file to flip a checkbox. It is not UserDefaults, so it cannot republish.
    private static func saveTodosRaw(_ raw: String) {
        let text = raw.isEmpty ? "[]" : raw
        guard let url = groupFileURL(todosFileName) else { return }
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == text { return }
        try? Data(text.utf8).write(to: url, options: .atomic)
    }

    private struct TodoToggle {
        var id: UUID
        var done: Bool
    }

    private static func readToggles() -> [TodoToggle] {
        guard let url = groupFileURL(togglesFileName),
              let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let idText = item["id"] as? String, let id = UUID(uuidString: idText) else { return nil }
            let done: Bool
            if let value = item["done"] as? Bool {
                done = value
            } else if let value = item["done"] as? NSNumber {
                done = value.boolValue
            } else {
                return nil
            }
            return TodoToggle(id: id, done: done)
        }
    }

    private static func clearToggles() {
        guard let url = groupFileURL(togglesFileName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func fileURL() -> URL? {
        groupFileURL(fileName)
    }

    private static func groupFileURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent(name)
    }
}

nonisolated private let homeWidgetTodoNotificationCallback: CFNotificationCallback = { _, _, _, _, _ in
    Task { @MainActor in
        HomeWidgetStore.applyWidgetTodoEdits()
    }
}

import Foundation
import WidgetKit

/// Today, shared with the Home Screen widget through the app group.
enum HomeWidgetStore {
    static let kind = "HomeToday"
    static let snapshotKey = "home.widget.snapshot"

    struct Line: Codable, Equatable {
        var time: String
        var title: String
    }

    struct Snapshot: Codable, Equatable {
        var meals: [String]
        var events: [Line]
        var todos: [Line]

        static let empty = Snapshot(meals: [], events: [], todos: [])
    }

    private static var lastTodoRaw = ""

    static func updateDay(meals: [String], events: [Line]) {
        var snapshot = load()
        snapshot.meals = meals
        snapshot.events = events
        save(snapshot)
        reload()
    }

    /// Reads the Home to-do list and refreshes the widget when that list changed.
    static func noteTodosChanged() {
        let raw = UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
        guard raw != lastTodoRaw else { return }
        lastTodoRaw = raw
        var snapshot = load()
        snapshot.todos = todayTodos(from: raw)
        save(snapshot)
        reload()
    }

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func todayTodos(from raw: String) -> [Line] {
        guard let wrapper = TodosWrapper(rawValue: raw) else { return [] }
        let today = Date()
        return wrapper.todos
            .filter { $0.occurs(on: today) && !$0.isChecked }
            .map { Line(time: $0.timeText ?? "", title: $0.title) }
    }

    private static func load() -> Snapshot {
        guard let defaults = UserDefaults(suiteName: ShareImportStore.appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    private static func save(_ snapshot: Snapshot) {
        guard let defaults = UserDefaults(suiteName: ShareImportStore.appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }
}

import AppIntents
import SwiftUI
import WidgetKit

/// Today on the Home Screen. The main app writes the same snapshot file into the app group.
private enum WidgetSnapshotStore {
    static let appGroupID = "group.com.kalebjensen.OurWeek"
    static let snapshotKey = "home.widget.snapshot"
    static let fileName = "home-widget-snapshot.json"
    static let todosFileName = "home-todos.json"
    static let togglesFileName = "home-todo-toggles.json"
    static let widgetTodoNote = "com.kalebjensen.OurWeek.widgetTodo" as CFString

    struct Line: Codable {
        var time: String
        var title: String
        var id: String?
        var done: Bool
        var red: Double?
        var green: Double?
        var blue: Double?

        init(
            time: String,
            title: String,
            id: String? = nil,
            done: Bool = false,
            red: Double? = nil,
            green: Double? = nil,
            blue: Double? = nil
        ) {
            self.time = time
            self.title = title
            self.id = id
            self.done = done
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            time = try container.decodeIfPresent(String.self, forKey: .time) ?? ""
            title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
            id = try container.decodeIfPresent(String.self, forKey: .id)
            done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
            red = try container.decodeIfPresent(Double.self, forKey: .red)
            green = try container.decodeIfPresent(Double.self, forKey: .green)
            blue = try container.decodeIfPresent(Double.self, forKey: .blue)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(time, forKey: .time)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(done, forKey: .done)
            try container.encodeIfPresent(red, forKey: .red)
            try container.encodeIfPresent(green, forKey: .green)
            try container.encodeIfPresent(blue, forKey: .blue)
        }
    }

    struct Day: Codable {
        var day: String
        var meals: [String]
        var events: [Line]
        var todos: [Line]
    }

    struct Snapshot: Codable {
        var days: [Day]
        var undatedTodos: [Line]
    }

    static func load() -> Snapshot {
        if let url = fileURL(),
           let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(days: [], undatedTodos: [])
        }
        return snapshot
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }
}

private struct HomeEntry: TimelineEntry {
    var date: Date
    var meals: [String]
    var events: [WidgetSnapshotStore.Line]
    var todos: [WidgetSnapshotStore.Line]
}

private struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(
            date: Date(),
            meals: ["Chicken tortilla soup"],
            events: [WidgetSnapshotStore.Line(time: "6:30 PM", title: "Practice")],
            todos: [WidgetSnapshotStore.Line(time: "8:00 AM", title: "Grocery run")]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let entries = [
            entry(for: now),
            entry(for: midnight)
        ]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    private func entry(for date: Date) -> HomeEntry {
        let snapshot = WidgetSnapshotStore.load()
        let key = WidgetSnapshotStore.dayKey(for: date)
        let day = snapshot.days.first { $0.day == key }
        // Undated to-dos stay on whichever day is on screen, including the midnight entry.
        let todos = (day?.todos ?? []) + snapshot.undatedTodos
        return HomeEntry(
            date: date,
            meals: day?.meals ?? [],
            events: day?.events ?? [],
            todos: todos
        )
    }
}

private struct HomeWidgetView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    private let quiet = Color(red: 0.45, green: 0.42, blue: 0.40)
    private let terra = Color(red: 0.878, green: 0.478, blue: 0.373)
    private let cream = Color(red: 1.0, green: 0.976, blue: 0.965)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(cream, for: .widget)
            .widgetURL(URL(string: "ourweek://home"))
    }

    private var content: some View {
        Group {
            if family == .systemSmall {
                small
            } else {
                medium
            }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            dayHeading(nameSize: 16, dateSize: 11)
            mealBlock(text: entry.meals.first ?? "Add dinner", size: 18, limit: 3)
            if let todo = entry.todos.first {
                todoRow(todo, limit: 1)
            }
            if let event = entry.events.first {
                eventRow(event, limit: 2)
            }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            dayHeading(nameSize: 18, dateSize: 12)
            mealBlock(text: joinedMeals, size: 22, limit: 2)
            if !entry.events.isEmpty || !entry.todos.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    if !entry.todos.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.todos.prefix(3).enumerated()), id: \.offset) { _, line in
                                todoRow(line, limit: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !entry.events.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.events.prefix(2).enumerated()), id: \.offset) { _, line in
                                eventRow(line, limit: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func dayHeading(nameSize: CGFloat, dateSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(weekdayName)
                .font(.system(size: nameSize, weight: .regular, design: .serif))
                .foregroundStyle(terra)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .widgetAccentable()
            Text(dateLabel)
                .font(.system(size: dateSize, weight: .regular))
                .foregroundStyle(quiet)
                .lineLimit(1)
                .widgetAccentable()
        }
    }

    /// Full weekday, then a quieter month-and-day. Uses the timeline entry date so midnight shows the new day.
    private var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: entry.date)
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: entry.date)
    }

    private var joinedMeals: String {
        let titles = entry.meals.prefix(2)
        if titles.isEmpty { return "Add dinner" }
        return titles.joined(separator: "\n")
    }

    private func mealBlock(text: String, size: CGFloat, limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            mealTitle(text, size: size, limit: limit, isPlaceholder: entry.meals.isEmpty)
            hairline
        }
    }

    private func mealTitle(_ text: String, size: CGFloat, limit: Int, isPlaceholder: Bool) -> some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(isPlaceholder ? quiet : ink)
            .lineLimit(limit)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
            .widgetAccentable()
    }

    private var hairline: some View {
        Rectangle()
            .fill(terra.opacity(0.45))
            .frame(height: 1)
            .widgetAccentable()
    }

    @ViewBuilder
    private func todoRow(_ line: WidgetSnapshotStore.Line, limit: Int) -> some View {
        if let id = line.id, !id.isEmpty {
            Button(intent: ToggleTodoIntent(todoID: id)) {
                todoLabel(line, limit: limit)
            }
            .buttonStyle(.plain)
        } else {
            todoLabel(line, limit: limit)
        }
    }

    private func todoLabel(_ line: WidgetSnapshotStore.Line, limit: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            checkbox(done: line.done)
            Text(lineLabel(line))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(quiet)
                .strikethrough(line.done, color: quiet)
                .lineLimit(limit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.done ? "Mark not done, \(line.title)" : "Mark done, \(line.title)")
    }

    private func eventRow(_ line: WidgetSnapshotStore.Line, limit: Int) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(eventColor(line))
                .frame(width: 7, height: 7)
            Text(lineLabel(line))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(quiet)
                .lineLimit(limit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .widgetAccentable()
    }

    private func checkbox(done: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(done ? terra : ink.opacity(0.28), lineWidth: 1)
                .background(
                    Circle()
                        .fill(done ? terra : Color.clear)
                )
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 14, height: 14)
        .widgetAccentable()
    }

    private func eventColor(_ line: WidgetSnapshotStore.Line) -> Color {
        guard let red = line.red, let green = line.green, let blue = line.blue else {
            return Color.black.opacity(0.28)
        }
        return Color(red: red, green: green, blue: blue)
    }

    private func lineLabel(_ line: WidgetSnapshotStore.Line) -> String {
        line.time.isEmpty ? line.title : "\(line.time)  \(line.title)"
    }
}

/// Checkbox tap. Stays in the widget. The shared toggle file is what the app applies, then Reminders sync pushes.
struct ToggleTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle to-do"
    static var openAppWhenRun = false

    @Parameter(title: "To-do")
    var todoID: String

    init() {
        todoID = ""
    }

    init(todoID: String) {
        self.todoID = todoID
    }

    func perform() async throws -> some IntentResult {
        WidgetTodoToggle.apply(id: todoID)
        return .result()
    }
}

private enum WidgetTodoToggle {
    static func apply(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let done = flippedDone(id: trimmed)
        recordToggle(id: trimmed, done: done)
        patchSnapshot(id: trimmed, done: done)
        WidgetCenter.shared.reloadTimelines(ofKind: "HomeToday")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            WidgetSnapshotStore.widgetTodoNote,
            nil,
            nil,
            true
        )
    }

    /// Flips the shared to-do file and returns the new done state. Snapshot is the fallback.
    private static func flippedDone(id: String) -> Bool {
        guard let url = fileURL(WidgetSnapshotStore.todosFileName),
              let data = try? Data(contentsOf: url),
              var todos = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return !snapshotDone(id: id)
        }
        var found = false
        var done = true
        for index in todos.indices {
            let current = (todos[index]["id"] as? String) ?? ""
            guard current.caseInsensitiveCompare(id) == .orderedSame else { continue }
            done = !boolValue(todos[index]["isChecked"])
            todos[index]["isChecked"] = done
            found = true
        }
        guard found, let written = try? JSONSerialization.data(withJSONObject: todos) else {
            return !snapshotDone(id: id)
        }
        try? written.write(to: url, options: .atomic)
        return done
    }

    private static func snapshotDone(id: String) -> Bool {
        guard let url = fileURL(WidgetSnapshotStore.fileName),
              let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        var lines: [[String: Any]] = []
        if let days = root["days"] as? [[String: Any]] {
            for day in days {
                lines.append(contentsOf: day["todos"] as? [[String: Any]] ?? [])
            }
        }
        lines.append(contentsOf: root["undatedTodos"] as? [[String: Any]] ?? [])
        for line in lines {
            let current = (line["id"] as? String) ?? ""
            guard current.caseInsensitiveCompare(id) == .orderedSame else { continue }
            return boolValue(line["done"])
        }
        return false
    }

    private static func recordToggle(id: String, done: Bool) {
        guard let url = fileURL(WidgetSnapshotStore.togglesFileName) else { return }
        var items = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
        } ?? []
        if let index = items.firstIndex(where: { (($0["id"] as? String) ?? "").caseInsensitiveCompare(id) == .orderedSame }) {
            items[index]["done"] = done
            items[index]["id"] = id
        } else {
            items.append(["id": id, "done": done])
        }
        guard let written = try? JSONSerialization.data(withJSONObject: items) else { return }
        try? written.write(to: url, options: .atomic)
    }

    private static func patchSnapshot(id: String, done: Bool) {
        guard let url = fileURL(WidgetSnapshotStore.fileName),
              let data = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        func patch(_ lines: inout [[String: Any]]) {
            for index in lines.indices {
                let current = (lines[index]["id"] as? String) ?? ""
                guard current.caseInsensitiveCompare(id) == .orderedSame else { continue }
                lines[index]["done"] = done
            }
        }

        if var days = root["days"] as? [[String: Any]] {
            for index in days.indices {
                var todos = days[index]["todos"] as? [[String: Any]] ?? []
                patch(&todos)
                days[index]["todos"] = todos
            }
            root["days"] = days
        }
        if var undated = root["undatedTodos"] as? [[String: Any]] {
            patch(&undated)
            root["undatedTodos"] = undated
        }
        guard let written = try? JSONSerialization.data(withJSONObject: root) else { return }
        try? written.write(to: url, options: .atomic)
    }

    private static func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return false
    }

    private static func fileURL(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshotStore.appGroupID)?
            .appendingPathComponent(name)
    }
}

struct HomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HomeToday", provider: HomeProvider()) { entry in
            HomeWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Tonight's meal, the next events, and today's to-dos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OurWeekWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
    }
}

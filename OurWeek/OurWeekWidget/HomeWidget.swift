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
    static let goalBumpsFileName = "home-goal-bumps.json"
    static let widgetTodoNote = "com.kalebjensen.OurWeek.widgetTodo" as CFString
    static let widgetGoalNote = "com.kalebjensen.OurWeek.widgetGoal" as CFString

    struct Line: Codable {
        var time: String
        var title: String
        var id: String?
        var done: Bool
        var red: Double?
        var green: Double?
        var blue: Double?

        private enum CodingKeys: String, CodingKey {
            case time, title, id, done, red, green, blue
        }

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

    struct GoalLine: Codable {
        var id: String
        var name: String
        var kind: String
        var period: String
        var current: Double
        var solo: Double
        var target: Double
        var step: Double
        var day: String
        var red: Double
        var green: Double
        var blue: Double

        private enum CodingKeys: String, CodingKey {
            case id, name, kind, period, current, solo, target, step, day, red, green, blue
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
            kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "count"
            period = try container.decodeIfPresent(String.self, forKey: .period) ?? "day"
            current = try container.decodeIfPresent(Double.self, forKey: .current) ?? 0
            solo = try container.decodeIfPresent(Double.self, forKey: .solo) ?? 0
            target = try container.decodeIfPresent(Double.self, forKey: .target) ?? 1
            step = try container.decodeIfPresent(Double.self, forKey: .step) ?? 1
            day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
            red = try container.decodeIfPresent(Double.self, forKey: .red) ?? 0.878
            green = try container.decodeIfPresent(Double.self, forKey: .green) ?? 0.478
            blue = try container.decodeIfPresent(Double.self, forKey: .blue) ?? 0.373
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            try container.encode(kind, forKey: .kind)
            try container.encode(period, forKey: .period)
            try container.encode(current, forKey: .current)
            try container.encode(solo, forKey: .solo)
            try container.encode(target, forKey: .target)
            try container.encode(step, forKey: .step)
            try container.encode(day, forKey: .day)
            try container.encode(red, forKey: .red)
            try container.encode(green, forKey: .green)
            try container.encode(blue, forKey: .blue)
        }
    }

    struct Day: Codable {
        var day: String
        var meals: [String]
        var events: [Line]
        var todos: [Line]
        var goals: [GoalLine]

        private enum CodingKeys: String, CodingKey {
            case day, meals, events, todos, goals
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            day = try container.decodeIfPresent(String.self, forKey: .day) ?? ""
            meals = try container.decodeIfPresent([String].self, forKey: .meals) ?? []
            events = try container.decodeIfPresent([Line].self, forKey: .events) ?? []
            todos = try container.decodeIfPresent([Line].self, forKey: .todos) ?? []
            goals = try container.decodeIfPresent([GoalLine].self, forKey: .goals) ?? []
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(day, forKey: .day)
            try container.encode(meals, forKey: .meals)
            try container.encode(events, forKey: .events)
            try container.encode(todos, forKey: .todos)
            try container.encode(goals, forKey: .goals)
        }
    }

    struct Snapshot: Codable {
        var days: [Day]
        var undatedTodos: [Line]
        var resetMinutes: Int

        private enum CodingKeys: String, CodingKey {
            case days, undatedTodos, resetMinutes
        }

        init(days: [Day], undatedTodos: [Line], resetMinutes: Int = 0) {
            self.days = days
            self.undatedTodos = undatedTodos
            self.resetMinutes = resetMinutes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            days = try container.decodeIfPresent([Day].self, forKey: .days) ?? []
            undatedTodos = try container.decodeIfPresent([Line].self, forKey: .undatedTodos) ?? []
            resetMinutes = try container.decodeIfPresent(Int.self, forKey: .resetMinutes) ?? 0
        }
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
    var goals: [WidgetSnapshotStore.GoalLine]
}

private struct HomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeEntry {
        HomeEntry(
            date: Date(),
            meals: ["Chicken tortilla soup"],
            events: [WidgetSnapshotStore.Line(time: "6:30 PM", title: "Practice")],
            todos: [WidgetSnapshotStore.Line(time: "8:00 AM", title: "Grocery run")],
            goals: []
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.load()
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.startOfDay(for: now)
        let midnight = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        var dates = [now, midnight]
        if snapshot.resetMinutes > 0 {
            let resetToday = start.addingTimeInterval(TimeInterval(snapshot.resetMinutes * 60))
            if resetToday > now {
                dates.append(resetToday)
            }
            if let resetTomorrow = calendar.date(byAdding: .day, value: 1, to: resetToday), resetTomorrow > now {
                dates.append(resetTomorrow)
            }
        }
        dates.sort()
        let entries = dates.map { entry(for: $0, snapshot: snapshot) }
        let refresh = dates.last ?? midnight
        completion(Timeline(entries: entries, policy: .after(refresh.addingTimeInterval(60))))
    }

    private func entry(for date: Date, snapshot loaded: WidgetSnapshotStore.Snapshot? = nil) -> HomeEntry {
        let snapshot = loaded ?? WidgetSnapshotStore.load()
        let key = WidgetSnapshotStore.dayKey(for: date)
        let day = snapshot.days.first { $0.day == key }
        let goalDate = date.addingTimeInterval(TimeInterval(-snapshot.resetMinutes * 60))
        let goalKey = WidgetSnapshotStore.dayKey(for: goalDate)
        let goalDay = goalKey == key ? day : snapshot.days.first { $0.day == goalKey }
        // Undated to-dos stay on whichever day is on screen, including the midnight entry.
        let todos = (day?.todos ?? []) + snapshot.undatedTodos
        return HomeEntry(
            date: date,
            meals: day?.meals ?? [],
            events: day?.events ?? [],
            todos: todos,
            goals: goalDay?.goals ?? []
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
        VStack(alignment: .leading, spacing: entry.goals.isEmpty ? 6 : 4) {
            dayHeading(nameSize: 16, dateSize: 11)
            mealBlock(text: entry.meals.first ?? "Add dinner", size: entry.goals.isEmpty ? 18 : 16, limit: entry.goals.isEmpty ? 3 : 2)
            if !entry.goals.isEmpty {
                goalMarks
            }
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
            if !entry.goals.isEmpty {
                goalMarks
            }
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

    private var goalMarks: some View {
        HStack(spacing: 8) {
            ForEach(Array(entry.goals.prefix(3).enumerated()), id: \.offset) { _, goal in
                Button(intent: BumpGoalIntent(goalID: goal.id, day: goal.day, op: goal.kind == "check" ? "toggle" : "increment")) {
                    goalMark(goal)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func goalMark(_ goal: WidgetSnapshotStore.GoalLine) -> some View {
        let tint = Color(red: goal.red, green: goal.green, blue: goal.blue)
        let fraction = goal.target > 0 ? min(goal.current / goal.target, 1) : 0
        let checked = goal.period == "week" ? goal.solo >= 1 : fraction >= 1
        return HStack(spacing: 4) {
            if goal.kind == "check" {
                checkbox(done: checked)
            } else {
                ZStack {
                    Circle()
                        .stroke(tint.opacity(0.28), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 14, height: 14)
            }
            if family != .systemSmall {
                Text(goal.name)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(ink)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(goal.name)
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
                .strokeBorder(done ? terra : ink.opacity(0.28), lineWidth: 1)
                .background {
                    Circle().fill(done ? terra : Color.clear)
                }
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 7, weight: .regular))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 14, height: 14)
        .padding(1)
        .fixedSize()
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
            CFNotificationName(WidgetSnapshotStore.widgetTodoNote),
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

struct BumpGoalIntent: AppIntent {
    static var title: LocalizedStringResource = "Log goal"
    static var openAppWhenRun = false

    @Parameter(title: "Goal")
    var goalID: String

    @Parameter(title: "Day")
    var day: String

    @Parameter(title: "Op")
    var op: String

    init() {
        goalID = ""
        day = ""
        op = "increment"
    }

    init(goalID: String, day: String, op: String) {
        self.goalID = goalID
        self.day = day
        self.op = op
    }

    func perform() async throws -> some IntentResult {
        WidgetGoalBump.apply(goalID: goalID, day: day, op: op)
        return .result()
    }
}

private enum WidgetGoalBump {
    static func apply(goalID: String, day: String, op: String) {
        let id = goalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        patchSnapshot(id: id, day: day, op: op)
        record(id: id, day: day, op: op)
        WidgetCenter.shared.reloadTimelines(ofKind: "HomeToday")
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(WidgetSnapshotStore.widgetGoalNote),
            nil,
            nil,
            true
        )
    }

    private static func record(id: String, day: String, op: String) {
        guard let url = fileURL(WidgetSnapshotStore.goalBumpsFileName) else { return }
        var items = (try? Data(contentsOf: url)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]]
        } ?? []
        items.append([
            "bump": UUID().uuidString,
            "goal": id,
            "day": day,
            "op": op
        ])
        guard let written = try? JSONSerialization.data(withJSONObject: items) else { return }
        try? written.write(to: url, options: .atomic)
    }

    private static func patchSnapshot(id: String, day: String, op: String) {
        guard let url = fileURL(WidgetSnapshotStore.fileName),
              let data = try? Data(contentsOf: url),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var days = root["days"] as? [[String: Any]] else { return }
        for index in days.indices {
            var goals = days[index]["goals"] as? [[String: Any]] ?? []
            for goalIndex in goals.indices {
                let currentID = (goals[goalIndex]["id"] as? String) ?? ""
                guard currentID.caseInsensitiveCompare(id) == .orderedSame else { continue }
                let lineDay = (goals[goalIndex]["day"] as? String) ?? ""
                if !day.isEmpty, lineDay != day { continue }
                let kind = (goals[goalIndex]["kind"] as? String) ?? ""
                let period = (goals[goalIndex]["period"] as? String) ?? "day"
                let target = doubleValue(goals[goalIndex]["target"])
                let step = max(doubleValue(goals[goalIndex]["step"]), 1)
                var current = doubleValue(goals[goalIndex]["current"])
                var solo = doubleValue(goals[goalIndex]["solo"])
                if op == "toggle" && kind == "check" && period == "week" {
                    if solo >= 1 {
                        solo = 0
                        current = max(0, current - 1)
                    } else {
                        solo = 1
                        current += 1
                    }
                } else if op == "toggle" && kind == "check" {
                    current = current >= target ? 0 : target
                    solo = current
                } else {
                    current += step
                    solo += step
                }
                goals[goalIndex]["current"] = current
                goals[goalIndex]["solo"] = solo
            }
            days[index]["goals"] = goals
        }
        root["days"] = days
        guard let written = try? JSONSerialization.data(withJSONObject: root) else { return }
        try? written.write(to: url, options: .atomic)
    }

    private static func doubleValue(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return 0
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
        .description("Tonight's meal, today's goals, the next events, and to-dos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct OurWeekWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeWidget()
    }
}

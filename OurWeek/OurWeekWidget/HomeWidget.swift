import SwiftUI
import WidgetKit

/// Today on the Home Screen. The main app writes the same snapshot file into the app group.
private enum WidgetSnapshotStore {
    static let appGroupID = "group.com.kalebjensen.OurWeek"
    static let snapshotKey = "home.widget.snapshot"
    static let fileName = "home-widget-snapshot.json"

    struct Line: Codable {
        var time: String
        var title: String
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
        VStack(alignment: .leading, spacing: 8) {
            mealBlock(text: entry.meals.first ?? "Add dinner", size: 18, limit: 3)
            if let event = entry.events.first {
                detail(event, limit: 2)
            }
            if let todo = entry.todos.first {
                detail(todo, limit: 1)
            }
            Spacer(minLength: 0)
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 10) {
            mealBlock(text: joinedMeals, size: 22, limit: 2)
            if !entry.events.isEmpty || !entry.todos.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    if !entry.events.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.events.prefix(2).enumerated()), id: \.offset) { _, line in
                                detail(line, limit: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !entry.todos.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(entry.todos.prefix(3).enumerated()), id: \.offset) { _, line in
                                detail(line, limit: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
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

    private func detail(_ line: WidgetSnapshotStore.Line, limit: Int) -> some View {
        let text = line.time.isEmpty ? line.title : "\(line.time)  \(line.title)"
        return Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(quiet)
            .lineLimit(limit)
            .fixedSize(horizontal: false, vertical: true)
            .widgetAccentable()
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

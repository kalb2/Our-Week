import SwiftUI
import WidgetKit

/// Today on the Home Screen. The main app writes the same snapshot into the app group.
private enum WidgetSnapshotStore {
    static let appGroupID = "group.com.kalebjensen.OurWeek"
    static let snapshotKey = "home.widget.snapshot"

    struct Line: Codable {
        var time: String
        var title: String
    }

    struct Snapshot: Codable {
        var meals: [String]
        var events: [Line]
        var todos: [Line]
    }

    static func load() -> Snapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(meals: [], events: [], todos: [])
        }
        return snapshot
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
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry()], policy: .after(next)))
    }

    private func entry() -> HomeEntry {
        let snapshot = WidgetSnapshotStore.load()
        return HomeEntry(
            date: Date(),
            meals: snapshot.meals,
            events: snapshot.events,
            todos: snapshot.todos
        )
    }
}

private struct HomeWidgetView: View {
    var entry: HomeEntry
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    private let quiet = Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.55)
    private let terra = Color(red: 0.878, green: 0.478, blue: 0.373)
    private let cream = Color(red: 1.0, green: 0.976, blue: 0.965)

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(cream, for: .widget)
            .widgetURL(URL(string: "ourweek://home"))
    }

    @ViewBuilder
    private var content: some View {
        if entry.meals.isEmpty && entry.events.isEmpty && entry.todos.isEmpty {
            Text("Today is open")
                .font(.system(size: 18, weight: .regular, design: .serif))
                .foregroundStyle(quiet)
        } else if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let meal = entry.meals.first {
                mealTitle(meal, size: 18, limit: 3)
                hairline
            }
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
            if let meal = entry.meals.first {
                mealTitle(joinedMeals, size: 22, limit: 2)
                hairline
            }
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
            Spacer(minLength: 0)
        }
    }

    private var joinedMeals: String {
        entry.meals.prefix(2).joined(separator: "\n")
    }

    private func mealTitle(_ text: String, size: CGFloat, limit: Int) -> some View {
        Text(text)
            .font(.system(size: size, weight: .regular, design: .serif))
            .foregroundStyle(ink)
            .lineLimit(limit)
            .minimumScaleFactor(0.85)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var hairline: some View {
        Rectangle()
            .fill(terra.opacity(0.45))
            .frame(height: 1)
    }

    private func detail(_ line: WidgetSnapshotStore.Line, limit: Int) -> some View {
        let text = line.time.isEmpty ? line.title : "\(line.time)  \(line.title)"
        return Text(text)
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(quiet)
            .lineLimit(limit)
            .fixedSize(horizontal: false, vertical: true)
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

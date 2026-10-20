import SwiftUI
import UIKit
import WidgetKit

/// Tonight's dinner. Reads tonight-dinner.json that the app writes into the app group.
private enum TonightFile {
    static let appGroupID = "group.com.kalebjensen.OurWeek"
    static let fileName = "tonight-dinner.json"

    struct Night: Codable {
        var day: String
        var title: String
        var recipeID: String?
        var photo: String?
        var more: Int
    }

    static func load() -> [Night] {
        guard let url = folder()?.appendingPathComponent(fileName),
              let data = try? Data(contentsOf: url),
              let nights = try? JSONDecoder().decode([Night].self, from: data) else { return [] }
        return nights
    }

    static func image(_ name: String?) -> UIImage? {
        guard let name, let url = folder()?.appendingPathComponent(name) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func folder() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}

private struct TonightEntry: TimelineEntry {
    var date: Date
    var title: String?
    var recipeID: String?
    var photo: UIImage?
    var more: Int
}

private struct TonightProvider: TimelineProvider {
    func placeholder(in context: Context) -> TonightEntry {
        TonightEntry(date: Date(), title: nil, recipeID: nil, photo: nil, more: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (TonightEntry) -> Void) {
        completion(entry(for: Date(), nights: TonightFile.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TonightEntry>) -> Void) {
        let nights = TonightFile.load()
        let calendar = Calendar.current
        let now = Date()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let entries = [entry(for: now, nights: nights), entry(for: midnight, nights: nights)]
        completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
    }

    private func entry(for date: Date, nights: [TonightFile.Night]) -> TonightEntry {
        let key = TonightFile.dayKey(for: date)
        guard let night = nights.first(where: { $0.day == key }) else {
            return TonightEntry(date: date, title: nil, recipeID: nil, photo: nil, more: 0)
        }
        return TonightEntry(
            date: date,
            title: night.title,
            recipeID: night.recipeID,
            photo: TonightFile.image(night.photo),
            more: night.more
        )
    }
}

private struct TonightWidgetView: View {
    var entry: TonightEntry
    @Environment(\.widgetFamily) private var family

    private let ink = Color(red: 0.12, green: 0.11, blue: 0.10)
    private let quiet = Color(red: 0.45, green: 0.42, blue: 0.40)
    private let terra = Color(red: 0.878, green: 0.478, blue: 0.373)
    private let cream = Color(red: 1.0, green: 0.976, blue: 0.965)

    private var link: URL? {
        if let id = entry.recipeID { return URL(string: "ourweek://recipe/\(id)") }
        return URL(string: "ourweek://home")
    }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 14) {
                    if let photo = entry.photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    text
                }
            } else {
                text
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) {
            if family == .systemSmall, let photo = entry.photo {
                ZStack {
                    Image(uiImage: photo).resizable().scaledToFill()
                    LinearGradient(colors: [cream.opacity(0.0), cream.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                }
            } else {
                cream
            }
        }
        .widgetURL(link)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TONIGHT")
                .font(.system(size: 10, weight: .medium))
                .tracking(1.3)
                .foregroundStyle(terra)
            Spacer(minLength: 0)
            Text(entry.title ?? "Nothing planned")
                .font(.system(size: family == .systemMedium ? 22 : 18, weight: .regular, design: .serif))
                .foregroundStyle(entry.title == nil ? quiet : ink)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            if entry.more > 0 {
                Text("and \(entry.more) more")
                    .font(.system(size: 12))
                    .foregroundStyle(quiet)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
    }
}

struct TonightWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TonightDinner", provider: TonightProvider()) { entry in
            TonightWidgetView(entry: entry)
        }
        .configurationDisplayName("Tonight")
        .description("Tonight's dinner, with its photo when it has one.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

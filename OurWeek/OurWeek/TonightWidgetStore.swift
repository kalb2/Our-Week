import CoreData
import Foundation
import UIKit
import WidgetKit

/// Tonight's dinner for the "Tonight" widget. Written next to the Home snapshot in the app group.
/// Only files are written, never app-group UserDefaults, so nothing republishes.
enum TonightWidgetStore {
    static let kind = "TonightDinner"
    static let fileName = "tonight-dinner.json"
    static let photoPrefix = "tonight-photo-"

    struct Night: Codable, Equatable {
        var day: String
        var title: String
        /// Recipe id for the deep link. Nil for takeout, leftovers, or a typed dinner.
        var recipeID: String?
        /// Photo file in the app group, from his own recipe photo only.
        var photo: String?
        var more: Int
    }

    private static var lastWritten: [Night]?

    /// Today and tomorrow, so the midnight timeline entry is already right.
    @MainActor
    static func write(meals: [MealPlan], start: Date) {
        let calendar = Calendar.current
        var nights: [Night] = []
        var photos: [String: Data] = [:]
        for offset in 0..<2 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let dinners = meals
                .filter { meal in
                    guard let mealDate = meal.date, calendar.isDate(mealDate, inSameDayAs: date) else { return false }
                    guard (meal.mealType ?? "dinner").lowercased() == "dinner" else { return false }
                    return !(meal.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                .sorted { ($0.date ?? .distantPast, $0.id?.uuidString ?? "") < ($1.date ?? .distantPast, $1.id?.uuidString ?? "") }
            guard let first = dinners.first else { continue }
            let key = TodoTask.dayKey(for: date)
            var photo: String?
            if let data = first.recipe?.imageData, let thumb = thumbnail(data) {
                let name = "\(photoPrefix)\(key)-\(first.recipe?.id?.uuidString ?? "x")-\(thumb.count).jpg"
                photos[name] = thumb
                photo = name
            }
            nights.append(Night(
                day: key,
                title: (first.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                recipeID: first.recipe?.id?.uuidString,
                photo: photo,
                more: dinners.count - 1
            ))
        }
        guard nights != lastWritten else { return }
        guard let folder = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID) else { return }
        for (name, data) in photos {
            let url = folder.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? data.write(to: url, options: .atomic)
            }
        }
        let keep = Set(photos.keys)
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for file in files where file.hasPrefix(photoPrefix) && !keep.contains(file) {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
            }
        }
        guard let data = try? JSONEncoder().encode(nights) else { return }
        do {
            try data.write(to: folder.appendingPathComponent(fileName), options: .atomic)
            lastWritten = nights
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        } catch {}
    }

    private static func thumbnail(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 360
        let scale = max(side / max(image.size.width, 1), side / max(image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        return rendered.jpegData(compressionQuality: 0.8)
    }
}

/// A widget tap that should open one recipe. Held until Home is on screen.
enum RecipeOpenRoute {
    static var pendingRecipeID: UUID?
    static let didArrive = Notification.Name("OurWeek.openRecipe")
}

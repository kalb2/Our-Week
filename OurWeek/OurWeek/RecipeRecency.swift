import Foundation

/// When a recipe was last made, from Cook mode Done and planned dinners whose day has passed.
enum RecipeRecency {
    /// Made within this many days counts as recent, so picks lean toward other recipes.
    static let recentDays = 14

    static func daysSinceMade(_ recipe: Recipe, now: Date = Date()) -> Int? {
        guard let last = recipe.lastCookedDate else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    static func isRecent(_ recipe: Recipe) -> Bool {
        guard let days = daysSinceMade(recipe) else { return false }
        return days < recentDays
    }

    /// "Made 2 weeks ago · 3×", "Made 3×" or "Never made".
    static func madeLine(times: Int, last: Date?, now: Date = Date()) -> String {
        guard times > 0 || last != nil else { return "Never made" }
        var parts: [String] = []
        if let last {
            let calendar = Calendar.current
            let days = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: last), to: calendar.startOfDay(for: now)).day ?? 0)
            parts.append("Made \(ago(days: days))")
        } else {
            parts.append("Made")
        }
        if times > 0 {
            if parts == ["Made"] { return "Made \(times)×" }
            parts.append("\(times)×")
        }
        return parts.joined(separator: " · ")
    }

    static func ago(days: Int) -> String {
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days ago"
        case 7..<14: return "last week"
        case 14..<60: return "\(days / 7) weeks ago"
        case 60..<365: return "\(days / 30) months ago"
        default:
            let years = days / 365
            return years == 1 ? "a year ago" : "\(years) years ago"
        }
    }

    /// Tie-breaker: recipes not made in the last two weeks first, then favorites (when asked),
    /// then the one made longest ago (never made counts as longest). Nil when still tied.
    static func fresherFirst(_ lhs: Recipe, _ rhs: Recipe, favorites: Bool) -> Bool? {
        let lRecent = isRecent(lhs), rRecent = isRecent(rhs)
        if lRecent != rRecent { return !lRecent }
        if favorites, lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }
        let lDays = daysSinceMade(lhs) ?? Int.max
        let rDays = daysSinceMade(rhs) ?? Int.max
        if lDays != rDays { return lDays > rDays }
        return nil
    }
}

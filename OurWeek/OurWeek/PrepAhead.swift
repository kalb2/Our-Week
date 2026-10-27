import Foundation
import SwiftUI
import UserNotifications

/// Reads a recipe's own steps and ingredients for anything that has to start the evening before.
/// Nothing is guessed: no keyword, no heads-up.
enum PrepAheadDetector {
    struct Cue: Equatable {
        let keyword: String
        /// Short instruction for tonight, e.g. "marinate tonight".
        let action: String
    }

    private static let proteins = [
        "chicken", "beef", "pork", "steak", "turkey", "shrimp", "prawn", "fish", "salmon", "cod",
        "tilapia", "sausage", "lamb", "roast", "ribs", "brisket", "meat", "thigh", "breast", "wings"
    ]

    /// Ordered by how much tonight matters. The first match wins.
    static func cue(steps: [String], ingredients: [String]) -> Cue? {
        let stepText = steps.joined(separator: "\n").lowercased()
        let ingredientText = ingredients.joined(separator: "\n").lowercased()
        let all = stepText + "\n" + ingredientText

        if has(all, #"\b(thaw|thawed|thawing|defrost|defrosted|defrosting)\b"#) {
            return Cue(keyword: "thaw", action: "move it to the fridge to thaw tonight")
        }
        if has(stepText, #"\bfrozen\b"#) || frozenProtein(ingredientText) {
            return Cue(keyword: "frozen", action: "move it to the fridge to thaw tonight")
        }
        if has(all, #"\b(marinate|marinated|marinating|marinade)\b"#) {
            return Cue(keyword: "marinate", action: "marinate tonight")
        }
        if has(all, #"\b(brine|brined|brining)\b"#) {
            return Cue(keyword: "brine", action: "brine tonight")
        }
        if has(all, #"\b(soak|soaked|soaking)\b(?!\s+up)"#) {
            return Cue(keyword: "soak", action: "start the soak tonight")
        }
        if let hours = longChillHours(stepText) {
            return Cue(keyword: "refrigerate for \(hours) hours", action: "it needs \(hours) hours in the fridge, so start tonight")
        }
        if has(all, #"\b(overnight|night before|day before|day ahead)\b"#) {
            return Cue(keyword: "overnight", action: "start the overnight step tonight")
        }
        if has(stepText, #"\bdough\b"#), has(stepText, #"\b(rise|rises|risen|proof|proofed|proofing|doubled)\b"#) {
            return Cue(keyword: "rise/proof dough", action: "plan time for the dough to rise")
        }
        if has(all, #"\b(slow[ -]?cooker|crock[ -]?pot)\b"#) {
            return Cue(keyword: "slow cooker", action: "prep tonight so the slow cooker can start early")
        }
        return nil
    }

    static func cue(for recipe: Recipe, dataManager: DataManager) -> Cue? {
        var steps = dataManager.sortedInstructions(for: recipe).compactMap(\.text)
        if steps.isEmpty, let legacy = recipe.instructions { steps = [legacy] }
        var ingredients = dataManager.sortedIngredients(for: recipe).map { [$0.name ?? "", $0.notes ?? ""].joined(separator: " ") }
        if ingredients.isEmpty, let legacy = recipe.ingredients { ingredients = [legacy] }
        return cue(steps: steps, ingredients: ingredients)
    }

    private static func frozenProtein(_ ingredients: String) -> Bool {
        ingredients.split(separator: "\n").contains { line in
            let line = String(line)
            return has(line, #"\bfrozen\b"#) && proteins.contains { has(line, "\\b\($0)") }
        }
    }

    /// "Refrigerate for 8 hours", "chill at least 6 hrs". Four hours or more counts.
    private static func longChillHours(_ text: String) -> Int? {
        let pattern = #"\b(refrigerate|refrigerated|chill|chilled|rest|marinate)\b[^.\n]{0,20}?\b(\d{1,2})\s*(\+\s*)?(hours|hour|hrs|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            if let r = Range(match.range(at: 2), in: text), let hours = Int(text[r]), hours >= 4 {
                return hours
            }
        }
        return nil
    }

    private static func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}

/// Evening-before heads-up for tomorrow's dinner. Settings live in UserDefaults only.
@MainActor
enum PrepAheadScheduler {
    static let prefix = "ourweek.prep."
    static let enabledKey = "prepAheadEnabled"
    static let minutesKey = "prepAheadMinutes"
    static let askedKey = "prepAheadAsked"
    static let defaultMinutes = 19 * 60
    private static var generation = 0
    private static let launchedAt = Date()

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var minutes: Int {
        UserDefaults.standard.object(forKey: minutesKey) as? Int ?? defaultMinutes
    }

    struct Heads: Equatable {
        let fireDate: Date
        let body: String
    }

    /// One heads-up per evening for the next week of planned dinners that link a recipe.
    static func plan(dataManager: DataManager, now: Date = Date()) -> [Heads] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var result: [Heads] = []
        for offset in 1...7 {
            guard let dinnerDay = calendar.date(byAdding: .day, value: offset, to: today),
                  let evening = calendar.date(byAdding: .day, value: -1, to: dinnerDay),
                  let fire = calendar.date(byAdding: .minute, value: minutes, to: evening),
                  fire > now.addingTimeInterval(60) else { continue }
            let lines = DayDinnerStore.dinners(on: dinnerDay, dataManager: dataManager).compactMap { meal -> String? in
                guard let recipe = meal.recipe,
                      let cue = PrepAheadDetector.cue(for: recipe, dataManager: dataManager) else { return nil }
                let name = (meal.title?.isEmpty == false ? meal.title : recipe.name) ?? "Dinner"
                return "\(name) — \(cue.action)."
            }
            guard !lines.isEmpty else { continue }
            result.append(Heads(fireDate: fire, body: "Tomorrow: " + lines.joined(separator: " · ")))
        }
        return result
    }

    /// Clears and re-adds the heads-ups. Cheap; called when the plan changes or the app opens.
    static func reschedule(dataManager: DataManager, mayAsk: Bool = false) {
        generation += 1
        let token = generation
        let upcoming = isEnabled ? plan(dataManager: dataManager) : []
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await center.pendingNotificationRequests()
            guard token == generation else { return }
            center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) })
            guard !upcoming.isEmpty else { return }
            var status = await center.notificationSettings().authorizationStatus
            // In context: the first time a planned dinner actually needs prep, after the app has settled.
            if status == .notDetermined, mayAsk, !UserDefaults.standard.bool(forKey: askedKey),
               Date().timeIntervalSince(launchedAt) > 8 {
                UserDefaults.standard.set(true, forKey: askedKey)
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
                status = await center.notificationSettings().authorizationStatus
            }
            guard token == generation, [.authorized, .provisional, .ephemeral].contains(status) else { return }
            let calendar = Calendar.current
            for heads in upcoming {
                let content = UNMutableNotificationContent()
                content.title = "Prep ahead"
                content.body = heads.body
                content.sound = .default
                let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: heads.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                let id = "\(prefix)\(Int(heads.fireDate.timeIntervalSince1970))"
                try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            }
        }
    }
}

/// The one settings row: a toggle, and the time once it is on.
struct PrepAheadSettingsRow: View {
    @Environment(DataManager.self) private var dataManager
    @AppStorage(PrepAheadScheduler.enabledKey) private var enabled = true
    @AppStorage(PrepAheadScheduler.minutesKey) private var minutes = PrepAheadScheduler.defaultMinutes
    @State private var blocked = false

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(byAdding: .minute, value: minutes, to: Calendar.current.startOfDay(for: Date())) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 19) * 60 + (parts.minute ?? 0)
                PrepAheadScheduler.reschedule(dataManager: dataManager)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(get: { enabled }, set: { turnOn($0) })) {
                HStack(spacing: 12) {
                    Image(systemName: "bell")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prep-ahead heads-up")
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                        Text("The evening before a dinner that needs thawing, marinating, or soaking.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(Color.terra500)
            if enabled {
                DatePicker("Remind me at", selection: time, displayedComponents: .hourAndMinute)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .tint(Color.terra500)
            }
            if blocked {
                Text("Notifications are off for Our Week. Turn them on in iOS Settings.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color.terra600)
            }
        }
        .padding(20)
        .homeQuietCard()
    }

    private func turnOn(_ on: Bool) {
        enabled = on
        blocked = false
        guard on else {
            PrepAheadScheduler.reschedule(dataManager: dataManager)
            return
        }
        Task { @MainActor in
            let allowed = await GoalReminderScheduler.requestAccess()
            UserDefaults.standard.set(true, forKey: PrepAheadScheduler.askedKey)
            blocked = !allowed
            PrepAheadScheduler.reschedule(dataManager: dataManager)
        }
    }
}

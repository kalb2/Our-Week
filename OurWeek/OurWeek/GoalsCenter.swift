import Foundation
import SwiftUI

/// Custom goals. Logs live in a file, not UserDefaults, so a tap cannot republish the widget.
@MainActor
@Observable
final class GoalsCenter {
    static let shared = GoalsCenter()

    private(set) var goals: [Goal] = []
    private(set) var settings = GoalSettings()
    private(set) var undoAction: GoalUndo?

    private var appliedBumps: [String] = []

    private init() {
        let stored = Self.readFile()
        goals = stored.goals
        settings = stored.settings
        appliedBumps = stored.appliedBumps
    }

    var activeGoals: [Goal] {
        goals.filter { !$0.archived }.sorted { $0.sort < $1.sort }
    }

    var todayGoals: [Goal] {
        let now = Date()
        return activeGoals.filter { isScheduled($0, on: now) }
    }

    var homeGoals: [Goal] {
        todayGoals.filter(\.showOnHome)
    }

    var archivedGoals: [Goal] {
        goals.filter(\.archived).sorted { $0.sort < $1.sort }
    }

    func progress(_ goal: Goal, on date: Date = Date()) -> Double {
        progress(goal, logicalDay: logicalDay(containing: date))
    }

    func isMet(_ goal: Goal, on date: Date = Date()) -> Bool {
        isMet(goal, logicalDay: logicalDay(containing: date))
    }

    func streak(for goal: Goal, now: Date = Date()) -> Int {
        let calendar = goalCalendar
        if goal.period == .week {
            var week = startOfWeek(containingLogical: logicalDay(containing: now))
            if !isMet(goal, logicalDay: week) {
                guard let previous = calendar.date(byAdding: .day, value: -7, to: week) else { return 0 }
                week = previous
            }
            var count = 0
            for _ in 0..<104 {
                guard isMet(goal, logicalDay: week) else { break }
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -7, to: week) else { break }
                week = previous
            }
            return count
        }

        var day = logicalDay(containing: now)
        if isScheduled(goal, logicalDay: day), !isMet(goal, logicalDay: day) {
            guard let previous = previousLogicalDay(day) else { return 0 }
            day = previous
        }
        var count = 0
        for _ in 0..<400 {
            if !isScheduled(goal, logicalDay: day) {
                guard let previous = previousLogicalDay(day) else { break }
                day = previous
                continue
            }
            guard isMet(goal, logicalDay: day) else { break }
            count += 1
            guard let previous = previousLogicalDay(day) else { break }
            day = previous
        }
        return count
    }

    func history(_ goal: Goal, days: Int = 30, now: Date = Date()) -> [GoalDayMark] {
        let calendar = goalCalendar
        let today = logicalDay(containing: now)
        return (0..<days).reversed().compactMap { offset -> GoalDayMark? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let key = key(forLogicalDay: date)
            let value = goal.logs[key] ?? 0
            let scheduled = isScheduled(goal, logicalDay: date)
            let met: Bool
            if goal.period == .week {
                met = scheduled && value > 0
            } else {
                met = scheduled && goal.target > 0 && value >= goal.target
            }
            return GoalDayMark(key: key, value: value, scheduled: scheduled, met: met, isToday: offset == 0)
        }
    }

    func bump(_ id: UUID) {
        mutate(id, undoable: true) { goal in
            let key = self.dayKey(for: Date())
            let old = goal.logs[key] ?? 0
            if goal.kind == .check {
                if goal.period == .week {
                    goal.logs[key] = old >= 1 ? 0 : 1
                } else {
                    goal.logs[key] = old >= goal.target ? 0 : max(goal.target, 1)
                }
            } else {
                goal.logs[key] = old + goal.step
            }
        }
    }

    func add(_ id: UUID, delta: Double) {
        guard delta != 0 else { return }
        mutate(id, undoable: true) { goal in
            let key = self.dayKey(for: Date())
            let next = max(0, (goal.logs[key] ?? 0) + delta)
            if next == 0 {
                goal.logs.removeValue(forKey: key)
            } else {
                goal.logs[key] = next
            }
        }
    }

    func undoLast() {
        guard let undoAction else { return }
        guard let index = goals.firstIndex(where: { $0.id == undoAction.goalID }) else {
            self.undoAction = nil
            return
        }
        if undoAction.previous == 0 {
            goals[index].logs.removeValue(forKey: undoAction.key)
        } else {
            goals[index].logs[undoAction.key] = undoAction.previous
        }
        self.undoAction = nil
        persist(notify: true)
    }

    func save(_ goal: Goal) {
        var next = goal
        let trimmed = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, next.target > 0 else { return }
        next.name = trimmed
        if next.step <= 0 { next.step = 1 }
        if let index = goals.firstIndex(where: { $0.id == next.id }) {
            next.logs = goals[index].logs
            next.sort = goals[index].sort
            goals[index] = next
        } else {
            next.sort = (goals.map(\.sort).max() ?? 0) + 1
            goals.append(next)
        }
        enforceWidgetCap(keeping: next.id)
        undoAction = nil
        persist(notify: true)
    }

    func archive(_ id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].archived = true
        goals[index].showOnWidget = false
        undoAction = nil
        persist(notify: true)
    }

    func restore(_ id: UUID) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].archived = false
        persist(notify: true)
    }

    func delete(_ id: UUID) {
        goals.removeAll { $0.id == id }
        undoAction = nil
        persist(notify: true)
    }

    func updateSettings(_ settings: GoalSettings) {
        self.settings = settings
        if !settings.showOnWidget {
            // Per-goal widget picks stay, but the master switch is what the widget reads.
        }
        persist(notify: true)
    }

    func setShowOnHome(_ id: UUID, on: Bool) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].showOnHome = on
        persist(notify: true)
    }

    func setShowOnWidget(_ id: UUID, on: Bool) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[index].showOnWidget = on
        if on { enforceWidgetCap(keeping: id) }
        persist(notify: true)
    }

    func isScheduled(_ goal: Goal, on date: Date) -> Bool {
        isScheduled(goal, logicalDay: logicalDay(containing: date))
    }

    func lines(for date: Date) -> [HomeWidgetStore.GoalLine] {
        lines(onLogicalDay: logicalDay(containing: date))
    }

    /// Goals for the logical day that begins on this calendar morning, after the reset time.
    func lines(forCalendarDay date: Date) -> [HomeWidgetStore.GoalLine] {
        let start = Calendar.current.startOfDay(for: date)
        let anchor = start.addingTimeInterval(TimeInterval(settings.resetMinutes * 60 + 60))
        return lines(for: anchor)
    }

    /// Applies widget taps once. Safe to call on launch and whenever a bump file appears.
    func applyWidgetBumps() {
        guard let url = Self.bumpsURL,
              let data = try? Data(contentsOf: url),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        var changed = false
        for item in items {
            guard let bump = item["bump"] as? String, !bump.isEmpty else { continue }
            guard !appliedBumps.contains(bump) else { continue }
            guard let idText = item["goal"] as? String, let id = UUID(uuidString: idText) else { continue }
            guard let index = goals.firstIndex(where: { $0.id == id }) else { continue }
            let day = (item["day"] as? String) ?? dayKey(for: Date())
            let op = (item["op"] as? String) ?? "increment"
            let old = goals[index].logs[day] ?? 0
            if op == "toggle" {
                if goals[index].kind == .check && goals[index].period == .week {
                    goals[index].logs[day] = old >= 1 ? 0 : 1
                } else if goals[index].kind == .check {
                    goals[index].logs[day] = old >= goals[index].target ? 0 : max(goals[index].target, 1)
                } else {
                    goals[index].logs[day] = old + goals[index].step
                }
            } else {
                goals[index].logs[day] = old + goals[index].step
            }
            if goals[index].logs[day] == 0 {
                goals[index].logs.removeValue(forKey: day)
            }
            appliedBumps.append(bump)
            changed = true
        }
        appliedBumps = Array(appliedBumps.suffix(40))
        if changed {
            persist(notify: false)
        }
        try? FileManager.default.removeItem(at: url)
    }

    func dayKey(for date: Date) -> String {
        key(forLogicalDay: logicalDay(containing: date))
    }

    // MARK: - Private

    private var goalCalendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = settings.weekStartsOn
        return calendar
    }

    /// A real timestamp belongs to the calendar day of (timestamp − reset).
    /// Callers that already hold a logical day must not pass it back through here.
    private func logicalDay(containing date: Date) -> Date {
        let shifted = date.addingTimeInterval(TimeInterval(-settings.resetMinutes * 60))
        return goalCalendar.startOfDay(for: shifted)
    }

    private func key(forLogicalDay day: Date) -> String {
        Self.formatter.string(from: goalCalendar.startOfDay(for: day))
    }

    private func previousLogicalDay(_ day: Date) -> Date? {
        goalCalendar.date(byAdding: .day, value: -1, to: goalCalendar.startOfDay(for: day))
    }

    private func isScheduled(_ goal: Goal, logicalDay day: Date) -> Bool {
        let weekday = goalCalendar.component(.weekday, from: goalCalendar.startOfDay(for: day))
        return goal.weekdays.contains(weekday)
    }

    private func progress(_ goal: Goal, logicalDay day: Date) -> Double {
        if goal.period == .week {
            return weekDayKeys(containingLogical: day).reduce(0) { sum, key in
                sum + (goal.logs[key] ?? 0)
            }
        }
        return goal.logs[key(forLogicalDay: day)] ?? 0
    }

    private func isMet(_ goal: Goal, logicalDay day: Date) -> Bool {
        goal.target > 0 && progress(goal, logicalDay: day) >= goal.target
    }

    private func startOfWeek(containingLogical day: Date) -> Date {
        let calendar = goalCalendar
        let start = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: start)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: start) ?? start
    }

    private func weekDayKeys(containingLogical day: Date) -> [String] {
        let calendar = goalCalendar
        let start = startOfWeek(containingLogical: day)
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { key(forLogicalDay: $0) }
        }
    }

    private func lines(onLogicalDay day: Date) -> [HomeWidgetStore.GoalLine] {
        guard settings.showOnWidget else { return [] }
        return goals
            .filter { $0.showOnWidget && !$0.archived && isScheduled($0, logicalDay: day) }
            .sorted { $0.sort < $1.sort }
            .prefix(3)
            .map { line(for: $0, logicalDay: day) }
    }

    private func line(for goal: Goal, logicalDay day: Date) -> HomeWidgetStore.GoalLine {
        let key = key(forLogicalDay: day)
        let color = GoalPalette.rgb(goal.color)
        return HomeWidgetStore.GoalLine(
            id: goal.id.uuidString,
            name: goal.name,
            kind: goal.kind.rawValue,
            period: goal.period.rawValue,
            current: progress(goal, logicalDay: day),
            solo: goal.logs[key] ?? 0,
            target: goal.target,
            step: goal.step,
            day: key,
            red: color.0,
            green: color.1,
            blue: color.2
        )
    }

    private func mutate(_ id: UUID, undoable: Bool, change: (inout Goal) -> Void) {
        guard let index = goals.firstIndex(where: { $0.id == id }) else { return }
        let key = dayKey(for: Date())
        let previous = goals[index].logs[key] ?? 0
        change(&goals[index])
        if undoable {
            undoAction = GoalUndo(goalID: id, key: key, previous: previous)
        }
        persist(notify: true)
    }

    private func enforceWidgetCap(keeping id: UUID) {
        let shown = goals.filter { $0.showOnWidget && !$0.archived }
        guard shown.count > 3 else { return }
        let overflow = shown.filter { $0.id != id }.sorted { $0.sort < $1.sort }
        let remove = overflow.prefix(shown.count - 3)
        for goal in remove {
            if let index = goals.firstIndex(where: { $0.id == goal.id }) {
                goals[index].showOnWidget = false
            }
        }
    }

    private func persist(notify: Bool) {
        let cutoff = goalCalendar.date(byAdding: .day, value: -120, to: logicalDay(containing: Date())).map { Self.formatter.string(from: $0) }
        if let cutoff {
            for index in goals.indices {
                goals[index].logs = goals[index].logs.filter { $0.key >= cutoff }
            }
        }
        let file = GoalsFile(goals: goals, settings: settings, appliedBumps: appliedBumps)
        if let data = try? JSONEncoder().encode(file) {
            let url = Self.fileURL
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        if notify {
            HomeWidgetStore.noteGoalsChanged()
        }
        GoalReminderScheduler.reschedule(goals: goals)
    }

    func refreshReminders() {
        GoalReminderScheduler.reschedule(goals: goals)
    }

    private static func readFile() -> GoalsFile {
        guard let data = try? Data(contentsOf: fileURL),
              let file = try? JSONDecoder().decode(GoalsFile.self, from: data) else {
            return GoalsFile(goals: [], settings: GoalSettings(), appliedBumps: [])
        }
        return file
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("OurWeek", isDirectory: true).appendingPathComponent("goals.json")
    }

    static var bumpsURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ShareImportStore.appGroupID)?
            .appendingPathComponent("home-goal-bumps.json")
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

struct Goal: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var kind: GoalKind
    var unit: GoalUnit
    var customUnit: String
    var period: GoalPeriod
    var target: Double
    var step: Double
    var color: String
    var icon: String
    var weekdays: [Int]
    var showOnHome: Bool
    var showOnWidget: Bool
    var archived: Bool
    var sort: Int
    var logs: [String: Double]
    var reminder: GoalReminder

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, unit, customUnit, period, target, step, color, icon
        case weekdays, showOnHome, showOnWidget, archived, sort, logs, reminder
    }

    static func draft() -> Goal {
        Goal(
            id: UUID(),
            name: "",
            kind: .count,
            unit: .glasses,
            customUnit: "",
            period: .day,
            target: 8,
            step: 1,
            color: "terra",
            icon: "",
            weekdays: Array(1...7),
            showOnHome: true,
            showOnWidget: false,
            archived: false,
            sort: 0,
            logs: [:],
            reminder: GoalReminder()
        )
    }

    init(
        id: UUID,
        name: String,
        kind: GoalKind,
        unit: GoalUnit,
        customUnit: String,
        period: GoalPeriod,
        target: Double,
        step: Double,
        color: String,
        icon: String,
        weekdays: [Int],
        showOnHome: Bool,
        showOnWidget: Bool,
        archived: Bool,
        sort: Int,
        logs: [String: Double],
        reminder: GoalReminder = GoalReminder()
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.unit = unit
        self.customUnit = customUnit
        self.period = period
        self.target = target
        self.step = step
        self.color = color
        self.icon = icon
        self.weekdays = weekdays
        self.showOnHome = showOnHome
        self.showOnWidget = showOnWidget
        self.archived = archived
        self.sort = sort
        self.logs = logs
        self.reminder = reminder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decode(GoalKind.self, forKey: .kind)
        unit = try container.decode(GoalUnit.self, forKey: .unit)
        customUnit = try container.decodeIfPresent(String.self, forKey: .customUnit) ?? ""
        period = try container.decode(GoalPeriod.self, forKey: .period)
        target = try container.decode(Double.self, forKey: .target)
        step = try container.decodeIfPresent(Double.self, forKey: .step) ?? 1
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "terra"
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        weekdays = try container.decodeIfPresent([Int].self, forKey: .weekdays) ?? Array(1...7)
        showOnHome = try container.decodeIfPresent(Bool.self, forKey: .showOnHome) ?? true
        showOnWidget = try container.decodeIfPresent(Bool.self, forKey: .showOnWidget) ?? false
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        sort = try container.decodeIfPresent(Int.self, forKey: .sort) ?? 0
        logs = try container.decodeIfPresent([String: Double].self, forKey: .logs) ?? [:]
        reminder = try container.decodeIfPresent(GoalReminder.self, forKey: .reminder) ?? GoalReminder()
    }

    var unitLabel: String {
        switch unit {
        case .glasses: return "glasses"
        case .steps: return "steps"
        case .minutes: return "min"
        case .custom:
            let trimmed = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "" : trimmed
        }
    }
}

enum GoalReminderMode: String, Codable, CaseIterable {
    case everyHour
    case everyTwoHours
    case custom
    case spread
}

struct GoalReminder: Codable, Equatable {
    var enabled: Bool
    var mode: GoalReminderMode
    var customHours: Int
    var spreadCount: Int
    var wakeStartMinutes: Int
    var wakeEndMinutes: Int

    private enum CodingKeys: String, CodingKey {
        case enabled, mode, customHours, spreadCount, wakeStartMinutes, wakeEndMinutes
    }

    init(
        enabled: Bool = false,
        mode: GoalReminderMode = .everyHour,
        customHours: Int = 3,
        spreadCount: Int = 4,
        wakeStartMinutes: Int = 8 * 60,
        wakeEndMinutes: Int = 21 * 60
    ) {
        self.enabled = enabled
        self.mode = mode
        self.customHours = customHours
        self.spreadCount = spreadCount
        self.wakeStartMinutes = wakeStartMinutes
        self.wakeEndMinutes = wakeEndMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        mode = try container.decodeIfPresent(GoalReminderMode.self, forKey: .mode) ?? .everyHour
        customHours = try container.decodeIfPresent(Int.self, forKey: .customHours) ?? 3
        spreadCount = try container.decodeIfPresent(Int.self, forKey: .spreadCount) ?? 4
        wakeStartMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeStartMinutes) ?? 8 * 60
        wakeEndMinutes = try container.decodeIfPresent(Int.self, forKey: .wakeEndMinutes) ?? 21 * 60
    }

    /// Clock minutes inside the wake window. Empty when the window is backwards.
    var slots: [Int] {
        let start = min(max(wakeStartMinutes, 0), 24 * 60 - 1)
        let end = min(max(wakeEndMinutes, 0), 24 * 60)
        guard end > start else { return [] }
        switch mode {
        case .everyHour:
            return Self.stride(from: start, through: end, by: 60)
        case .everyTwoHours:
            return Self.stride(from: start, through: end, by: 120)
        case .custom:
            let step = min(max(customHours, 1), 12) * 60
            return Self.stride(from: start, through: end, by: step)
        case .spread:
            let count = min(max(spreadCount, 2), 12)
            guard count > 1 else { return [(start + end) / 2] }
            return (0..<count).map { start + (end - start) * $0 / (count - 1) }
        }
    }

    var summary: String {
        guard enabled else { return "Off" }
        let window = "\(Self.clock.string(from: Self.date(wakeStartMinutes)))–\(Self.clock.string(from: Self.date(wakeEndMinutes)))"
        switch mode {
        case .everyHour:
            return "Every hour · \(window)"
        case .everyTwoHours:
            return "Every 2 hours · \(window)"
        case .custom:
            let hours = min(max(customHours, 1), 12)
            return hours == 1 ? "Every hour · \(window)" : "Every \(hours) hours · \(window)"
        case .spread:
            let count = min(max(spreadCount, 2), 12)
            return "\(count) times · \(window)"
        }
    }

    private static func stride(from start: Int, through end: Int, by step: Int) -> [Int] {
        guard step > 0 else { return [] }
        var minute = start
        var slots: [Int] = []
        while minute <= end && slots.count < 24 {
            slots.append(minute)
            minute += step
        }
        return slots
    }

    static func date(_ minutes: Int) -> Date {
        let hour = min(max(minutes, 0), 24 * 60) / 60
        let minute = min(max(minutes, 0), 24 * 60) % 60
        return Calendar.current.date(bySettingHour: hour % 24, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

enum GoalKind: String, Codable, CaseIterable {
    case count
    case check
    case ring
    case time

    var title: String {
        switch self {
        case .count: return "Count"
        case .check: return "Check"
        case .ring: return "Ring"
        case .time: return "Time"
        }
    }
}

enum GoalUnit: String, Codable, CaseIterable {
    case glasses
    case steps
    case minutes
    case custom

    var title: String {
        switch self {
        case .glasses: return "Glasses"
        case .steps: return "Steps"
        case .minutes: return "Minutes"
        case .custom: return "Custom"
        }
    }
}

enum GoalPeriod: String, Codable, CaseIterable {
    case day
    case week

    var title: String {
        switch self {
        case .day: return "Daily"
        case .week: return "Weekly"
        }
    }
}

struct GoalSettings: Codable, Equatable {
    var showOnWidget: Bool = false
    var weekStartsOn: Int = 2
    var resetMinutes: Int = 0

    private enum CodingKeys: String, CodingKey {
        case showOnWidget, weekStartsOn, resetMinutes
    }

    init(showOnWidget: Bool = false, weekStartsOn: Int = 2, resetMinutes: Int = 0) {
        self.showOnWidget = showOnWidget
        self.weekStartsOn = weekStartsOn
        self.resetMinutes = resetMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showOnWidget = try container.decodeIfPresent(Bool.self, forKey: .showOnWidget) ?? false
        weekStartsOn = try container.decodeIfPresent(Int.self, forKey: .weekStartsOn) ?? 2
        resetMinutes = try container.decodeIfPresent(Int.self, forKey: .resetMinutes) ?? 0
    }
}

struct GoalUndo: Equatable {
    var goalID: UUID
    var key: String
    var previous: Double
}

struct GoalDayMark: Identifiable {
    var key: String
    var value: Double
    var scheduled: Bool
    var met: Bool
    var isToday: Bool
    var id: String { key }
}

struct GoalsFile: Codable {
    var goals: [Goal]
    var settings: GoalSettings
    var appliedBumps: [String]
}

enum GoalPalette {
    static let names = ["terra", "clay", "sage", "sky", "lilac", "ink"]

    static func rgb(_ name: String) -> (Double, Double, Double) {
        switch name {
        case "clay": return (0.72, 0.45, 0.38)
        case "sage": return (0.45, 0.52, 0.42)
        case "sky": return (0.45, 0.58, 0.66)
        case "lilac": return (0.58, 0.48, 0.64)
        case "ink": return (0.28, 0.25, 0.23)
        default: return (0.878, 0.478, 0.373)
        }
    }

    static func color(_ name: String) -> Color {
        let parts = rgb(name)
        return Color(red: parts.0, green: parts.1, blue: parts.2)
    }
}

enum GoalIcons {
    static let symbols = [
        "",
        "drop.fill",
        "figure.walk",
        "moon.fill",
        "book.fill",
        "heart.fill",
        "flame.fill",
        "leaf.fill",
        "dumbbell.fill",
        "cup.and.saucer.fill"
    ]
}

enum GoalNumber {
    static func text(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

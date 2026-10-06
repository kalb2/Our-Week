import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let ourWeekOpenGoals = Notification.Name("OurWeek.openGoals")
}

/// Set when a goal reminder opens the app, including before the first view appears.
enum GoalReminderRoute {
    static var openGoals = false
}

/// Local nudges for goals. Permission is requested only when reminders are turned on.
@MainActor
enum GoalReminderScheduler {
    static let prefix = "ourweek.goal."
    private static var generation = 0

    static func requestAccess() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    static func reschedule(goals: [Goal]) {
        generation += 1
        let token = generation
        let active = goals.filter { !$0.archived && $0.reminder.enabled }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard token == generation else { return }
            let pending = await center.pendingNotificationRequests()
            guard token == generation else { return }
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard isAllowed(settings.authorizationStatus) else { return }
            for request in requests(for: active) {
                try? await center.add(request)
            }
        }
    }

    private static func isAllowed(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private static func requests(for goals: [Goal]) -> [UNNotificationRequest] {
        let now = Date()
        let calendar = Calendar.current
        var pairs: [(Date, Goal)] = []
        for goal in goals {
            for offset in 0..<3 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else { continue }
                for minutes in goal.reminder.slots {
                    guard let date = calendar.date(byAdding: .minute, value: minutes, to: day) else { continue }
                    guard date > now.addingTimeInterval(45) else { continue }
                    guard GoalsCenter.shared.isScheduled(goal, on: date) else { continue }
                    guard !GoalsCenter.shared.isMet(goal, on: date) else { continue }
                    pairs.append((date, goal))
                }
            }
        }
        pairs.sort { $0.0 < $1.0 }
        return pairs.prefix(48).map { date, goal in
            let content = UNMutableNotificationContent()
            content.title = goal.name
            content.body = body(for: goal)
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let identifier = "\(prefix)\(goal.id.uuidString).\(Int(date.timeIntervalSince1970))"
            return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        }
    }

    private static func body(for goal: Goal) -> String {
        if goal.kind == .check {
            return goal.period == .week ? "A nudge for this week." : "A nudge for today."
        }
        let amount = GoalNumber.text(goal.target)
        let span = goal.period == .week ? "this week" : "today"
        if goal.unitLabel.isEmpty { return "\(amount) \(span)" }
        return "\(amount) \(goal.unitLabel) \(span)"
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier.hasPrefix(GoalReminderScheduler.prefix) {
            completionHandler([.banner, .sound])
        } else {
            completionHandler([.banner, .sound])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.notification.request.identifier.hasPrefix(GoalReminderScheduler.prefix) {
            GoalReminderRoute.openGoals = true
            NotificationCenter.default.post(name: .ourWeekOpenGoals, object: nil)
        }
        completionHandler()
    }
}

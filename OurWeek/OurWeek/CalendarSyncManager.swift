//
//  CalendarSyncManager.swift
//  OurWeek
//
//  Wraps EventKit to provide bi-directional Apple Calendar sync.
//

import EventKit
import SwiftUI

// MARK: - Lightweight model for Apple Calendar events

struct AppleCalendarEvent: Identifiable {
    let id: String                // EKEvent.eventIdentifier
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: UIColor
    let calendarTitle: String
}

// MARK: - Selectable calendar wrapper

struct SelectableCalendar: Identifiable {
    let id: String                // EKCalendar.calendarIdentifier
    let title: String
    let color: UIColor
    let accountName: String
}

// MARK: - CalendarSyncManager

@Observable
class CalendarSyncManager {
    private let eventStore = EKEventStore()

    // Authorization
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // Available calendars
    var availableCalendars: [SelectableCalendar] = []

    // User-selected source calendar IDs (persisted separately via AppStorage in the view)
    var selectedCalendarIDs: Set<String> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: "selectedAppleCalendarIDs") ?? []
            return Set(raw)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: "selectedAppleCalendarIDs")
        }
    }

    // Write-back target calendar ID
    var writeBackCalendarID: String? {
        get { UserDefaults.standard.string(forKey: "writeBackCalendarID") }
        set { UserDefaults.standard.set(newValue, forKey: "writeBackCalendarID") }
    }

    // Global sync toggle
    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "appleCalendarSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "appleCalendarSyncEnabled") }
    }

    init() {
        refreshAuthorizationStatus()
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
    }

    func requestAccess() async -> Bool {
        do {
            let granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            await MainActor.run {
                refreshAuthorizationStatus()
                if granted { loadCalendars() }
            }
            return granted
        } catch {
            print("EventKit access error: \(error)")
            return false
        }
    }

    // MARK: - Calendar Discovery

    func loadCalendars() {
        let ekCalendars = eventStore.calendars(for: .event)
        availableCalendars = ekCalendars.map { cal in
            SelectableCalendar(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: cal.cgColor.flatMap { UIColor(cgColor: $0) } ?? .systemPurple,
                accountName: cal.source?.title ?? "Unknown"
            )
        }
        .sorted { $0.accountName < $1.accountName }
    }

    // MARK: - Read: Fetch Apple Calendar Events

    func fetchEvents(from startDate: Date, to endDate: Date) -> [AppleCalendarEvent] {
        guard isSyncEnabled,
              authorizationStatus == .fullAccess else {
            return []
        }

        let selectedIDs = selectedCalendarIDs
        guard !selectedIDs.isEmpty else { return [] }

        let ekCalendars = eventStore.calendars(for: .event)
            .filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !ekCalendars.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: ekCalendars
        )

        let ekEvents = eventStore.events(matching: predicate)

        return ekEvents.map { ev in
            AppleCalendarEvent(
                id: ev.eventIdentifier,
                title: ev.title ?? "Untitled",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                calendarColor: ev.calendar.cgColor.flatMap { UIColor(cgColor: $0) } ?? .systemPurple,
                calendarTitle: ev.calendar.title
            )
        }
    }

    /// Fetch Apple Calendar events for a week starting at the given date
    func fetchWeekEvents(from monday: Date) -> [AppleCalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: monday)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
        return fetchEvents(from: start, to: end)
    }

    // MARK: - Write: Push OurWeek event to Apple Calendar

    /// Creates or updates an event in Apple Calendar. Returns the EKEvent identifier on success.
    @discardableResult
    func writeEvent(
        title: String,
        startDate: Date,
        endDate: Date?,
        isAllDay: Bool,
        notes: String?,
        existingEventID: String? = nil
    ) -> String? {
        guard let calendarID = writeBackCalendarID,
              let targetCalendar = eventStore.calendars(for: .event)
                .first(where: { $0.calendarIdentifier == calendarID }) else {
            print("No write-back calendar configured")
            return nil
        }

        let ekEvent: EKEvent
        if let existingID = existingEventID,
           let existing = eventStore.event(withIdentifier: existingID) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: eventStore)
        }

        ekEvent.title = title
        ekEvent.startDate = startDate
        ekEvent.endDate = endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: startDate)
        ekEvent.isAllDay = isAllDay
        ekEvent.notes = notes
        ekEvent.calendar = targetCalendar

        do {
            try eventStore.save(ekEvent, span: .thisEvent)
            return ekEvent.eventIdentifier
        } catch {
            print("Failed to save event to Apple Calendar: \(error)")
            return nil
        }
    }

    /// Write a meal plan as an event to Apple Calendar with a meal-style prefix
    @discardableResult
    func writeMeal(
        title: String,
        mealType: String,
        date: Date,
        notes: String?
    ) -> String? {
        let emoji: String
        switch mealType.lowercased() {
        case "breakfast": emoji = "🥞"
        case "lunch": emoji = "🥗"
        case "dinner": emoji = "🍝"
        case "snack": emoji = "🍎"
        default: emoji = "🍽️"
        }

        let displayTitle = "\(emoji) OurWeek: \(title)"
        return writeEvent(
            title: displayTitle,
            startDate: date,
            endDate: Calendar.current.date(byAdding: .hour, value: 1, to: date),
            isAllDay: false,
            notes: notes
        )
    }

    /// Remove an event from Apple Calendar by its identifier
    func removeEvent(identifier: String) {
        guard let event = eventStore.event(withIdentifier: identifier) else { return }
        do {
            try eventStore.remove(event, span: .thisEvent)
        } catch {
            print("Failed to remove event from Apple Calendar: \(error)")
        }
    }
}

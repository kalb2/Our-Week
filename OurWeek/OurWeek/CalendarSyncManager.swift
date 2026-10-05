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
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let calendarColor: UIColor
    let calendarTitle: String

    /// True when this event should appear on the given local calendar day.
    /// All-day EventKit dates are floating GMT days, so they are matched by
    /// year/month/day instead of the local instant of `startDate`.
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }

        if isAllDay {
            var gmt = Calendar(identifier: .gregorian)
            gmt.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            let startParts = gmt.dateComponents([.year, .month, .day], from: startDate)
            let endParts = gmt.dateComponents([.year, .month, .day], from: endDate)
            let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
            guard let startDay = gmt.date(from: startParts),
                  let endDay = gmt.date(from: endParts),
                  let localDay = gmt.date(from: dayParts) else { return false }
            return localDay >= startDay && localDay < endDay
        }

        return startDate < dayEnd && endDate > dayStart
    }
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
    /// Replaced after access is granted. A store created before full access
    /// keeps returning an empty calendar list, which made every fetch bail out.
    private var eventStore = EKEventStore()

    // Authorization
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // Available calendars
    var availableCalendars: [SelectableCalendar] = []

    static let selectedCalendarsKey = "selectedAppleCalendarIDs"

    /// Calendars the user checked in Calendar Sync.
    var selectedCalendarIDs: Set<String> = []

    /// Last week of Apple events loaded off the main thread. The widget reads this.
    /// It is never filled by a synchronous EventKit fetch.
    private(set) var widgetEvents: [AppleCalendarEvent] = []

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

    /// Full access, including a legacy `.authorized` grant that shares that raw value.
    var canReadEvents: Bool {
        switch authorizationStatus {
        case .denied, .restricted, .notDetermined, .writeOnly:
            return false
        case .fullAccess:
            return true
        @unknown default:
            return authorizationStatus.rawValue == EKAuthorizationStatus.fullAccess.rawValue
        }
    }

    /// Shown on the home week when calendar access exists but events cannot be read yet.
    var calendarSelectionCue: String? {
        guard canReadEvents else { return nil }
        if !isSyncEnabled { return "Turn on calendar sync" }
        if selectedCalendarIDs.isEmpty && availableCalendars.isEmpty { return "Turn on calendar sync" }
        if selectedCalendarIDs.isEmpty { return "Choose calendars" }
        return nil
    }

    private var syncPreferenceExists: Bool {
        UserDefaults.standard.object(forKey: "appleCalendarSyncEnabled") != nil
    }

    private var selectionPreferenceExists: Bool {
        UserDefaults.standard.object(forKey: Self.selectedCalendarsKey) != nil
    }

    init() {
        if let raw = UserDefaults.standard.stringArray(forKey: Self.selectedCalendarsKey) {
            selectedCalendarIDs = Set(raw)
        }
        refreshAuthorizationStatus()
    }

    /// Prime EventKit from the system grant and the saved calendar selection.
    /// Does not clear a selection that still matches a calendar, and does not
    /// turn sync back on when it was explicitly switched off.
    /// A permission prompt happens only when sync is already on and iOS still
    /// reports `.notDetermined`. An existing full-access grant is reused.
    func prepareForReading() async {
        refreshAuthorizationStatus()

        if syncPreferenceExists && !isSyncEnabled {
            return
        }

        switch authorizationStatus {
        case .denied, .restricted, .writeOnly:
            return
        case .notDetermined:
            guard isSyncEnabled else { return }
            _ = await requestAccess()
        case .fullAccess:
            // Returns immediately and does not prompt when access is already granted.
            _ = await requestAccess()
        @unknown default:
            guard authorizationStatus.rawValue == EKAuthorizationStatus.fullAccess.rawValue else { return }
            _ = await requestAccess()
        }

        refreshAuthorizationStatus()
        guard canReadEvents else { return }

        if !syncPreferenceExists {
            isSyncEnabled = true
        }
        guard isSyncEnabled else { return }
        recoverCalendarSelectionIfNeeded()
    }

    /// After a wipe there is no saved checklist, so start with every calendar
    /// checked. Once a choice exists — including an explicit empty one — never
    /// add calendars back. The user turns them on and off in Calendar Sync.
    private func recoverCalendarSelectionIfNeeded() {
        guard !selectionPreferenceExists else { return }
        let knownIDs = Set(eventStore.calendars(for: .event).map(\.calendarIdentifier))
        guard !knownIDs.isEmpty else { return }
        replaceSelectedCalendars(knownIDs)
    }

    /// Toggle one calendar in the checklist and save that choice.
    func toggleCalendar(id: String) {
        var ids = selectedCalendarIDs
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        replaceSelectedCalendars(ids)
    }

    private func replaceSelectedCalendars(_ ids: Set<String>) {
        selectedCalendarIDs = ids
        UserDefaults.standard.set(Array(ids), forKey: Self.selectedCalendarsKey)
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
        let granted = await askForAccess(on: eventStore)
        refreshAuthorizationStatus()
        guard granted || canReadEvents else { return false }

        eventStore.refreshSourcesIfNecessary()
        loadCalendars()

        // calendars(for:) stays empty on a store that was created before access.
        // reset() does not fix that. A new store, asked again, does not re-prompt.
        if availableCalendars.isEmpty {
            eventStore = EKEventStore()
            _ = await askForAccess(on: eventStore)
            refreshAuthorizationStatus()
            eventStore.refreshSourcesIfNecessary()
            loadCalendars()
        }
        return canReadEvents
    }

    private func askForAccess(on store: EKEventStore) async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                return try await store.requestFullAccessToEvents()
            } else {
                return try await store.requestAccess(to: .event)
            }
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
        refreshAuthorizationStatus()
        guard isSyncEnabled, canReadEvents, startDate < endDate else { return [] }

        let selectedIDs = selectedCalendarIDs
        let matched = eventStore.calendars(for: .event)
            .filter { selectedIDs.contains($0.calendarIdentifier) }
        guard !matched.isEmpty else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: matched
        )

        return eventStore.events(matching: predicate).map { ev in
            let stamp = String(ev.startDate.timeIntervalSince1970)
            let rawID = ev.eventIdentifier
            return AppleCalendarEvent(
                id: rawID.isEmpty ? stamp : "\(rawID)-\(stamp)",
                title: ev.title ?? "Untitled",
                startDate: ev.startDate,
                endDate: ev.endDate,
                isAllDay: ev.isAllDay,
                calendarColor: ev.calendar.cgColor.flatMap { UIColor(cgColor: $0) } ?? .systemPurple,
                calendarTitle: ev.calendar.title
            )
        }
    }

    /// Fetch Apple Calendar events for a week starting at the given date.
    /// The range is padded by a day so all-day events, which EventKit stores
    /// as GMT midnights, are still returned for the home week to place.
    func fetchWeekEvents(from monday: Date) -> [AppleCalendarEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: monday)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start),
              let paddedStart = calendar.date(byAdding: .day, value: -1, to: start),
              let paddedEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return [] }
        return fetchEvents(from: paddedStart, to: paddedEnd)
    }

    /// Week of Apple events for the widget and the home week. The EventKit query
    /// runs on a background store so the main thread is not blocked on CalendarDaemon.
    func loadWeekEvents(from monday: Date) async -> [AppleCalendarEvent] {
        refreshAuthorizationStatus()
        guard isSyncEnabled, canReadEvents else {
            widgetEvents = []
            return []
        }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: monday)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start),
              let paddedStart = calendar.date(byAdding: .day, value: -1, to: start),
              let paddedEnd = calendar.date(byAdding: .day, value: 1, to: end) else {
            return widgetEvents
        }
        let ids = selectedCalendarIDs
        let records: [EventKitBackgroundReader.Record] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let found = EventKitBackgroundReader.events(from: paddedStart, to: paddedEnd, calendarIDs: ids)
                continuation.resume(returning: found)
            }
        }
        let events = records.map { record in
            AppleCalendarEvent(
                id: record.id,
                title: record.title,
                startDate: record.startDate,
                endDate: record.endDate,
                isAllDay: record.isAllDay,
                calendarColor: UIColor(
                    red: record.red,
                    green: record.green,
                    blue: record.blue,
                    alpha: record.alpha
                ),
                calendarTitle: record.calendarTitle
            )
        }
        widgetEvents = events
        return events
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

/// Reads EventKit on a private store. Not the store the UI uses on the main thread.
nonisolated enum EventKitBackgroundReader {
    struct Record: Sendable {
        var id: String
        var title: String
        var startDate: Date
        var endDate: Date
        var isAllDay: Bool
        var red: Double
        var green: Double
        var blue: Double
        var alpha: Double
        var calendarTitle: String
    }

    static func events(from startDate: Date, to endDate: Date, calendarIDs: Set<String>) -> [Record] {
        guard startDate < endDate, !calendarIDs.isEmpty else { return [] }
        let store = EKEventStore()
        let matched = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard !matched.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: startDate, end: endDate, calendars: matched)
        return store.events(matching: predicate).map { event in
            let stamp = String(event.startDate.timeIntervalSince1970)
            let rawID = event.eventIdentifier
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            let color = event.calendar.cgColor.flatMap { UIColor(cgColor: $0) } ?? .systemPurple
            if !color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                red = 0.58
                green = 0.22
                blue = 0.92
                alpha = 1
            }
            return Record(
                id: rawID.isEmpty ? stamp : "\(rawID)-\(stamp)",
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                red: Double(red),
                green: Double(green),
                blue: Double(blue),
                alpha: Double(alpha),
                calendarTitle: event.calendar.title
            )
        }
    }
}

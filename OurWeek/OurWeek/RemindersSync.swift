import EventKit
import Foundation

/// Two-way sync between the Home to-do list and one Apple Reminders list.
/// Permission is requested only when the user turns the week setting on.
@MainActor
@Observable
final class RemindersSync {
    static let enabledKey = "appleRemindersSyncEnabled"
    static let listIDKey = "appleRemindersListID"

    struct ListChoice: Identifiable, Equatable {
        var id: String
        var title: String
    }

    var isEnabled: Bool
    var statusNote: String?
    var listTitle: String
    var lists: [ListChoice]

    private var store = EKEventStore()
    private static let pushedIDsKey = "appleRemindersPushedIDs"

    private var isPushing = false
    private var isApplyingRemote = false
    private var pushQueued = false
    private var lastPushedRaw = ""

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        listTitle = "Our Week"
        lists = []
    }

    /// Does not prompt. If sync was already turned on and access is still granted, refresh.
    func resumeIfEnabled() async {
        guard isEnabled else { return }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess else {
            if status == .denied || status == .restricted {
                turnOff(note: "Reminders access is off, so to-dos stay on this phone.")
            }
            return
        }
        guard await requestAccess() else { return }
        refreshLists()
        await push()
        await pull()
    }

    func setEnabled(_ on: Bool) async {
        if !on {
            turnOff(note: nil)
            return
        }
        isEnabled = true
        guard await requestAccess() else {
            turnOff(note: "Reminders access is off, so to-dos stay on this phone.")
            return
        }
        guard ensureList() != nil else {
            turnOff(note: "To-dos stay on this phone.")
            return
        }
        isEnabled = true
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        statusNote = nil
        refreshLists()
        await push()
        await pull()
    }

    func selectList(id: String) {
        UserDefaults.standard.set(id, forKey: Self.listIDKey)
        listTitle = lists.first(where: { $0.id == id })?.title ?? "Our Week"
        Task { await push() }
    }

    func noteLocalTodosChanged() {
        guard isEnabled, !isPushing, !isApplyingRemote, !pushQueued else { return }
        let raw = Self.currentRaw()
        guard raw != lastPushedRaw else { return }
        pushQueued = true
        Task {
            await self.push()
            self.pushQueued = false
        }
    }

    private func turnOff(note: String?) {
        isEnabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        statusNote = note
    }

    private func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if status == .denied || status == .restricted || status == .writeOnly {
            return false
        }
        do {
            let granted = try await store.requestFullAccessToReminders()
            if granted, store.calendars(for: .reminder).isEmpty {
                store = EKEventStore()
                _ = try await store.requestFullAccessToReminders()
            }
            return EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        } catch {
            return false
        }
    }

    @discardableResult
    private func ensureList() -> EKCalendar? {
        let calendars = store.calendars(for: .reminder)
        if let saved = UserDefaults.standard.string(forKey: Self.listIDKey),
           let match = calendars.first(where: { $0.calendarIdentifier == saved }) {
            listTitle = match.title
            return match
        }
        if let named = calendars.first(where: { $0.title.compare("Our Week", options: .caseInsensitive) == .orderedSame }) {
            UserDefaults.standard.set(named.calendarIdentifier, forKey: Self.listIDKey)
            listTitle = named.title
            return named
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = "Our Week"
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV })
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        guard let source else { return nil }
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
            UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.listIDKey)
            listTitle = calendar.title
            return calendar
        } catch {
            return nil
        }
    }

    private func refreshLists() {
        lists = store.calendars(for: .reminder)
            .map { ListChoice(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if let saved = UserDefaults.standard.string(forKey: Self.listIDKey),
           let match = lists.first(where: { $0.id == saved }) {
            listTitle = match.title
        }
    }

    private func currentList() -> EKCalendar? {
        ensureList()
    }

    func push() async {
        guard isEnabled, !isPushing, let list = currentList() else { return }
        isPushing = true
        defer { isPushing = false }

        guard let reminders = await fetchReminders(in: list) else { return }
        var todos = Self.currentTodos()
        var used = Set<String>()
        let previousIDs = Set(UserDefaults.standard.stringArray(forKey: Self.pushedIDsKey) ?? [])

        for index in todos.indices {
            let match = unmatched(reminders, for: todos[index], used: used)
            let reminder = match ?? EKReminder(eventStore: store)
            write(todos[index], to: reminder, list: list)
            do {
                try store.save(reminder, commit: true)
            } catch {
                continue
            }
            let identifier = reminder.calendarItemIdentifier
            if !identifier.isEmpty {
                todos[index].externalIdentifier = identifier
                used.insert(identifier)
            }
        }

        let liveIDs = Set(todos.compactMap(\.externalIdentifier))
        for identifier in previousIDs.subtracting(liveIDs) {
            if let item = store.calendarItem(withIdentifier: identifier) {
                try? store.remove(item, commit: true)
            }
        }
        UserDefaults.standard.set(Array(liveIDs), forKey: Self.pushedIDsKey)

        writeTodosIfNeeded(todos)
        lastPushedRaw = Self.currentRaw()
    }

    func pull() async {
        guard isEnabled, !isPushing, !isApplyingRemote, let list = currentList() else { return }
        guard let reminders = await fetchReminders(in: list) else { return }
        var todos = Self.currentTodos()
        var seen = Set<UUID>()

        for reminder in reminders {
            if let index = todos.firstIndex(where: { matches($0, reminder) }) {
                todos[index] = applyReminder(reminder, to: todos[index])
                seen.insert(todos[index].id)
            } else {
                var created = todo(from: reminder)
                todos.append(created)
                seen.insert(created.id)
                reminder.url = URL(string: "ourweek://todo/\(created.id.uuidString)")
                try? store.save(reminder, commit: true)
                created.externalIdentifier = reminder.calendarItemIdentifier
                if let index = todos.firstIndex(where: { $0.id == created.id }) {
                    todos[index] = created
                }
            }
        }

        let knownIDs = Set(reminders.map(\.calendarItemIdentifier))
        todos.removeAll { todo in
            guard let external = todo.externalIdentifier, !external.isEmpty else { return false }
            return !knownIDs.contains(external)
        }

        writeTodosIfNeeded(todos)
        lastPushedRaw = Self.currentRaw()
        HomeWidgetStore.noteTodosChanged()
    }

    private func write(_ todo: TodoTask, to reminder: EKReminder, list: EKCalendar) {
        reminder.calendar = list
        reminder.title = todo.title
        reminder.notes = todo.subtitle.isEmpty ? nil : todo.subtitle
        reminder.isCompleted = todo.isChecked
        reminder.url = URL(string: "ourweek://todo/\(todo.id.uuidString)")
        if let due = dueDate(for: todo) {
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: due)
            if let minutes = todo.dueMinutes {
                parts.hour = minutes / 60
                parts.minute = minutes % 60
            }
            reminder.dueDateComponents = parts
        } else {
            reminder.dueDateComponents = nil
        }
    }

    private func applyReminder(_ reminder: EKReminder, to todo: TodoTask) -> TodoTask {
        var next = todo
        next.title = (reminder.title ?? todo.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if next.title.isEmpty { next.title = todo.title }
        if let notes = reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            next.subtitle = notes
        }
        next.isChecked = reminder.isCompleted
        next.externalIdentifier = reminder.calendarItemIdentifier
        if let parts = reminder.dueDateComponents, let date = Calendar.current.date(from: parts) {
            next.dueDay = TodoTask.dayKey(for: date)
            if parts.hour != nil {
                next.dueMinutes = TodoTask.minutes(from: date)
            } else {
                next.dueMinutes = nil
            }
        } else {
            next.dueDay = nil
            next.dueMinutes = nil
        }
        return next
    }

    private func todo(from reminder: EKReminder) -> TodoTask {
        var task = TodoTask(title: (reminder.title ?? "To-do").trimmingCharacters(in: .whitespacesAndNewlines))
        if task.title.isEmpty { task.title = "To-do" }
        if let id = todoID(in: reminder) {
            task.id = id
        }
        return applyReminder(reminder, to: task)
    }

    private func matches(_ todo: TodoTask, _ reminder: EKReminder) -> Bool {
        if let id = todoID(in: reminder), id == todo.id { return true }
        if let external = todo.externalIdentifier, external == reminder.calendarItemIdentifier { return true }
        return false
    }

    private func unmatched(_ reminders: [EKReminder], for todo: TodoTask, used: Set<String>) -> EKReminder? {
        if let external = todo.externalIdentifier,
           let found = reminders.first(where: { $0.calendarItemIdentifier == external && !used.contains(external) }) {
            return found
        }
        if let found = reminders.first(where: { reminder in
            guard let id = todoID(in: reminder), id == todo.id else { return false }
            return !used.contains(reminder.calendarItemIdentifier)
        }) {
            return found
        }
        return reminders.first { reminder in
            let identifier = reminder.calendarItemIdentifier
            guard !used.contains(identifier) else { return false }
            let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.caseInsensitiveCompare(todo.title) == .orderedSame else { return false }
            return sameDue(reminder, todo)
        }
    }

    private func sameDue(_ reminder: EKReminder, _ todo: TodoTask) -> Bool {
        guard let parts = reminder.dueDateComponents, let date = Calendar.current.date(from: parts) else {
            return todo.dueDay == nil
        }
        guard TodoTask.dayKey(for: date) == todo.dueDay else { return false }
        if parts.hour == nil { return todo.dueMinutes == nil }
        return TodoTask.minutes(from: date) == todo.dueMinutes
    }

    private func dueDate(for todo: TodoTask) -> Date? {
        guard let key = todo.dueDay, let day = TodoTask.date(fromDayKey: key) else { return nil }
        guard let minutes = todo.dueMinutes else { return day }
        return Calendar.current.date(byAdding: .minute, value: minutes, to: day)
    }

    private func todoID(in reminder: EKReminder) -> UUID? {
        guard let host = reminder.url?.host, host == "todo" else { return nil }
        let raw = reminder.url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        return UUID(uuidString: raw)
    }

    private func fetchReminders(in list: EKCalendar) async -> [EKReminder]? {
        let open = store.predicateForReminders(in: [list])
        let start = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? .distantPast
        let end = Calendar.current.date(byAdding: .year, value: 2, to: Date()) ?? .distantFuture
        let done = store.predicateForCompletedReminders(
            withCompletionDateStarting: start,
            ending: end,
            calendars: [list]
        )
        guard let unfinished = await fetch(open), let finished = await fetch(done) else { return nil }
        var seen = Set<String>()
        return (unfinished + finished).filter { reminder in
            let id = reminder.calendarItemIdentifier
            guard !id.isEmpty, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private func fetch(_ predicate: NSPredicate) async -> [EKReminder]? {
        await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders)
            }
        }
    }

    private func writeTodosIfNeeded(_ todos: [TodoTask]) {
        let encoded = TodosWrapper(todos: todos).rawValue
        guard encoded != Self.currentRaw() else { return }
        isApplyingRemote = true
        UserDefaults.standard.set(encoded, forKey: "homeTodosWrapper")
        isApplyingRemote = false
    }

    private static func currentRaw() -> String {
        UserDefaults.standard.string(forKey: "homeTodosWrapper") ?? ""
    }

    private static func currentTodos() -> [TodoTask] {
        guard let wrapper = TodosWrapper(rawValue: currentRaw()) else { return [] }
        return wrapper.todos
    }
}

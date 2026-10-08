import SwiftUI
import UIKit
import CoreData
import EventKit
import EventKitUI
import UniformTypeIdentifiers

enum AddFanAction: String, CaseIterable, Identifiable {
    case recipe
    case todo
    case shopping
    case meal
    case event

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recipe: return "Recipe"
        case .todo: return "To-do"
        case .shopping: return "Shop"
        case .meal: return "Meal"
        case .event: return "Event"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .recipe: return "Add recipe"
        case .todo: return "Add to-do"
        case .shopping: return "Add shopping item"
        case .meal: return "Add meal"
        case .event: return "Add event"
        }
    }

    var symbol: String {
        switch self {
        case .recipe: return "book.closed"
        case .todo: return "checkmark"
        case .shopping: return "cart"
        case .meal: return "fork.knife"
        case .event: return "calendar"
        }
    }
}

extension Notification.Name {
    /// A meal or local plan changed outside the week card, so Home and Calendar can reload.
    static let ourWeekPlansChanged = Notification.Name("ourWeekPlansChanged")
}

/// Today, or the next day in the next two weeks that has no dinner yet.
func nextOpenDinnerDay(using dataManager: DataManager) -> Date {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    for offset in 0..<14 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
        let dinners = dataManager.fetchMealPlans(for: day).filter { meal in
            let type = (meal.mealType ?? "dinner").lowercased()
            let title = (meal.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return type == "dinner" && !title.isEmpty
        }
        if dinners.isEmpty { return day }
    }
    return today
}

// MARK: - Fan

struct AddFanChips: View {
    var onSelect: (AddFanAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    private let actions = AddFanAction.allCases

    var body: some View {
        GeometryReader { geo in
            let radius = fanRadius(width: geo.size.width)
            ZStack {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    let point = arcPoint(index: index, count: actions.count, radius: radius)
                    chip(action)
                        .offset(x: place(point.x), y: place(point.y))
                        .opacity(reduceMotion || shown ? 1 : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 250)
        .padding(.bottom, -8)
        .allowsHitTesting(reduceMotion || shown)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.74)) {
                    shown = true
                }
            }
        }
    }

    private func place(_ value: CGFloat) -> CGFloat {
        if reduceMotion || shown { return value }
        return value * 0.2
    }

    /// Wide enough that a capsule under one icon clears the next icon.
    private func fanRadius(width: CGFloat) -> CGFloat {
        let side = CGFloat(sin((132.0 * .pi / 180) / 2))
        let fitted = (width / 2 - 42) / side
        return min(164, max(148, fitted))
    }

    private func arcPoint(index: Int, count: Int, radius: CGFloat) -> CGPoint {
        let spread = 132.0 * Double.pi / 180
        let step = count > 1 ? spread / Double(count - 1) : 0
        let theta = -spread / 2 + step * Double(index)
        return CGPoint(
            x: CGFloat(sin(theta)) * radius,
            y: -CGFloat(cos(theta)) * radius
        )
    }

    private func chip(_ action: AddFanAction) -> some View {
        Button {
            onSelect(action)
        } label: {
            ZStack {
                Image(systemName: action.symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.terra500)
                    .frame(width: 46, height: 46)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.08), radius: 8, y: 3)
                Text(action.title)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.14), radius: 5, y: 2)
                    )
                    .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                    .offset(y: 40)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.accessibilityTitle)
    }
}

// MARK: - To-do

struct QuickTodoAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RemindersSync.self) private var remindersSync
    @AppStorage("homeTodosWrapper") private var storedTodos = ""

    @State private var title = ""
    @State private var includeDate = false
    @State private var includeTime = false
    @State private var day = Calendar.current.startOfDay(for: Date())
    @State private var time = Date()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add a to-do")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)

            TextField("What needs doing?", text: $title)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(saveIfReady)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HomeQuiet.buttonStroke, lineWidth: 1))

            if includeDate {
                DatePicker("Date", selection: $day, displayedComponents: .date)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .tint(Color.terra500)
            } else {
                disclosure("Add date") { includeDate = true }
            }

            if includeTime {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .tint(Color.terra500)
            } else {
                disclosure("Add time") { includeTime = true }
            }

            if !trimmedTitle.isEmpty {
                Button(action: saveIfReady) {
                    Text("Add")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.terra500))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgBase)
        .onAppear { focused = true }
        .onTapGesture { focused = false }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func disclosure(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .regular, design: .serif))
                .foregroundStyle(Color.terra500)
        }
        .buttonStyle(.plain)
    }

    private func saveIfReady() {
        let name = trimmedTitle
        guard !name.isEmpty else { return }
        var task = TodoTask(title: name, subtitle: "", subtitleColorHex: "terra")
        if includeDate {
            task.dueDay = TodoTask.dayKey(for: day)
        }
        if includeTime {
            task.dueMinutes = TodoTask.minutes(from: time)
        }
        var items = currentTodos
        items.append(task)
        storedTodos = TodosWrapper(todos: items).rawValue
        remindersSync.noteLocalTodosChanged()
        dismiss()
    }

    private var currentTodos: [TodoTask] {
        if !storedTodos.isEmpty, let wrapper = TodosWrapper(rawValue: storedTodos) {
            return wrapper.todos
        }
        return [
            TodoTask(title: "Morning Pilates", subtitle: "7:30 AM • Studio", subtitleColorHex: "terra"),
            TodoTask(title: "Grocery Run", subtitle: "Whole Foods", subtitleColorHex: "lilac")
        ]
    }
}

// MARK: - Shopping

struct QuickShoppingAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager

    @State private var title = ""
    @State private var lists: [ShoppingList] = []
    @State private var listID: NSManagedObjectID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add an item")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)

            TextField("Item", text: $title)
                .font(.system(size: 17, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(saveIfReady)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(HomeQuiet.buttonStroke, lineWidth: 1))

            if lists.count > 1 {
                Menu {
                    ForEach(lists, id: \.objectID) { list in
                        Button(list.name ?? "List") {
                            listID = list.objectID
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedListName)
                            .font(.system(size: 15, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                    }
                    .padding(16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                }
                .accessibilityLabel("Shopping section, \(selectedListName)")
            }

            if !trimmedTitle.isEmpty {
                Button(action: saveIfReady) {
                    Text("Add")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.terra500))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgBase)
        .onAppear {
            lists = dataManager.fetchShoppingLists()
            if lists.isEmpty {
                _ = dataManager.createShoppingList(name: "Grocery Store")
                _ = dataManager.createShoppingList(name: "Costco")
                _ = dataManager.createShoppingList(name: "Trader Joe's")
                lists = dataManager.fetchShoppingLists()
            }
            listID = lists.first?.objectID
            focused = true
        }
        .onTapGesture { focused = false }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedListName: String {
        lists.first { $0.objectID == listID }?.name ?? lists.first?.name ?? "List"
    }

    private func saveIfReady() {
        let name = CookingAmount.reformatLine(trimmedTitle)
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let list = lists.first { $0.objectID == listID } ?? lists.first
        guard let list else { return }
        _ = dataManager.addShoppingItem(name: name, quantity: "", to: list)
        NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
        dismiss()
    }
}

// MARK: - Event

struct EventEditorRequest: Identifiable {
    let id = UUID()
    let store: EKEventStore
    let event: EKEvent
}

enum AddFanEventPrep {
    @MainActor
    static func makeRequest(sync: CalendarSyncManager) async -> EventEditorRequest {
        let store = EKEventStore()
        // A store created before access stays empty. Ask again on this new store;
        // a grant that already exists does not prompt a second time.
        _ = try? await store.requestFullAccessToEvents()
        let event = EKEvent(eventStore: store)
        let start = Date()
        event.startDate = start
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(3600)
        event.calendar = calendar(in: store, sync: sync)
        return EventEditorRequest(store: store, event: event)
    }

    private static func calendar(in store: EKEventStore, sync: CalendarSyncManager) -> EKCalendar? {
        if let id = sync.writeBackCalendarID, let match = store.calendar(withIdentifier: id), match.allowsContentModifications {
            return match
        }
        let selected = sync.selectedCalendarIDs
        if let match = store.calendars(for: .event).first(where: { selected.contains($0.calendarIdentifier) && $0.allowsContentModifications }) {
            return match
        }
        return store.defaultCalendarForNewEvents
    }
}

/// Presents the system editor from a host. EventKit expects that editor to be
/// presented, and the delegate is the one that dismisses it.
struct SystemEventEditor: UIViewControllerRepresentable {
    var request: EventEditorRequest
    var onFinish: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> EventEditorHost {
        let host = EventEditorHost()
        host.view.backgroundColor = .systemBackground
        return host
    }

    func updateUIViewController(_ host: EventEditorHost, context: Context) {
        context.coordinator.onFinish = onFinish
        let present = { [weak host] in
            guard let host else { return }
            context.coordinator.presentIfNeeded(from: host, request: request)
        }
        host.onAppear = present
        if host.view.window != nil {
            present()
        }
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        var onFinish: () -> Void
        private var presented = false

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func presentIfNeeded(from host: UIViewController, request: EventEditorRequest) {
            guard !presented, host.presentedViewController == nil else { return }
            presented = true
            let editor = EKEventEditViewController()
            editor.eventStore = request.store
            editor.event = request.event
            editor.editViewDelegate = self
            host.present(editor, animated: true)
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            controller.dismiss(animated: true) {
                self.onFinish()
            }
        }
    }
}

final class EventEditorHost: UIViewController {
    var onAppear: (() -> Void)?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}

// MARK: - Recipe

private enum QuickRecipeFollowUp {
    case paste(text: String, url: String)
    case manual(title: String, url: String)
}

/// The existing recipe entry choices, then the same importers the Meals tab uses.
struct QuickRecipeAddHost: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showURLImport = false
    @State private var showPasteImport = false
    @State private var showPhotoImport = false
    @State private var showManual = false
    @State private var showPackPicker = false
    @State private var scrapedRecipe: ScrapedRecipe?
    @State private var pastedRecipe: ScrapedRecipe?
    @State private var photoRecipe: ScrapedRecipe?
    @State private var previewRecipe: ScrapedRecipe?
    @State private var urlFailure: URLImportFailure?
    @State private var urlImportSeed = ""
    @State private var urlImportToken = UUID()
    @State private var urlFollowUp: QuickRecipeFollowUp?
    @State private var pasteSeedText = ""
    @State private var pasteSourceURL = ""
    @State private var photoFollowUp: AddRecipeRoute?
    @State private var manualSeedName = ""
    @State private var manualSeedURL = ""
    @State private var loadedPack: LoadedRecipePack?
    @State private var packLoadError: String?

    var body: some View {
        AddRecipeEntrySheet { route in
            open(route)
        }
        .background(Color.bgBase)
        .sheet(isPresented: $showURLImport, onDismiss: finishURL) {
            URLImportView(
                scrapedRecipe: $scrapedRecipe,
                showPreview: .constant(false),
                initialURL: urlImportSeed,
                initialFailure: urlFailure,
                onPaste: { url, text in
                    urlFollowUp = .paste(text: text, url: url)
                    showURLImport = false
                },
                onManual: { url, title in
                    urlFollowUp = .manual(title: title, url: url)
                    showURLImport = false
                }
            )
            .id(urlImportToken)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPasteImport, onDismiss: finishPaste) {
            PasteImportView(scrapedRecipe: $pastedRecipe, initialText: pasteSeedText, sourceURL: pasteSourceURL)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPhotoImport, onDismiss: finishPhoto) {
            PhotoImportView(
                scrapedRecipe: $photoRecipe,
                initialImageData: nil,
                onPaste: {
                    photoFollowUp = .paste
                    showPhotoImport = false
                },
                onManual: {
                    photoFollowUp = .manual
                    showPhotoImport = false
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showManual) {
            AddRecipeView(recipe: nil, initialName: manualSeedName, initialSourceURL: manualSeedURL)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $previewRecipe) { recipe in
            ImportPreviewView(scrapedRecipe: recipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $loadedPack) { pack in
            RecipePackImportView(loaded: pack)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showPackPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePack(result)
        }
        .alert("Couldn't Import Pack", isPresented: Binding(
            get: { packLoadError != nil },
            set: { if !$0 { packLoadError = nil } }
        )) {
            Button("OK", role: .cancel) { packLoadError = nil }
        } message: {
            Text(packLoadError ?? "")
        }
    }

    private func open(_ route: AddRecipeRoute) {
        switch route {
        case .link:
            urlFailure = nil
            urlImportSeed = ""
            urlImportToken = UUID()
            showURLImport = true
        case .paste:
            pasteSeedText = ""
            pasteSourceURL = ""
            showPasteImport = true
        case .photo:
            showPhotoImport = true
        case .manual:
            manualSeedName = ""
            manualSeedURL = ""
            showManual = true
        case .pack:
            showPackPicker = true
        }
    }

    private func finishURL() {
        urlImportSeed = ""
        urlFailure = nil
        if let recipe = scrapedRecipe {
            scrapedRecipe = nil
            presentPreview(recipe)
        } else if let follow = urlFollowUp {
            urlFollowUp = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                switch follow {
                case .paste(let text, let url):
                    pasteSeedText = text
                    pasteSourceURL = url
                    showPasteImport = true
                case .manual(let title, let url):
                    manualSeedName = title
                    manualSeedURL = url
                    showManual = true
                }
            }
        }
    }

    private func finishPaste() {
        pasteSeedText = ""
        pasteSourceURL = ""
        if let recipe = pastedRecipe {
            pastedRecipe = nil
            presentPreview(recipe)
        }
    }

    private func finishPhoto() {
        if let recipe = photoRecipe {
            photoRecipe = nil
            presentPreview(recipe)
        } else if let next = photoFollowUp {
            photoFollowUp = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                switch next {
                case .paste:
                    pasteSeedText = ""
                    pasteSourceURL = ""
                    showPasteImport = true
                case .manual:
                    manualSeedName = ""
                    manualSeedURL = ""
                    showManual = true
                default:
                    break
                }
            }
        }
    }

    private func presentPreview(_ recipe: ScrapedRecipe) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            previewRecipe = recipe
        }
    }

    private func handlePack(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let pack = try RecipePackParser.parse(url: url)
                let loaded = LoadedRecipePack(pack: pack, fileName: url.lastPathComponent)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    loadedPack = loaded
                }
            } catch {
                packLoadError = error.localizedDescription
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError { return }
            packLoadError = error.localizedDescription
        }
    }
}

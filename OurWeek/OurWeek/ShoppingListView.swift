import SwiftUI
import UIKit
import PhotosUI
import CoreData

// MARK: - Shopping Undo Stack
@Observable
class ShoppingUndoStack {
    struct Action {
        let undo: () -> Void
        let redo: () -> Void
    }

    private var undoStack: [Action] = []
    private var redoStack: [Action] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func register(undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoStack.append(Action(undo: undo, redo: redo))
        redoStack.removeAll()
    }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
    }
}

extension Notification.Name {
    /// A grocery add-row took the keyboard, so the home meal field should let go.
    static let shoppingItemFieldFocused = Notification.Name("shoppingItemFieldFocused")
}

/// Selection actions for the bar that floats above the tab bar.
@MainActor
@Observable
final class ShoppingSelectChrome {
    var count = 0
    var canMove = false
    var checkOff: () -> Void = {}
    var move: () -> Void = {}
    var delete: () -> Void = {}

    func update(
        count: Int,
        canMove: Bool,
        checkOff: @escaping () -> Void,
        move: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        self.count = count
        self.canMove = canMove
        self.checkOff = checkOff
        self.move = move
        self.delete = delete
    }

    func clear() {
        guard count != 0 || canMove else { return }
        count = 0
        canMove = false
        checkOff = {}
        move = {}
        delete = {}
    }
}

struct ShoppingSelectActionBar: View {
    var count: Int
    var canMove: Bool
    var onCheckOff: () -> Void
    var onMove: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text("\(count)")
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(Color.terra500)
                .frame(minWidth: 24)
            barAction("Check off", "checkmark", onCheckOff)
            if canMove {
                barAction("Move", "arrow.right", onMove)
            }
            barAction("Delete", "trash", onDelete)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 14, y: 4)
        .padding(.horizontal, 20)
    }

    private func barAction(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                Text(title)
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(title == "Delete" ? Color.terra600 : HomeQuiet.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private func noteShoppingRemovals(_ items: [ShoppingItem]) {
    WeekGrocerySync.noteUserRemoved(itemIDs: items.compactMap(\.id))
}

private func shoppingTextInputIsFirstResponder() -> Bool {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for window in scenes.flatMap(\.windows) {
        if window.shoppingContainsFirstResponderTextInput { return true }
    }
    return false
}

private extension UIView {
    var shoppingContainsFirstResponderTextInput: Bool {
        if isFirstResponder, self is UITextField || self is UITextView { return true }
        for subview in subviews where subview.shoppingContainsFirstResponderTextInput {
            return true
        }
        return false
    }
}

// MARK: - Shopping List View
struct ShoppingListView: View {
    @Binding var showSharingSettings: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ShoppingListHeader(showSharingSettings: $showSharingSettings)
                MealPlanCarousel()
                    .padding(.top, 16)
                ShoppingListBoard(reservesTabBarSpace: true, quietToolbar: true)
            }
        }
        .background(Color.bgBase)
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

/// Store sections, items, check-off, and add controls. Same lists as the Shop tab.
/// The week meal cards stay on Shop only.
struct ShoppingListBoard: View {
    var reservesTabBarSpace: Bool = false
    /// Quiet white capsules on Home and Shop.
    var quietToolbar: Bool = false
    /// Home labels the grocery controls. Shop already has a Shopping title.
    var showsSectionLabel: Bool = false

    @Environment(DataManager.self) private var dataManager
    @State private var undoStack = ShoppingUndoStack()
    @State private var shoppingLists: [ShoppingList] = []
    @State private var isReorderMode = false
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var showSyncModal = false
    @State private var showPantrySheet = false
    @State private var showAddSectionModal = false
    @State private var showEditModal = false
    @State private var showMoveSheet = false
    @State private var showBulkDeleteConfirm = false
    @State private var bulkRevision = 0

    @Environment(ShoppingSelectChrome.self) private var shoppingSelectChrome

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            shoppingHeader
                .padding(.horizontal, 24)
                .padding(.top, showsSectionLabel ? 36 : (quietToolbar ? 8 : 12))
                .padding(.bottom, 2)

            if isReorderMode {
                if quietToolbar {
                    HStack(spacing: 12) {
                        Text("Drag sections or use the arrows")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                        Spacer(minLength: 8)
                        Button("Done") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isReorderMode = false
                            }
                        }
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Drag sections or use arrows to reorder")
                            .font(.system(size: 13, weight: .regular))
                        Spacer()
                        Button("Done") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isReorderMode = false
                            }
                        }
                        .font(.system(size: 13, weight: .regular))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sky400, lineWidth: 1))
                    }
                    .foregroundStyle(Color(red: 0.03, green: 0.45, blue: 0.70))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.sky100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sky200, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            VStack(spacing: quietToolbar ? 14 : 20) {
                if shoppingLists.isEmpty {
                    if quietToolbar {
                        VStack(spacing: 8) {
                            Text("No lists yet")
                                .font(.system(size: 20, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                            Text("Add a section to start a store list.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(HomeQuiet.quiet)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity)
                        .homeQuietCard()
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.terra400)
                            Text("No Shopping Lists Yet")
                                .font(.system(size: 18, weight: .regular, design: .serif))
                            Text("Use the Add Section button above to create a store list.")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(Array(shoppingLists.enumerated()), id: \.element.objectID) { index, list in
                        StoreSection(
                            list: list,
                            storeName: list.name ?? "Unknown Store",
                            icon: icon(for: list.name ?? ""),
                            accentColor: accentColor(for: list.name ?? ""),
                            accentLight: accentLight(for: list.name ?? ""),
                            borderColor: accentColor(for: list.name ?? ""),
                            shadowColor: accentColor(for: list.name ?? ""),
                            badgeBg: accentLight(for: list.name ?? ""),
                            badgeText: darkerColor(for: list.name ?? ""),
                            checkBorder: accentLight(for: list.name ?? "").opacity(0.8),
                            checkFill: accentColor(for: list.name ?? ""),
                            dividerColor: accentLight(for: list.name ?? ""),
                            headerColor: darkerColor(for: list.name ?? ""),
                            quiet: quietToolbar,
                            undoStack: undoStack,
                            isReorderMode: isReorderMode,
                            isSelectMode: isSelectMode,
                            selectedIDs: $selectedIDs,
                            isFirst: index == 0,
                            isLast: index == shoppingLists.count - 1,
                            onMoveUp: {
                                guard index > 0 else { return }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    shoppingLists.swapAt(index, index - 1)
                                    dataManager.reorderShoppingLists(shoppingLists)
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            },
                            onMoveDown: {
                                guard index < shoppingLists.count - 1 else { return }
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    shoppingLists.swapAt(index, index + 1)
                                    dataManager.reorderShoppingLists(shoppingLists)
                                }
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            },
                            onDelete: {
                                let items = (list.items as? Set<ShoppingItem>) ?? []
                                noteShoppingRemovals(Array(items))
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    dataManager.deleteShoppingList(list)
                                    selectedIDs.subtract(items.compactMap(\.id))
                                    loadLists()
                                }
                            }
                        )
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            Button(action: { showSyncModal = true }) {
                if quietToolbar {
                    Text("Sync with meal plan")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .bold))
                        Text("SYNC WITH MEAL PLAN")
                            .font(.system(size: 14, weight: .regular))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Color.terra500
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.terra600, lineWidth: 1)
                    )
                    .boldShadow(Color.terra600, size: 4)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.top, quietToolbar ? 16 : 24)
            .padding(.bottom, (reservesTabBarSpace ? 120 : 0) + (selectionBarVisible ? 72 : 0))
        }
        .background(ParentScrollDirectionLock())
        .onAppear {
            loadLists()
            publishSelectChrome()
        }
        .onDisappear {
            shoppingSelectChrome.clear()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitDataDidChange"))) { _ in
            loadLists()
        }
        .onChange(of: isSelectMode) { _, on in
            if !on { selectedIDs.removeAll() }
            publishSelectChrome()
        }
        .onChange(of: selectedIDs) { _, _ in
            publishSelectChrome()
        }
        .sheet(isPresented: $showAddSectionModal) {
            AddSectionModal(onAdd: { loadLists() }, quiet: quietToolbar)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditModal) {
            EditListModal(shoppingLists: $shoppingLists, onListsChanged: { loadLists() }, quiet: quietToolbar)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSyncModal) {
            SyncModal(quiet: quietToolbar)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPantrySheet) {
            PantryStaplesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.bgBase)
        }
        .sheet(isPresented: $showMoveSheet) {
            MoveToSectionSheet(
                sections: shoppingLists,
                selectedItems: selectedShoppingItems(),
                onMove: { list in
                    moveSelection(to: list)
                    showMoveSheet = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.bgBase)
        }
        .sheet(isPresented: $showBulkDeleteConfirm) {
            QuietDeleteConfirm(
                count: selectedShoppingItems().count,
                onCancel: { showBulkDeleteConfirm = false },
                onDelete: {
                    deleteSelection()
                    showBulkDeleteConfirm = false
                }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.bgBase)
        }
    }

    private var everyItem: [ShoppingItem] {
        dataManager.allShoppingItems()
    }

    private var hasCheckedItems: Bool {
        _ = bulkRevision
        return everyItem.contains(where: \.isChecked)
    }

    private var hasItems: Bool {
        everyItem.contains { $0.id != nil }
    }

    private var allItemsSelected: Bool {
        let ids = Set(everyItem.compactMap(\.id))
        return !ids.isEmpty && ids.isSubset(of: selectedIDs)
    }

    private var selectionBarVisible: Bool {
        isSelectMode && !selectedIDs.isEmpty
    }

    private var shoppingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            if isSelectMode {
                if hasItems {
                    Button(allItemsSelected ? "Select none" : "Select all") {
                        if allItemsSelected {
                            selectNone()
                        } else {
                            selectAll()
                        }
                    }
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(HomeQuiet.ink)
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 8)
                Button("Done") {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelectMode = false
                    }
                }
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.terra500)
                .buttonStyle(.plain)
            } else {
                if showsSectionLabel {
                    Text("SHOPPING")
                        .font(.system(size: 11, weight: .regular))
                        .tracking(1.4)
                        .foregroundStyle(HomeQuiet.quiet)
                }
                Spacer(minLength: 8)
                groceryMenu
            }
        }
    }

    private var groceryMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isSelectMode = true
                    isReorderMode = false
                }
            }
            Button(isReorderMode ? "Done" : "Reorder", systemImage: "arrow.up.arrow.down") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isReorderMode.toggle()
                    if isReorderMode { isSelectMode = false }
                }
            }
            Button("Add section", systemImage: "plus") { showAddSectionModal = true }
            Button("Edit", systemImage: "pencil") { showEditModal = true }
            Button("Sync", systemImage: "arrow.triangle.2.circlepath") { showSyncModal = true }
            Button("Pantry staples", systemImage: "cabinet") { showPantrySheet = true }
            if hasCheckedItems {
                Button("Clear checked", systemImage: "trash") { clearChecked() }
                Button("Uncheck all", systemImage: "circle") { uncheckAll() }
            }
            if undoStack.canUndo {
                Button("Undo", systemImage: "arrow.uturn.backward") { undoStack.undo() }
            }
            if undoStack.canRedo {
                Button("Redo", systemImage: "arrow.uturn.forward") { undoStack.redo() }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HomeQuiet.ink)
                .frame(width: 44, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func publishSelectChrome() {
        let items = selectedShoppingItems()
        guard isSelectMode, !items.isEmpty else {
            shoppingSelectChrome.clear()
            return
        }
        shoppingSelectChrome.update(
            count: items.count,
            canMove: shoppingLists.contains { list in
                !items.allSatisfy { $0.list?.objectID == list.objectID }
            },
            checkOff: { setSelectionChecked(true) },
            move: { showMoveSheet = true },
            delete: { showBulkDeleteConfirm = true }
        )
    }

    private func selectedShoppingItems() -> [ShoppingItem] {
        everyItem.filter { item in
            guard let id = item.id else { return false }
            return selectedIDs.contains(id)
        }
    }

    private func selectAll() {
        selectedIDs = Set(everyItem.compactMap(\.id))
    }

    private func selectNone() {
        selectedIDs.removeAll()
    }

    private func setSelectionChecked(_ checked: Bool) {
        dataManager.setShoppingItemsChecked(selectedShoppingItems(), checked: checked)
        postShoppingChange()
    }

    private func clearChecked() {
        let items = everyItem.filter(\.isChecked)
        noteShoppingRemovals(items)
        let ids = Set(items.compactMap(\.id))
        dataManager.deleteShoppingItems(items)
        selectedIDs.subtract(ids)
        postShoppingChange()
    }

    private func uncheckAll() {
        dataManager.setShoppingItemsChecked(everyItem.filter(\.isChecked), checked: false)
        postShoppingChange()
    }

    private func deleteSelection() {
        let items = selectedShoppingItems()
        noteShoppingRemovals(items)
        dataManager.deleteShoppingItems(items)
        selectedIDs.removeAll()
        postShoppingChange()
    }

    private func moveSelection(to list: ShoppingList) {
        dataManager.moveShoppingItems(selectedShoppingItems(), to: list)
        postShoppingChange()
    }

    private func postShoppingChange() {
        bulkRevision += 1
        NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
    }

    private func loadLists() {
        shoppingLists = dataManager.fetchShoppingLists()

        if shoppingLists.isEmpty {
            _ = dataManager.createShoppingList(name: "Grocery Store")
            _ = dataManager.createShoppingList(name: "Costco")
            _ = dataManager.createShoppingList(name: "Trader Joe's")
            shoppingLists = dataManager.fetchShoppingLists()
        }
    }

    private func icon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("grocery") || n.contains("smith") { return "storefront" }
        if n.contains("costco") || n.contains("sams") { return "tag" }
        if n.contains("trader") || n.contains("sprouts") { return "basket" }
        if n.contains("walmart") || n.contains("target") { return "cart" }
        return "list.bullet.clipboard"
    }

    private func accentColor(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("grocery") { return Color.lime500 }
        if n.contains("costco") { return Color.sky400 }
        if n.contains("trader") { return Color.terra500 }
        if n.contains("walmart") { return Color.lilac500 }
        return Color.peach500
    }

    private func accentLight(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("grocery") { return Color.lime100 }
        if n.contains("costco") { return Color.sky100 }
        if n.contains("trader") { return Color.terra100 }
        if n.contains("walmart") { return Color.lilac100 }
        return Color.orange.opacity(0.1)
    }

    private func darkerColor(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("grocery") { return Color(red: 0.26, green: 0.53, blue: 0.09) }
        if n.contains("costco") { return Color(red: 0.03, green: 0.45, blue: 0.70) }
        if n.contains("trader") { return Color.terra600 }
        if n.contains("walmart") { return Color.lilac600 }
        return Color.orange
    }
}

// MARK: - Header
struct ShoppingListHeader: View {
    @Binding var showSharingSettings: Bool

    @State private var showProfileMenu = false

    @AppStorage("profileImageData") private var profileImageData: Data?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SHOP")
                    .font(.system(size: 12, weight: .regular))
                    .tracking(1.6)
                    .foregroundStyle(HomeQuiet.quiet)
                Text("Shopping")
                    .font(.system(size: 40, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                Text("GROUPED BY STORE")
                    .font(.system(size: 11, weight: .regular))
                    .tracking(1.2)
                    .foregroundStyle(HomeQuiet.quiet)
                    .padding(.top, 4)
            }
            Spacer()
            // Profile avatar button
            Button(action: { showProfileMenu = true }) {
                AvatarButton(imageData: profileImageData)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuSheet(
                onSharingTapped: { showSharingSettings = true }
            )
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Shopping Item Model
struct ShopListEntry: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var quantity: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ShopListEntry, rhs: ShopListEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Store Section Card
struct StoreSection: View {
    let list: ShoppingList
    let storeName: String
    let icon: String
    let accentColor: Color
    let accentLight: Color
    let borderColor: Color
    let shadowColor: Color
    let badgeBg: Color
    let badgeText: Color
    let checkBorder: Color
    let checkFill: Color
    let dividerColor: Color
    let headerColor: Color
    var quiet: Bool = false
    var undoStack: ShoppingUndoStack
    var isReorderMode: Bool = false
    var isSelectMode: Bool = false
    var selectedIDs: Binding<Set<UUID>> = .constant([])
    var isFirst: Bool = false
    var isLast: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(DataManager.self) private var dataManager
    @State private var allItems: [ShoppingItem] = []
    @State private var isExpanded: Bool = true
    @State private var newItemTexts: [UUID: String] = [:]
    @State private var addRowIDs: [UUID] = []
    /// Which row owns the keyboard. A tap focuses that field; a drag is left to the list.
    @State private var focusedLine: ShoppingLine?
    /// Set only for a programmatic move, so a finger tap can keep the caret where it landed.
    @State private var focusCursorAtEnd = false
    @State private var editingItem: ShoppingItem?

    private enum ShoppingLine: Hashable {
        case item(NSManagedObjectID)
        case add(UUID)
    }
    /// Height of the non-scrolling item list, so the page scroll view can move.
    @State private var itemsHeight: CGFloat = 0

    private func ensureOneAddRow() {
        if addRowIDs.isEmpty {
            let id = UUID()
            addRowIDs.append(id)
            newItemTexts[id] = ""
        }
    }

    private func commitRow(_ id: UUID) {
        let text = (newItemTexts[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Core Data creation
        let formatted = CookingAmount.reformatLine(text)
        let newItem = dataManager.addShoppingItem(name: formatted, quantity: "", to: list)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            allItems.append(newItem)
        }

        // Register undo/redo
        undoStack.register(
            undo: {
                noteShoppingRemovals([newItem])
                self.dataManager.delete(newItem)
                withAnimation { self.loadItems() }
            },
            redo: {
                _ = self.dataManager.addShoppingItem(name: formatted, quantity: "", to: self.list)
                withAnimation { self.loadItems() }
            }
        )

        // Remove the committed row
        addRowIDs.removeAll { $0 == id }
        newItemTexts.removeValue(forKey: id)

        // Add a fresh row and focus it
        let newID = UUID()
        addRowIDs.append(newID)
        newItemTexts[newID] = ""

        focusAddRowAtEnd(newID)
    }
    
    private func loadItems() {
        if let listItems = list.items as? Set<ShoppingItem> {
            // Sort by creation time (optional, core data standard set is unordered)
            // For now, we will sort alphabetically or keep insertion order based on simple attributes
            allItems = listItems.sorted { ($0.name ?? "") < ($1.name ?? "") }
        } else {
            allItems = []
        }
    }
    
    private func toggleSelection(_ item: ShoppingItem) {
        guard let id = item.id else { return }
        if selectedIDs.wrappedValue.contains(id) {
            selectedIDs.wrappedValue.remove(id)
        } else {
            selectedIDs.wrappedValue.insert(id)
        }
    }

    private func haveItAction(for item: ShoppingItem) -> (() -> Void)? {
        guard let id = item.id, WeekGrocerySync.generatedItemIDs().contains(id) else { return nil }
        return { haveIt(item) }
    }

    private func haveIt(_ item: ShoppingItem) {
        let name = item.name ?? ""
        WeekGrocerySync.addStaple(name)
        if !item.isDeleted {
            dataManager.delete(item)
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            loadItems()
        }
    }

    private func deleteItem(_ item: ShoppingItem, animated: Bool = true) {
        let name = item.name ?? ""
        let qty = item.quantity ?? ""
        let isChecked = item.isChecked

        noteShoppingRemovals([item])
        dataManager.delete(item)
        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                loadItems()
            }
        } else {
            loadItems()
        }
        
        undoStack.register(
            undo: {
                let restored = self.dataManager.addShoppingItem(name: name, quantity: qty, to: self.list)
                restored.isChecked = isChecked
                self.dataManager.save()
                withAnimation { self.loadItems() }
            },
            redo: {
                // Omitting redo deletion for simplicity as new Core Data ID is generated
            }
        )
    }

    private func toggleChecked(_ item: ShoppingItem) {
        withAnimation(.easeInOut(duration: 0.2)) {
            dataManager.toggleShoppingItem(item)
            loadItems()
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
        }
    }

    private func nameBinding(_ item: ShoppingItem) -> Binding<String> {
        Binding(
            get: {
                let raw = item.name ?? ""
                // While the caret is in the row, show exactly what is stored so the cursor does not jump.
                if focusedLine == .item(item.objectID) { return raw }
                return CookingAmount.reformatLine(raw)
            },
            set: { newValue in
                guard !item.isDeleted, item.name != newValue else { return }
                item.name = newValue
                dataManager.save()
            }
        )
    }

    private func beginLine(_ line: ShoppingLine) {
        focusedLine = line
        focusCursorAtEnd = false
    }

    private func itemAbove(_ item: ShoppingItem) -> ShoppingItem? {
        guard let index = allItems.firstIndex(where: { $0.objectID == item.objectID }), index > 0 else {
            return nil
        }
        return allItems[index - 1]
    }

    private func focusItemAtEnd(_ item: ShoppingItem) {
        focusCursorAtEnd = true
        focusedLine = .item(item.objectID)
    }

    private func focusAddRowAtEnd(_ id: UUID) {
        focusCursorAtEnd = true
        focusedLine = .add(id)
    }

    /// Saves the line. An empty name removes the item, the way a blank Notes line disappears.
    private func finishItem(_ item: ShoppingItem) {
        guard !item.isDeleted, item.managedObjectContext != nil else { return }
        let raw = item.name ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if focusedLine == .item(item.objectID) {
                focusedLine = nil
            }
            deleteItem(item, animated: false)
            return
        }
        let formatted = CookingAmount.reformatLine(trimmed)
        if formatted != raw {
            item.name = formatted
            dataManager.save()
        }
        if focusedLine == .item(item.objectID) {
            focusedLine = nil
        }
        // Names are alphabetical. Refresh once the caret has left this row.
        loadItems()
    }

    /// Return keeps the name and moves to the empty add line.
    /// Items have no stored order (the list sorts by name), so a blank row inserted
    /// under this one would jump. The add line at the bottom is the new line.
    private func submitItem(_ item: ShoppingItem) {
        ensureOneAddRow()
        if let addID = addRowIDs.last {
            focusAddRowAtEnd(addID)
        }
        guard !item.isDeleted else { return }
        let raw = item.name ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteItem(item, animated: false)
            return
        }
        let formatted = CookingAmount.reformatLine(trimmed)
        if formatted != raw {
            item.name = formatted
            dataManager.save()
            loadItems()
        }
    }

    private func backspaceItem(_ item: ShoppingItem) {
        if let above = itemAbove(item) {
            focusItemAtEnd(above)
        } else {
            focusedLine = nil
        }
        deleteItem(item, animated: false)
    }

    private func backspaceAddRow(_ id: UUID) {
        if let index = addRowIDs.firstIndex(of: id), index > 0 {
            focusAddRowAtEnd(addRowIDs[index - 1])
            return
        }
        if let last = allItems.last {
            focusItemAtEnd(last)
        }
    }

    private func openDetails(_ item: ShoppingItem) {
        focusedLine = nil
        editingItem = item
    }

    private func endAddRow(_ id: UUID) {
        if focusedLine == .add(id) {
            focusedLine = nil
        }
    }

    @State private var showDeleteSectionConfirm = false

    private var itemCountLabel: String {
        let count = allItems.count
        return "\(count) \(count == 1 ? "ITEM" : "ITEMS")"
    }

    private var sectionIDs: Set<UUID> {
        Set(allItems.compactMap(\.id))
    }

    private var sectionFullySelected: Bool {
        !sectionIDs.isEmpty && sectionIDs.isSubset(of: selectedIDs.wrappedValue)
    }

    private var sectionSelectToggle: some View {
        Button(sectionFullySelected ? "Select none" : "Select all") {
            if sectionFullySelected {
                selectedIDs.wrappedValue.subtract(sectionIDs)
            } else {
                selectedIDs.wrappedValue.formUnion(sectionIDs)
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(quiet ? HomeQuiet.ink : headerColor)
        .buttonStyle(.plain)
    }

    private func quietMoveButton(_ systemName: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(enabled ? HomeQuiet.ink : HomeQuiet.quiet)
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(Circle())
                .overlay(Circle().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private var itemListHeight: CGFloat {
        if itemsHeight > 1 { return itemsHeight }
        let extras = isSelectMode ? 0 : max(addRowIDs.count, 1)
        return CGFloat(max(allItems.count + extras, 1)) * 64
    }

    /// Native rows. The list does not scroll; the Home page (or Shop page) does.
    private var itemList: some View {
        List {
            ForEach(allItems, id: \.objectID) { item in
                if isSelectMode {
                    shoppingEntry(item)
                        .shoppingPlainRow()
                } else {
                    shoppingEntry(item)
                        .shoppingPlainRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteItem(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            if let haveIt = haveItAction(for: item) {
                                Button(action: haveIt) {
                                    Label("Have it", systemImage: "cabinet")
                                }
                                .tint(Color.terra500)
                            }
                        }
                }
            }
            if !isSelectMode {
                ForEach(addRowIDs, id: \.self) { rowID in
                    addField(rowID)
                        .shoppingPlainRow()
                }
            }
        }
        .listStyle(.plain)
        .listRowSpacing(0)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .contentMargins(.vertical, 0, for: .scrollContent)
        .environment(\.defaultMinListRowHeight, 1)
        .frame(height: itemListHeight)
        .background {
            StoreListHeightReader { newValue in
                guard newValue > 1, abs(newValue - itemsHeight) > 0.5 else { return }
                itemsHeight = newValue
            }
        }
    }

    private func shoppingEntry(_ item: ShoppingItem) -> some View {
        VStack(spacing: 0) {
            if isSelectMode {
                ShopListEntryRow(
                    item: item,
                    isChecked: item.isChecked,
                    checkBorder: checkBorder,
                    checkFill: checkFill,
                    accentColor: accentColor,
                    quiet: quiet,
                    isSelecting: true,
                    isSelected: item.id.map { selectedIDs.wrappedValue.contains($0) } ?? false,
                    onToggle: { toggleSelection(item) }
                )
            } else {
                editRow(item)
            }
            if quiet {
                Rectangle()
                    .fill(HomeQuiet.rule)
                    .frame(height: 1)
            } else {
                Divider()
                    .background(dividerColor)
                    .padding(.vertical, 2)
            }
        }
    }

    private func editRow(_ item: ShoppingItem) -> some View {
        let line = ShoppingLine.item(item.objectID)
        return ShopListEntryRow(
            item: item,
            isChecked: item.isChecked,
            checkBorder: checkBorder,
            checkFill: checkFill,
            accentColor: accentColor,
            quiet: quiet,
            onToggle: { toggleChecked(item) },
            name: nameBinding(item),
            isLineFocused: focusedLine == line,
            cursorAtEnd: focusCursorAtEnd && focusedLine == line,
            onLineFocus: { beginLine(line) },
            onLineCommit: { finishItem(item) },
            onLineSubmit: { submitItem(item) },
            onLineBackspace: { backspaceItem(item) },
            onDetails: { openDetails(item) }
        )
    }

    private func addField(_ rowID: UUID) -> some View {
        InlineAddItemRow(
            text: Binding(
                get: { newItemTexts[rowID] ?? "" },
                set: { newItemTexts[rowID] = $0 }
            ),
            checkBorder: checkBorder,
            accentColor: accentColor,
            quiet: quiet,
            isFocused: focusedLine == .add(rowID),
            cursorAtEnd: focusCursorAtEnd && focusedLine == .add(rowID),
            onFocus: { beginLine(.add(rowID)) },
            onCommit: { endAddRow(rowID) },
            onSubmit: { commitRow(rowID) },
            onEmptyBackspace: { backspaceAddRow(rowID) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if isReorderMode {
                if quiet {
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                        Text(storeName)
                            .font(.system(size: 18, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.ink)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        quietMoveButton("chevron.up", enabled: !isFirst, action: onMoveUp)
                        quietMoveButton("chevron.down", enabled: !isLast, action: onMoveDown)
                        Button(action: { showDeleteSectionConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color.terra600)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 4)
                } else {
                // Reorder mode header with move controls
                HStack(spacing: 0) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(headerColor.opacity(0.4))
                        .frame(width: 28)
                        .padding(.trailing, 8)
                    
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(storeName.uppercased())
                            .font(.system(size: 16, weight: .regular, design: .serif))
                            .tracking(0.8)
                    }
                    .foregroundStyle(headerColor)

                    Spacer()
                    
                    // Move up/down buttons
                    HStack(spacing: 6) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isFirst ? headerColor.opacity(0.2) : headerColor)
                                .frame(width: 32, height: 32)
                                .background(isFirst ? accentLight.opacity(0.3) : accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(accentColor.opacity(isFirst ? 0.1 : 0.3), lineWidth: 1)
                                )
                        }
                        .disabled(isFirst)
                        .buttonStyle(.plain)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isLast ? headerColor.opacity(0.2) : headerColor)
                                .frame(width: 32, height: 32)
                                .background(isLast ? accentLight.opacity(0.3) : accentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(accentColor.opacity(isLast ? 0.1 : 0.3), lineWidth: 1)
                                )
                        }
                        .disabled(isLast)
                        .buttonStyle(.plain)
                        
                        Button(action: { showDeleteSectionConfirm = true }) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                                .frame(width: 32, height: 32)
                                .background(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
                }
            } else {
                // Normal mode header — tap the name to expand/collapse.
                // Select controls sit beside it so they are not part of that tap.
                HStack(alignment: .center, spacing: 8) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isExpanded.toggle()
                        }
                    }) {
                        if quiet {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(storeName)
                                    .font(.system(size: 20, weight: .regular, design: .serif))
                                    .foregroundStyle(HomeQuiet.ink)
                                    .lineLimit(1)
                                Text(itemCountLabel)
                                    .font(.system(size: 11, weight: .regular))
                                    .tracking(1.2)
                                    .foregroundStyle(HomeQuiet.quiet)
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: icon)
                                    .font(.system(size: 18, weight: .semibold))
                                Text(storeName.uppercased())
                                    .font(.system(size: 16, weight: .regular, design: .serif))
                                    .tracking(0.8)
                                Text("\(allItems.count) \(allItems.count == 1 ? "Item" : "Items")")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(badgeText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(badgeBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(badgeText.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .foregroundStyle(headerColor)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !isSelectMode {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: quiet ? 12 : 14, weight: quiet ? .regular : .bold))
                                .foregroundStyle(quiet ? HomeQuiet.quiet : headerColor)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else if !sectionIDs.isEmpty {
                        sectionSelectToggle
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .padding(.bottom, isExpanded ? 14 : 0)
            }

            if isExpanded && !isReorderMode {
                itemList
            }
        }
        .padding(quiet ? 16 : 20)
        .modifier(StoreCardChrome(quiet: quiet, borderColor: borderColor, shadowColor: shadowColor))
        .onAppear {
            loadItems()
            ensureOneAddRow()
        }
        .onChange(of: isSelectMode) { _, on in
            if on {
                focusedLine = nil
                isExpanded = true
            }
        }
        .onChange(of: focusedLine) { _, new in
            if new != nil {
                NotificationCenter.default.post(name: .shoppingItemFieldFocused, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            let line = focusedLine
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard focusedLine == line, line != nil, !shoppingTextInputIsFirstResponder() else { return }
                focusedLine = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitDataDidChange"))) { _ in
            loadItems()
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(
                item: item,
                accentColor: accentColor,
                borderColor: borderColor,
                quiet: quiet,
                onSave: { name, quantity in
                    item.name = CookingAmount.reformatLine(name)
                    item.quantity = CookingAmount.reformatLine(quantity)
                    dataManager.save()
                    loadItems()
                },
                onDelete: {
                    noteShoppingRemovals([item])
                    dataManager.delete(item)
                    if let id = item.id {
                        selectedIDs.wrappedValue.remove(id)
                    }
                    loadItems()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Delete Section?", isPresented: $showDeleteSectionConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("\"" + storeName + "\" and all its items will be permanently removed.")
        }
    }
}

/// SwiftUI `List` is a collection view on iOS 16, and a table view on older systems.
/// The page around it is a plain scroll view.
private enum ShoppingScrollSplit {
    static func isListBacking(_ view: UIView) -> Bool {
        view is UICollectionView || view is UITableView
    }

    static func nearestListScroll(from view: UIView) -> UIScrollView? {
        var node: UIView? = view
        for _ in 0..<10 {
            guard let current = node else { return nil }
            if let scroll = firstListScroll(in: current, depth: 8) {
                return scroll
            }
            node = current.superview
        }
        return nil
    }

    static func pageScroll(from view: UIView) -> UIScrollView? {
        var node: UIView? = view.superview
        while let current = node {
            if let scroll = current as? UIScrollView, !isListBacking(current) {
                return scroll
            }
            node = current.superview
        }
        return nil
    }

    private static func firstListScroll(in view: UIView, depth: Int) -> UIScrollView? {
        if isListBacking(view), let scroll = view as? UIScrollView {
            return scroll
        }
        guard depth > 0 else { return nil }
        for subview in view.subviews {
            if let scroll = firstListScroll(in: subview, depth: depth - 1) {
                return scroll
            }
        }
        return nil
    }
}

/// Reads the store list's own scroll view so the surrounding page can scroll.
private struct StoreListHeightReader: UIViewRepresentable {
    var onChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.scheduleSearch(from: uiView)
    }

    final class Coordinator: NSObject {
        var onChange: (CGFloat) -> Void
        private weak var observed: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var waiting = false

        init(onChange: @escaping (CGFloat) -> Void) {
            self.onChange = onChange
        }

        func scheduleSearch(from view: UIView) {
            guard !waiting else { return }
            waiting = true
            search(from: view, attempt: 0)
        }

        func search(from view: UIView, attempt: Int) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                if let view, let scroll = ShoppingScrollSplit.nearestListScroll(from: view) {
                    self.waiting = false
                    self.attach(scroll)
                    return
                }
                guard attempt < 6, let view else {
                    self.waiting = false
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.search(from: view, attempt: attempt + 1)
                }
            }
        }

        func attach(_ scroll: UIScrollView) {
            scroll.layoutIfNeeded()
            scroll.isScrollEnabled = false
            if observed === scroll {
                report(scroll)
                return
            }
            observed = scroll
            observation = scroll.observe(\.contentSize, options: [.initial, .new]) { [weak self] scroll, _ in
                DispatchQueue.main.async {
                    self?.report(scroll)
                }
            }
        }

        func report(_ scroll: UIScrollView) {
            scroll.isScrollEnabled = false
            let height = scroll.contentSize.height
            guard height > 1 else { return }
            onChange(height)
        }
    }
}

/// Lets the page scroll view keep vertical drags and leave sideways swipes to the list.
private struct ParentScrollDirectionLock: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            ShoppingScrollSplit.pageScroll(from: uiView)?.isDirectionalLockEnabled = true
        }
    }
}

private extension View {
    func shoppingPlainRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Notes line field
/// One visible line, like a row in Notes. A drag is not claimed here, so the page scroll
/// view keeps vertical movement and the list keeps swipe-to-delete. Only a tap focuses.
private struct NotesLineStyle: Equatable {
    var quiet: Bool
    var prominent: Bool
    var isChecked: Bool
    var placeholder: String
}

/// Details only. Kept off the text field so UIControl's own context-menu method
/// can still present the system edit menu and the caret loupe.
private final class NotesDetailsMenu: NSObject, UIContextMenuInteractionDelegate {
    var onDetails: (() -> Void)?

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let onDetails else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let details = UIAction(title: "Details", image: UIImage(systemName: "ellipsis.circle")) { _ in
                onDetails()
            }
            return UIMenu(children: [details])
        }
    }
}

private final class NotesUITextField: UITextField {
    var onEmptyBackspace: () -> Void = {}
    var onDetails: (() -> Void)?
    var suppressChange = false
    var blockRefocus = false
    var editGeneration = 0
    var appliedStyle: NotesLineStyle?
    private let detailsDelegate = NotesDetailsMenu()
    private var detailsMenu: UIContextMenuInteraction?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 22)
    }

    override func deleteBackward() {
        let current = text ?? ""
        if current.isEmpty, markedTextRange == nil {
            onEmptyBackspace()
            return
        }
        super.deleteBackward()
    }

    /// Attached only while the row is not editing, so a long-press can open Details
    /// without replacing the field's select, copy, paste, or caret menu.
    func setDetailsMenu(enabled: Bool) {
        detailsDelegate.onDetails = onDetails
        if enabled, onDetails != nil {
            guard detailsMenu == nil else { return }
            let menu = UIContextMenuInteraction(delegate: detailsDelegate)
            detailsMenu = menu
            addInteraction(menu)
        } else if let menu = detailsMenu {
            removeInteraction(menu)
            detailsMenu = nil
        }
    }

    func apply(_ style: NotesLineStyle) {
        guard appliedStyle != style else { return }
        appliedStyle = style
        suppressChange = true
        defer { suppressChange = false }

        let size: CGFloat = style.quiet ? 16 : 14
        let weight: UIFont.Weight = style.quiet ? .regular : (style.prominent ? .bold : .medium)
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let design: UIFontDescriptor.SystemDesign = style.quiet ? .serif : .rounded
        let font = base.fontDescriptor.withDesign(design).map { UIFont(descriptor: $0, size: size) } ?? base
        let color: UIColor
        if style.quiet {
            color = UIColor(red: 0.12, green: 0.11, blue: 0.10, alpha: style.isChecked ? 0.45 : 1)
        } else {
            color = style.isChecked ? .secondaryLabel : .label
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        if style.isChecked {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            attributes[.strikethroughColor] = color
        }
        let selection = selectedTextRange
        let current = text
        defaultTextAttributes = attributes
        self.font = font
        textColor = color
        tintColor = UIColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1)
        typingAttributes = attributes
        text = current
        if style.placeholder.isEmpty {
            attributedPlaceholder = nil
        } else {
            attributedPlaceholder = NSAttributedString(
                string: style.placeholder,
                attributes: [
                    .font: font,
                    .foregroundColor: color.withAlphaComponent(0.45)
                ]
            )
        }
        if let selection {
            selectedTextRange = selection
        }
    }
}

private struct NotesLineField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var quiet: Bool
    var prominent: Bool
    var isChecked: Bool
    var isFocused: Bool
    var focusCursorAtEnd: Bool
    var onFocus: () -> Void
    var onCommit: () -> Void
    var onSubmit: () -> Void
    var onEmptyBackspace: () -> Void
    var showsDetails: Bool
    var onDetails: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NotesUITextField {
        let field = NotesUITextField(frame: .zero)
        field.delegate = context.coordinator
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.returnKeyType = .default
        field.autocorrectionType = .yes
        field.autocapitalizationType = .sentences
        field.clearButtonMode = .never
        field.tintColor = UIColor(red: 0.878, green: 0.478, blue: 0.373, alpha: 1)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: NotesUITextField, context: Context) {
        context.coordinator.parent = self
        field.onEmptyBackspace = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEmptyBackspace()
        }
        if showsDetails {
            field.onDetails = onDetails
        } else {
            field.onDetails = nil
        }
        field.apply(NotesLineStyle(
            quiet: quiet,
            prominent: prominent,
            isChecked: isChecked,
            placeholder: placeholder
        ))
        if !field.isFirstResponder, (field.text ?? "") != text {
            field.suppressChange = true
            field.text = text
            field.suppressChange = false
        }
        let placeAtEnd = focusCursorAtEnd
        if isFocused, !field.isFirstResponder, !field.blockRefocus {
            if field.becomeFirstResponder() {
                if placeAtEnd {
                    let end = field.endOfDocument
                    field.selectedTextRange = field.textRange(from: end, to: end)
                }
            } else {
                context.coordinator.retryFocus(field)
            }
        } else if !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
        field.setDetailsMenu(enabled: showsDetails && !field.isFirstResponder)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NotesUITextField, context: Context) -> CGSize? {
        let proposed = proposal.width ?? 0
        let width = proposed > 1 ? proposed : 280
        let measured = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: max(22, measured.height))
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NotesLineField

        init(_ parent: NotesLineField) {
            self.parent = parent
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            guard let field = textField as? NotesUITextField else { return }
            field.editGeneration += 1
            field.blockRefocus = false
            parent.onFocus()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard let field = textField as? NotesUITextField else { return }
            let generation = field.editGeneration
            field.blockRefocus = true
            let commit = parent.onCommit
            DispatchQueue.main.async { [weak field] in
                if let field, field.editGeneration != generation { return }
                commit()
                if field?.editGeneration == generation {
                    field?.blockRefocus = false
                }
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }

        func textFieldDidChangeSelection(_ textField: UITextField) {
            guard let field = textField as? NotesUITextField, field.isFirstResponder, !field.suppressChange else { return }
            let value = field.text ?? ""
            guard parent.text != value else { return }
            parent.text = value
        }

        func retryFocus(_ field: NotesUITextField) {
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.parent.isFocused, !field.isFirstResponder, !field.blockRefocus else { return }
                let placeAtEnd = self.parent.focusCursorAtEnd
                if field.becomeFirstResponder(), placeAtEnd {
                    let end = field.endOfDocument
                    field.selectedTextRange = field.textRange(from: end, to: end)
                }
            }
        }
    }
}

// MARK: - Inline Add Item Row
struct InlineAddItemRow: View {
    @Binding var text: String
    let checkBorder: Color
    let accentColor: Color
    var quiet: Bool = false
    let isFocused: Bool
    var cursorAtEnd: Bool = false
    let onFocus: () -> Void
    var onCommit: () -> Void = {}
    let onSubmit: () -> Void
    var onEmptyBackspace: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .stroke(quiet ? HomeQuiet.ink.opacity(0.22) : checkBorder.opacity(0.4), lineWidth: quiet ? 1 : 1.5)
                .frame(width: 18, height: 18)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(quiet ? HomeQuiet.quiet : checkBorder.opacity(0.5))
                )

            NotesLineField(
                text: $text,
                placeholder: "Add item...",
                quiet: quiet,
                prominent: false,
                isChecked: false,
                isFocused: isFocused,
                focusCursorAtEnd: cursorAtEnd,
                onFocus: onFocus,
                onCommit: onCommit,
                onSubmit: onSubmit,
                onEmptyBackspace: onEmptyBackspace,
                showsDetails: false,
                onDetails: {}
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .opacity(text.isEmpty && !isFocused ? 0.5 : 1.0)
    }
}

private struct RenameFieldShadow: ViewModifier {
    var quiet: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if quiet {
            content
        } else {
            content.boldShadow(.black, size: 3, radius: 10)
        }
    }
}

private struct RenameControlShadow: ViewModifier {
    var quiet: Bool
    var size: CGFloat = 3

    @ViewBuilder
    func body(content: Content) -> some View {
        if quiet {
            content
        } else {
            content.boldShadow(.black, size: size, radius: 12)
        }
    }
}

private struct StoreCardChrome: ViewModifier {
    var quiet: Bool
    var borderColor: Color
    var shadowColor: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if quiet {
            content.homeQuietCard()
        } else {
            content
                .background(Color.cardWhite)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(borderColor, lineWidth: 1)
                )
                .boldShadow(shadowColor)
        }
    }
}

// MARK: - Edit Item Sheet
struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ShoppingItem
    let accentColor: Color
    let borderColor: Color
    var quiet: Bool = false
    let onSave: (String, String) -> Void
    let onDelete: () -> Void

    @State private var editName: String = ""
    @State private var editQuantity: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quiet ? "Edit item" : "Edit Item")
                        .font(quiet ? .system(size: 22, weight: .regular, design: .serif) : .system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                    Text("UPDATE DETAILS")
                        .font(.system(size: 10, weight: quiet ? .regular : .bold, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    if quiet {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(accentColor)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            // Item name field
            VStack(alignment: .leading, spacing: 8) {
                Text("ITEM NAME")
                    .font(.system(size: 10, weight: quiet ? .regular : .heavy, design: quiet ? .default : .rounded))
                    .tracking(1)
                    .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))

                TextField("Item name", text: $editName)
                    .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 16, weight: .bold, design: .rounded))
                    .padding(16)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(quiet ? HomeQuiet.buttonStroke : Color.gray.opacity(0.2), lineWidth: quiet ? 1 : 2)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Quantity field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QUANTITY")
                        .font(.system(size: 10, weight: quiet ? .regular : .heavy, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                    Spacer()
                    Text("OPTIONAL")
                        .font(.system(size: 9, weight: quiet ? .regular : .bold, design: quiet ? .default : .rounded))
                        .tracking(0.5)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.3))
                }

                HStack {
                    TextField("e.g. 5 tomatoes, 2 lbs...", text: $editQuantity)
                        .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 16, weight: .bold, design: .rounded))

                    if !editQuantity.isEmpty {
                        Button(action: { editQuantity = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.gray.opacity(0.4))
                        }
                    }
                }
                .padding(16)
                .background(Color.cardWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(quiet ? HomeQuiet.buttonStroke : Color.gray.opacity(0.2), lineWidth: quiet ? 1 : 2)
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                Button(action: {
                    let cleanName = editName.trimmingCharacters(in: .whitespaces)
                    let cleanQty = editQuantity.trimmingCharacters(in: .whitespaces)
                    onSave(cleanName, cleanQty)
                    dismiss()
                }) {
                    if quiet {
                        Text("Save")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(editName.isEmpty ? HomeQuiet.quiet : Color.terra500)
                            .clipShape(Capsule())
                    } else {
                        Text("SAVE CHANGES")
                            .font(.system(size: 14, weight: .regular))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(editName.isEmpty ? Color.gray.opacity(0.3) : accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.black.opacity(0.2), lineWidth: 1)
                            )
                            .boldShadow(editName.isEmpty ? Color.gray.opacity(0.2) : borderColor, size: 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(editName.isEmpty)

                // Delete button
                Button(action: { showDeleteConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                        Text("DELETE ITEM")
                            .font(.system(size: 12, weight: .regular))
                            .tracking(0.5)
                    }
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
        .onAppear {
            editName = CookingAmount.reformatLine(item.name ?? "")
            editQuantity = CookingAmount.reformatLine(item.quantity ?? "")
        }
        .alert("Delete Item?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("\"\(item.name ?? "Item")\" will be removed from the list.")
        }
    }
}

// MARK: - Shopping Item Row
struct ShopListEntryRow: View {
    @ObservedObject var item: ShoppingItem
    let isChecked: Bool
    let checkBorder: Color
    let checkFill: Color
    let accentColor: Color
    var quiet: Bool = false
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onToggle: () -> Void
    var name: Binding<String> = .constant("")
    var isLineFocused: Bool = false
    var cursorAtEnd: Bool = false
    var onLineFocus: () -> Void = {}
    var onLineCommit: () -> Void = {}
    var onLineSubmit: () -> Void = {}
    var onLineBackspace: () -> Void = {}
    var onDetails: () -> Void = {}

    var body: some View {
        Group {
            if isSelecting {
                Button(action: onToggle) {
                    HStack(spacing: 12) {
                        markCircle(
                            filled: isSelected,
                            ring: quiet ? HomeQuiet.ink.opacity(0.28) : checkBorder,
                            fill: Color.terra500
                        )
                        titleBlock
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    Button(action: onToggle) {
                        markCircle(
                            filled: isChecked,
                            ring: quiet ? HomeQuiet.ink.opacity(0.28) : checkBorder,
                            fill: quiet ? Color.terra500 : checkFill
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize()
                    .layoutPriority(1)

                    VStack(alignment: .leading, spacing: 2) {
                        NotesLineField(
                            text: name,
                            placeholder: "",
                            quiet: quiet,
                            prominent: !quiet,
                            isChecked: isChecked,
                            isFocused: isLineFocused,
                            focusCursorAtEnd: cursorAtEnd,
                            onFocus: onLineFocus,
                            onCommit: onLineCommit,
                            onSubmit: onLineSubmit,
                            onEmptyBackspace: onLineBackspace,
                            showsDetails: true,
                            onDetails: onDetails
                        )
                        quantityLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, quiet ? 8 : 4)
        .frame(minHeight: 32)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CookingAmount.reformatLine(item.name ?? "Unknown"))
                .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(quiet ? (isChecked ? HomeQuiet.quiet : HomeQuiet.ink) : (isChecked ? Color.gray.opacity(0.5) : Color.primary))
                .strikethrough(isChecked, color: quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                .multilineTextAlignment(.leading)

            quantityText
        }
    }

    @ViewBuilder
    private var quantityLine: some View {
        if item.quantity?.isEmpty == false {
            quantityText
                .contextMenu {
                    Button("Details", systemImage: "ellipsis.circle", action: onDetails)
                }
        }
    }

    @ViewBuilder
    private var quantityText: some View {
        if let quantity = item.quantity, !quantity.isEmpty {
            Text(CookingAmount.reformatLine(quantity))
                .font(quiet ? .system(size: 12, weight: .regular) : .system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(quiet ? HomeQuiet.quiet : (isChecked ? Color.gray.opacity(0.3) : Color.gray))
                .strikethrough(isChecked, color: quiet ? HomeQuiet.quiet : Color.gray.opacity(0.3))
        }
    }

    /// Stroke sits inside the disk, with a point of padding, so the circle is not clipped.
    private func markCircle(filled: Bool, ring: Color, fill: Color) -> some View {
        ZStack {
            Circle()
                .strokeBorder(filled ? fill : ring, lineWidth: quiet ? 1 : 2)
                .background {
                    Circle().fill(filled ? fill : Color.clear)
                }
            if filled {
                Image(systemName: "checkmark")
                    .font(.system(size: quiet ? 9 : 12, weight: quiet ? .regular : .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 18, height: 18)
        .padding(1)
        .fixedSize()
        .layoutPriority(1)
    }
}

// MARK: - Pantry staples
private struct PantryStaplesSheet: View {
    @State private var names: [String] = []
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pantry staples")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(names, id: \.self) { name in
                        HStack(spacing: 12) {
                            Text(name)
                                .font(.system(size: 17, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                WeekGrocerySync.removeStaple(name)
                                reload()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .regular))
                                    .foregroundStyle(HomeQuiet.quiet)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(name)")
                        }
                        .padding(.leading, 24)
                        .padding(.trailing, 8)
                        Rectangle()
                            .fill(HomeQuiet.rule)
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add", text: $draft)
                    .font(.system(size: 16, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .submitLabel(.done)
                    .onSubmit(commitDraft)
                if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: commitDraft) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(Color.terra500)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgBase)
        .onAppear(perform: reload)
    }

    private func reload() {
        names = WeekGrocerySync.stapleNames()
    }

    private func commitDraft() {
        let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        WeekGrocerySync.addStaple(name)
        draft = ""
        reload()
    }
}

// MARK: - Move to section
private struct MoveToSectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sections: [ShoppingList]
    let selectedItems: [ShoppingItem]
    let onMove: (ShoppingList) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Move to section")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(sections.filter { !holdsAll($0) }, id: \.objectID) { list in
                        Button {
                            onMove(list)
                            dismiss()
                        } label: {
                            Text(list.name ?? "Section")
                                .font(.system(size: 17, weight: .regular, design: .serif))
                                .foregroundStyle(HomeQuiet.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle()
                            .fill(HomeQuiet.rule)
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.bgBase)
    }

    private func holdsAll(_ list: ShoppingList) -> Bool {
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { $0.list?.objectID == list.objectID }
    }
}

// MARK: - Bulk delete confirm
private struct QuietDeleteConfirm: View {
    let count: Int
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Text(count == 1 ? "Delete item" : "Delete \(count) items")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 36)
                .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(HomeQuiet.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(HomeQuiet.buttonStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Text("Delete")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgBase)
    }
}

// MARK: - Sort Options Modal
struct SortOptionsModal: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSort: SortOption = .byStore

    enum SortOption: String, CaseIterable {
        case byStore = "By Store"
        case alphabetical = "Alphabetical"
        case byCategory = "By Category"
        case recentlyAdded = "Recently Added"

        var icon: String {
            switch self {
            case .byStore: return "storefront"
            case .alphabetical: return "textformat.abc"
            case .byCategory: return "tag"
            case .recentlyAdded: return "clock"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sort Items")
                        .font(.system(size: 22, weight: .regular, design: .serif))
                    Text("CHOOSE SORT ORDER")
                        .font(.system(size: 10, weight: .regular))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.03, green: 0.45, blue: 0.70))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Sort options
            VStack(spacing: 10) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSort = option
                        }
                    }) {
                        HStack(spacing: 14) {
                            Image(systemName: option.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 24)
                            Text(option.rawValue)
                                .font(.system(size: 15, weight: .regular))
                            Spacer()
                            if selectedSort == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(red: 0.03, green: 0.45, blue: 0.70))
                            } else {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .foregroundStyle(selectedSort == option ? Color(red: 0.03, green: 0.45, blue: 0.70) : .primary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 16)
                        .background(
                            selectedSort == option ? Color.sky100 : Color.cardWhite
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(selectedSort == option ? Color.sky400 : Color.gray.opacity(0.15), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Done button
            Button(action: { dismiss() }) {
                Text("APPLY SORT")
                    .font(.system(size: 14, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.03, green: 0.45, blue: 0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .boldShadow(Color.sky400, size: 4)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
    }
}

// MARK: - Add Section Modal
struct AddSectionModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    var onAdd: () -> Void = {}
    var quiet: Bool = false
    @State private var sectionName = ""
    @State private var selectedColor: Color = .lime500

    private let colorOptions: [(name: String, color: Color, border: Color)] = [
        ("Green", Color.lime500, Color(red: 0.40, green: 0.64, blue: 0.05)),
        ("Blue", Color.sky400, Color(red: 0.01, green: 0.52, blue: 0.78)),
        ("Orange", Color.terra500, Color.terra600),
        ("Purple", Color.lilac500, Color.lilac600),
        ("Peach", Color.peach500, Color.terra600),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quiet ? "Add section" : "Add Section")
                        .font(quiet ? .system(size: 22, weight: .regular, design: .serif) : .system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                    Text("NEW STORE OR CATEGORY")
                        .font(.system(size: 10, weight: quiet ? .regular : .bold, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    if quiet {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(red: 0.26, green: 0.53, blue: 0.09))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            // Section name text field
            VStack(alignment: .leading, spacing: 8) {
                Text("SECTION NAME")
                    .font(.system(size: 10, weight: quiet ? .regular : .heavy, design: quiet ? .default : .rounded))
                    .tracking(1)
                    .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))

                TextField("e.g. Whole Foods, Target...", text: $sectionName)
                    .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 16, weight: .bold, design: .rounded))
                    .padding(16)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(quiet ? HomeQuiet.buttonStroke : Color.gray.opacity(0.2), lineWidth: quiet ? 1 : 2)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            if !quiet {
            // Color picker
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCENT COLOR")
                    .font(.system(size: 10, weight: .regular))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))

                HStack(spacing: 14) {
                    ForEach(colorOptions, id: \.name) { option in
                        Button(action: { selectedColor = option.color }) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(option.border, lineWidth: 1)
                                )
                                .overlay {
                                    if selectedColor == option.color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .scaleEffect(selectedColor == option.color ? 1.15 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: {
                let name = sectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                _ = dataManager.createShoppingList(name: name)
                onAdd()
                dismiss()
            }) {
                if quiet {
                    Text("Add section")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(sectionName.isEmpty ? HomeQuiet.quiet : Color.terra500)
                        .clipShape(Capsule())
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                        Text("ADD SECTION")
                            .font(.system(size: 14, weight: .regular))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        sectionName.isEmpty
                            ? Color.gray.opacity(0.3)
                            : Color(red: 0.26, green: 0.53, blue: 0.09)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .boldShadow(
                        sectionName.isEmpty ? Color.gray.opacity(0.2) : Color.lime500,
                        size: 4
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(sectionName.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
    }
}

// MARK: - Section rename tap-away
/// Resigns the section-name field when the edit sheet is tapped outside that field.
/// Touches still reach Save, so the button can commit in the same turn.
private struct SectionRenameTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.scheduleInstall(from: uiView)
    }

    final class Coordinator: NSObject {
        private weak var installedOn: UIScrollView?
        private var waitingToInstall = false
        private let tapName = "ourweek.sectionRenameDismiss"

        func scheduleInstall(from view: UIView) {
            guard installedOn == nil, !waitingToInstall else { return }
            waitingToInstall = true
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self else { return }
                self.waitingToInstall = false
                guard let view, self.installedOn == nil else { return }
                self.install(from: view)
            }
        }

        func install(from view: UIView) {
            var current: UIView? = view
            var scroll: UIScrollView?
            while let candidate = current {
                if let found = candidate as? UIScrollView {
                    scroll = found
                    break
                }
                current = candidate.superview
            }
            guard let scroll, installedOn == nil else { return }
            if scroll.gestureRecognizers?.contains(where: { $0.name == tapName }) == true {
                installedOn = scroll
                return
            }
            let tap = UITapGestureRecognizer(
                target: SectionRenameTapRelay.shared,
                action: #selector(SectionRenameTapRelay.handleTap)
            )
            tap.name = tapName
            tap.cancelsTouchesInView = false
            tap.delegate = SectionRenameTapRelay.shared
            scroll.addGestureRecognizer(tap)
            installedOn = scroll
        }
    }
}

private final class SectionRenameTapRelay: NSObject, UIGestureRecognizerDelegate {
    static let shared = SectionRenameTapRelay()

    @objc func handleTap() {
        KeyboardDismiss.resign()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Edit List Modal
struct EditListModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @Binding var shoppingLists: [ShoppingList]
    var onListsChanged: () -> Void = {}
    var quiet: Bool = false
    @State private var showDeleteConfirm = false
    @State private var checkedDeleted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quiet ? "Edit list" : "Edit List")
                        .font(quiet ? .system(size: 22, weight: .regular, design: .serif) : .system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                    Text("MANAGE YOUR ITEMS")
                        .font(.system(size: 10, weight: quiet ? .regular : .bold, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    if quiet {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.terra600)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Edit actions
                    VStack(spacing: 10) {
                        Button(action: {
                            // Delete all checked items across all lists
                            var checked: [ShoppingItem] = []
                            for list in shoppingLists {
                                if let items = list.items as? Set<ShoppingItem> {
                                    checked.append(contentsOf: items.filter(\.isChecked))
                                }
                            }
                            noteShoppingRemovals(checked)
                            dataManager.deleteShoppingItems(checked)
                            checkedDeleted = true
                            NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
                            onListsChanged()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                checkedDeleted = false
                            }
                        }) {
                            EditActionRow(
                                icon: checkedDeleted ? "checkmark.circle.fill" : "trash",
                                title: checkedDeleted ? "Checked Items Removed!" : "Delete Checked Items",
                                subtitle: checkedDeleted ? "All completed items have been removed" : "Remove all completed items from every section",
                                accentColor: checkedDeleted ? Color.lime500 : Color.terra500,
                                quiet: quiet
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: { showDeleteConfirm = true }) {
                            EditActionRow(
                                icon: "xmark.circle",
                                title: "Clear All Sections",
                                subtitle: "Remove all items from every section — can't be undone",
                                accentColor: Color(red: 0.85, green: 0.20, blue: 0.20),
                                quiet: quiet
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, 8)

                    // Sections Editor
                    ForEach(shoppingLists, id: \.objectID) { list in
                        EditSectionCard(list: list, onListsChanged: onListsChanged, quiet: quiet)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .background(SectionRenameTapInstaller())
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(Color.bgBase)
        .alert("Clear All Sections?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                var doomed: [ShoppingItem] = []
                for list in shoppingLists {
                    if let items = list.items as? Set<ShoppingItem> {
                        doomed.append(contentsOf: items)
                    }
                }
                noteShoppingRemovals(doomed)
                dataManager.deleteShoppingItems(doomed)
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
                onListsChanged()
                dismiss()
            }
        } message: {
            Text("This will remove all items from every shopping list section. This action can't be undone.")
        }
    }
}

// MARK: - Edit Section Card
struct EditSectionCard: View {
    @ObservedObject var list: ShoppingList
    @Environment(DataManager.self) private var dataManager
    var onListsChanged: () -> Void = {}
    var quiet: Bool = false

    @State private var editName: String = ""
    @State private var isRenaming = false
    @State private var commitInFlight = false
    @FocusState private var nameFieldFocused: Bool
    @State private var showClearConfirm = false

    private var storedName: String { list.name ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header: rename commits only from Save or the keyboard Done key.
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SECTION NAME")
                        .font(.system(size: 10, weight: quiet ? .regular : .heavy, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))

                    if isRenaming {
                        TextField("Store or Section", text: $editName)
                            .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 16, weight: .bold, design: .rounded))
                            .padding(12)
                            .background(Color.cardWhite)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(quiet ? HomeQuiet.buttonStroke : Color.black, lineWidth: quiet ? 1 : 2)
                            )
                            .modifier(RenameFieldShadow(quiet: quiet))
                            .focused($nameFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(commitRename)

                        HStack(spacing: 10) {
                            Button(action: commitRename) {
                                Text(quiet ? "Save" : "SAVE")
                                    .font(quiet ? .system(size: 15, weight: .regular) : .system(size: 14, weight: .heavy, design: .rounded))
                                    .tracking(quiet ? 0 : 0.8)
                                    .foregroundStyle(quiet ? Color.white : Color.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(quiet ? Color.terra500 : Color.lime400)
                                    .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: quiet ? 22 : 12)
                                            .stroke(quiet ? Color.clear : Color.black, lineWidth: quiet ? 0 : 2)
                                    )
                                    .modifier(RenameControlShadow(quiet: quiet))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Save section name")

                            Button(action: cancelRename) {
                                Text(quiet ? "Cancel" : "CANCEL")
                                    .font(quiet ? .system(size: 15, weight: .regular) : .system(size: 14, weight: .heavy, design: .rounded))
                                    .tracking(quiet ? 0 : 0.8)
                                    .foregroundStyle(quiet ? HomeQuiet.ink : Color.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: quiet ? 22 : 12)
                                            .stroke(quiet ? HomeQuiet.buttonStroke : Color.black, lineWidth: quiet ? 1 : 2)
                                    )
                                    .modifier(RenameControlShadow(quiet: quiet))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Cancel rename")
                        }
                    } else {
                        HStack(spacing: 10) {
                            Text(storedName.isEmpty ? "Store or Section" : storedName)
                                .font(quiet ? .system(size: 18, weight: .regular, design: .serif) : .system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: beginRename) {
                                Text(quiet ? "Rename" : "RENAME")
                                    .font(quiet ? .system(size: 14, weight: .regular) : .system(size: 12, weight: .heavy, design: .rounded))
                                    .tracking(quiet ? 0 : 0.6)
                                    .foregroundStyle(quiet ? HomeQuiet.ink : Color.black)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(quiet ? Color.white : Color.lime100)
                                    .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: quiet ? 22 : 10)
                                            .stroke(quiet ? HomeQuiet.buttonStroke : Color.black, lineWidth: quiet ? 1 : 2)
                                    )
                                    .modifier(RenameControlShadow(quiet: quiet, size: 2))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rename section")
                        }
                    }
                }

                if !isRenaming {
                    Button(action: { showClearConfirm = true }) {
                        if quiet {
                            Image(systemName: "trash")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.terra600)
                                .frame(width: 36, height: 36)
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14, weight: .bold))
                                Text("CLEAR")
                                    .font(.system(size: 9, weight: .regular))
                            }
                            .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear section")
                }
            }
            
            // List of items
            if let items = list.items as? Set<ShoppingItem>, !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items).sorted { ($0.name ?? "") < ($1.name ?? "") }, id: \.objectID) { item in
                        EditItemRow(item: item, quiet: quiet)
                        if item != Array(items).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }).last {
                            Divider().background(Color.gray.opacity(0.1))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            } else {
                Text("No items in this section.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.gray.opacity(0.5))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous)
                .stroke(quiet ? HomeQuiet.cardStroke : Color.gray.opacity(0.12), lineWidth: quiet ? 1 : 2)
        )
        .onAppear {
            if !isRenaming {
                editName = storedName
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            guard !focused, isRenaming else { return }
            // Save and Done run in the same turn as the field resigning. Wait
            // so a tap on Save still commits, while a tap away reverts.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                guard isRenaming, !commitInFlight else { return }
                cancelRename()
            }
        }
        .alert("Clear Section?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                let doomed = Array((list.items as? Set<ShoppingItem>) ?? [])
                noteShoppingRemovals(doomed)
                dataManager.deleteShoppingItems(doomed)
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
                onListsChanged()
            }
        } message: {
            Text("This will remove all items from \(list.name ?? "this section"). Cannot be undone.")
        }
    }

    private func beginRename() {
        editName = storedName
        isRenaming = true
        DispatchQueue.main.async {
            nameFieldFocused = true
        }
    }

    private func commitRename() {
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        commitInFlight = true
        isRenaming = false
        nameFieldFocused = false
        KeyboardDismiss.resign()

        guard !trimmed.isEmpty else {
            editName = storedName
            commitInFlight = false
            return
        }

        if trimmed != storedName {
            list.name = trimmed
            dataManager.save()
            NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
            onListsChanged()
        }
        editName = list.name ?? trimmed
        commitInFlight = false
    }

    private func cancelRename() {
        editName = storedName
        isRenaming = false
        nameFieldFocused = false
        KeyboardDismiss.resign()
    }
}

// MARK: - Edit Item Row
struct EditItemRow: View {
    @ObservedObject var item: ShoppingItem
    var quiet: Bool = false
    @Environment(DataManager.self) private var dataManager
    
    var body: some View {
        HStack {
            TextField("Item name", text: Binding(
                get: { item.name ?? "" },
                set: {
                    item.name = $0
                    dataManager.save()
                }
            ))
            .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 14, weight: .semibold, design: .rounded))
            
            Spacer()
            
            Button(action: {
                noteShoppingRemovals([item])
                dataManager.delete(item)
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.gray.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.white)
    }
}

struct EditActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let accentColor: Color
    var quiet: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: quiet ? 16 : 20, weight: quiet ? .regular : .semibold))
                .foregroundStyle(quiet ? HomeQuiet.ink : accentColor)
                .frame(width: 40, height: 40)
                .background(quiet ? HomeQuiet.rule : accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(quiet ? .system(size: 16, weight: .regular, design: .serif) : .system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                Text(subtitle)
                    .font(.system(size: 12, weight: quiet ? .regular : .medium, design: quiet ? .default : .rounded))
                    .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: quiet ? .regular : .bold))
                .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.3))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous)
                .stroke(quiet ? HomeQuiet.cardStroke : Color.gray.opacity(0.12), lineWidth: quiet ? 1 : 2)
        )
    }
}

// MARK: - Sync Modal
struct SyncModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    var quiet: Bool = false
    @State private var isSyncing = false
    @State private var syncComplete = false
    @AppStorage("autoSync") private var autoSync = true
    @AppStorage("syncRecipes") private var syncRecipes = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sync")
                        .font(quiet ? .system(size: 22, weight: .regular, design: .serif) : .system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                    Text("MEAL PLAN INTEGRATION")
                        .font(.system(size: 10, weight: quiet ? .regular : .bold, design: quiet ? .default : .rounded))
                        .tracking(1)
                        .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    if quiet {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.lilac600)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Sync status card
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(quiet ? HomeQuiet.rule : (syncComplete ? Color.lime100 : Color.lilac100))
                        .frame(width: 64, height: 64)

                    if isSyncing {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(quiet ? Color.terra500 : Color.lilac600)
                    } else {
                        Image(systemName: syncComplete ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 28, weight: quiet ? .regular : .bold))
                            .foregroundStyle(quiet ? (syncComplete ? Color.terra500 : HomeQuiet.ink) : (syncComplete ? Color.lime500 : Color.lilac600))
                    }
                }

                Text(isSyncing ? "Syncing..." : (syncComplete ? "All Synced!" : "Ready to Sync"))
                    .font(quiet ? .system(size: 18, weight: .regular, design: .serif) : .system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)

                Text("Last synced: Today, 2:30 PM")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.gray.opacity(0.5))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: quiet ? 22 : 16, style: .continuous)
                    .stroke(quiet ? HomeQuiet.cardStroke : Color.lilac200, lineWidth: quiet ? 1 : 2)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Toggle options
            VStack(spacing: 10) {
                SyncToggleRow(icon: "clock.arrow.2.circlepath", title: "Auto-Sync",
                              subtitle: "Sync when meal plan changes", isOn: $autoSync, quiet: quiet)
                SyncToggleRow(icon: "book", title: "Include Recipes",
                              subtitle: "Add recipe ingredients automatically", isOn: $syncRecipes, quiet: quiet)
            }
            .padding(.horizontal, 24)

            Spacer()

            // Sync button
            Button(action: {
                isSyncing = true
                syncComplete = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dataManager.syncMealPlanToShoppingList(syncRecipes: syncRecipes)
                    // Trigger ui update across sections
                    NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
                    withAnimation {
                        isSyncing = false
                        syncComplete = true
                    }
                }
            }) {
                if quiet {
                    Text(isSyncing ? "Syncing" : "Sync now")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .bold))
                        Text("SYNC NOW")
                            .font(.system(size: 14, weight: .regular))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Color.terra500
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.2), lineWidth: 1)
                    )
                    .boldShadow(Color.lilac400, size: 4)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSyncing)
            .opacity(isSyncing ? 0.6 : 1.0)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
    }
}

struct SyncToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var quiet: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: quiet ? .regular : .semibold))
                .foregroundStyle(quiet ? HomeQuiet.ink : Color.lilac600)
                .frame(width: 36, height: 36)
                .background(quiet ? HomeQuiet.rule : Color.lilac100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(quiet ? .system(size: 15, weight: .regular, design: .serif) : .system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(quiet ? HomeQuiet.ink : Color.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: quiet ? .regular : .medium, design: quiet ? .default : .rounded))
                    .foregroundStyle(quiet ? HomeQuiet.quiet : Color.gray.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(quiet ? Color.terra500 : Color.lilac500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: quiet ? 22 : 14, style: .continuous)
                .stroke(quiet ? HomeQuiet.cardStroke : Color.gray.opacity(0.12), lineWidth: quiet ? 1 : 2)
        )
    }
}

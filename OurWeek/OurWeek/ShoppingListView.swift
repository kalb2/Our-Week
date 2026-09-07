import SwiftUI
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

// MARK: - Shopping List View
struct ShoppingListView: View {
    @Binding var showSharingSettings: Bool
    @Environment(DataManager.self) private var dataManager
    @State private var undoStack = ShoppingUndoStack()
    
    // Core data query 
    @State private var shoppingLists: [ShoppingList] = []
    
    // Section reorder state
    @State private var isReorderMode = false
    @State private var draggedSectionID: NSManagedObjectID?
    
    // Sync modal state
    @State private var showSyncModal = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ShoppingListHeader(showSharingSettings: $showSharingSettings)
                MealPlanCarousel()
                    .padding(.top, 16)
                ShoppingToolbar(
                    undoStack: undoStack,
                    isReorderMode: $isReorderMode,
                    showSyncModal: $showSyncModal,
                    shoppingLists: $shoppingLists,
                    onListsChanged: { loadLists() }
                )
                    .padding(.top, 12)

                // Reorder mode banner
                if isReorderMode {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.up.arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Drag sections or use arrows to reorder")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Spacer()
                        Button("Done") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isReorderMode = false
                            }
                        }
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.sky400, lineWidth: 1.5))
                    }
                    .foregroundStyle(Color(red: 0.03, green: 0.45, blue: 0.70))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.sky100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sky200, lineWidth: 1.5)
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Store sections
                VStack(spacing: 20) {
                    if shoppingLists.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cart.badge.plus")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.terra400)
                            Text("No Shopping Lists Yet")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                            Text("Use the Add Section button above to create a store list.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 40)
                        .frame(maxWidth: .infinity)
                    } else {
                        ForEach(Array(shoppingLists.enumerated()), id: \.element.objectID) { index, list in
                            StoreSection(
                                list: list,
                                storeName: list.name ?? "Unknown Store",
                                icon: getIcon(for: list.name ?? ""),
                                accentColor: getAccentColor(for: list.name ?? ""),
                                accentLight: getAccentLight(for: list.name ?? ""),
                                borderColor: getAccentColor(for: list.name ?? ""),
                                shadowColor: getAccentColor(for: list.name ?? ""),
                                badgeBg: getAccentLight(for: list.name ?? ""),
                                badgeText: getDarkerColor(for: list.name ?? ""),
                                checkBorder: getAccentLight(for: list.name ?? "").opacity(0.8),
                                checkFill: getAccentColor(for: list.name ?? ""),
                                dividerColor: getAccentLight(for: list.name ?? ""),
                                headerColor: getDarkerColor(for: list.name ?? ""),
                                undoStack: undoStack,
                                isReorderMode: isReorderMode,
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
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        dataManager.deleteShoppingList(list)
                                        loadLists()
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Sync with Meal Plan CTA
                Button(action: { showSyncModal = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18, weight: .bold))
                        Text("SYNC WITH MEAL PLAN")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.terra400, Color.terra500],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.terra600, lineWidth: 2)
                    )
                    .boldShadow(Color.terra600, size: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .background(Color.bgBase)
        .onAppear {
            loadLists()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitDataDidChange"))) { _ in
            loadLists()
        }
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
    
    private func loadLists() {
        shoppingLists = dataManager.fetchShoppingLists()
        
        // Auto-create defaults if completely empty (e.g., first install)
        if shoppingLists.isEmpty {
            _ = dataManager.createShoppingList(name: "Grocery Store")
            _ = dataManager.createShoppingList(name: "Costco")
            _ = dataManager.createShoppingList(name: "Trader Joe's")
            
            // Re-fetch after creation
            shoppingLists = dataManager.fetchShoppingLists()
        }
    }
    
    // MARK: - Color/Icon Helpers for dynamically generated lists
    private func getIcon(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("grocery") || n.contains("smith") { return "storefront" }
        if n.contains("costco") || n.contains("sams") { return "tag" }
        if n.contains("trader") || n.contains("sprouts") { return "basket" }
        if n.contains("walmart") || n.contains("target") { return "cart" }
        return "list.bullet.clipboard"
    }

    private func getAccentColor(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("grocery") { return Color.lime500 }
        if n.contains("costco") { return Color.sky400 }
        if n.contains("trader") { return Color.terra500 }
        if n.contains("walmart") { return Color.lilac500 }
        return Color.peach500
    }

    private func getAccentLight(for name: String) -> Color {
        let n = name.lowercased()
        if n.contains("grocery") { return Color.lime100 }
        if n.contains("costco") { return Color.sky100 }
        if n.contains("trader") { return Color.terra100 }
        if n.contains("walmart") { return Color.lilac100 }
        return Color.orange.opacity(0.1)
    }

    private func getDarkerColor(for name: String) -> Color {
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
                Text("Shopping")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .tracking(-0.5)
                Text("List")
                    .font(.system(size: 36, weight: .heavy, design: .rounded))
                    .italic()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.peach500, Color.terra500],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("GROUPED BY STORE")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))
                    .padding(.top, 4)
            }
            Spacer()
            // Profile avatar button
            Button(action: { showProfileMenu = true }) {
                AvatarButton(imageData: profileImageData)
            }
            .buttonStyle(.plain)
            .shadow(color: .black.opacity(0.15), radius: 0, x: 4, y: 4)
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

// MARK: - Toolbar
struct ShoppingToolbar: View {
    var undoStack: ShoppingUndoStack
    @Binding var isReorderMode: Bool
    @Binding var showSyncModal: Bool
    @Binding var shoppingLists: [ShoppingList]
    var onListsChanged: () -> Void
    @State private var showAddSectionModal = false
    @State private var showEditModal = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ActionPill(icon: "arrow.up.arrow.down", label: isReorderMode ? "Done" : "Reorder",
                           bg: isReorderMode ? Color.sky400 : Color.sky100,
                           border: isReorderMode ? Color(red: 0.03, green: 0.45, blue: 0.70) : Color.sky200,
                           foreground: isReorderMode ? .white : Color(red: 0.03, green: 0.45, blue: 0.70),
                           action: {
                               withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                   isReorderMode.toggle()
                               }
                           })

                ActionPill(icon: "plus.circle", label: "Add Section",
                           bg: Color.lime100, border: Color(red: 0.85, green: 0.98, blue: 0.62),
                           foreground: Color(red: 0.26, green: 0.53, blue: 0.09),
                           action: { showAddSectionModal = true })

                ActionPill(icon: "pencil", label: "Edit",
                           bg: Color(red: 1.0, green: 0.90, blue: 0.88),
                           border: Color(red: 1.0, green: 0.82, blue: 0.75),
                           foreground: Color.terra600,
                           action: { showEditModal = true })

                ActionPill(icon: "arrow.triangle.2.circlepath", label: "Sync",
                           bg: Color.lilac100, border: Color.lilac200,
                           foreground: Color.lilac600,
                           action: { showSyncModal = true })

                ActionPill(icon: "arrow.uturn.backward", label: "Undo",
                           bg: undoStack.canUndo ? Color.sky100 : Color(red: 0.95, green: 0.95, blue: 0.95),
                           border: undoStack.canUndo ? Color.sky200 : Color(red: 0.90, green: 0.90, blue: 0.90),
                           foreground: undoStack.canUndo ? Color(red: 0.03, green: 0.45, blue: 0.70) : Color(red: 0.40, green: 0.40, blue: 0.40).opacity(0.4),
                           action: { undoStack.undo() })

                ActionPill(icon: "arrow.uturn.forward", label: "Redo",
                           bg: undoStack.canRedo ? Color.sky100 : Color(red: 0.95, green: 0.95, blue: 0.95),
                           border: undoStack.canRedo ? Color.sky200 : Color(red: 0.90, green: 0.90, blue: 0.90),
                           foreground: undoStack.canRedo ? Color(red: 0.03, green: 0.45, blue: 0.70) : Color(red: 0.40, green: 0.40, blue: 0.40).opacity(0.4),
                           action: { undoStack.redo() })
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
        }
        .sheet(isPresented: $showAddSectionModal) {
            AddSectionModal(onAdd: onListsChanged)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showEditModal) {
            EditListModal(shoppingLists: $shoppingLists, onListsChanged: onListsChanged)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSyncModal) {
            SyncModal()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Action Pill Button
struct ActionPill: View {
    let icon: String
    let label: String
    let bg: Color
    let border: Color
    let foreground: Color
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(bg)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(border, lineWidth: 1)
            )
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
    var undoStack: ShoppingUndoStack
    var isReorderMode: Bool = false
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
    @FocusState private var focusedAddRowID: UUID?
    @State private var editingItem: ShoppingItem?

    // Drag reorder state
    @State private var draggedItemID: NSManagedObjectID?
    @State private var dragOffset: CGFloat = 0

    private func ensureOneAddRow() {
        if addRowIDs.isEmpty {
            let id = UUID()
            addRowIDs.append(id)
            newItemTexts[id] = ""
        }
    }

    private func commitRow(_ id: UUID) {
        let text = (newItemTexts[id] ?? "").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        // Core Data creation
        let newItem = dataManager.addShoppingItem(name: text, quantity: "", to: list)
        
        withAnimation(.easeInOut(duration: 0.2)) {
            allItems.append(newItem)
        }

        // Register undo/redo
        undoStack.register(
            undo: { 
                self.dataManager.delete(newItem)
                withAnimation { self.loadItems() } 
            },
            redo: { 
                _ = self.dataManager.addShoppingItem(name: text, quantity: "", to: self.list)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedAddRowID = newID
        }
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
    
    private func deleteItem(_ item: ShoppingItem) {
        let name = item.name ?? ""
        let qty = item.quantity ?? ""
        let isChecked = item.isChecked
        
        dataManager.delete(item)
        withAnimation(.easeInOut(duration: 0.2)) {
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
    
    private func moveItem(_ item: ShoppingItem, dragOffset: CGFloat) {
        guard let fromIndex = allItems.firstIndex(where: { $0.objectID == item.objectID }) else { return }
        let rowHeight: CGFloat = 50
        let moveBy = Int(round(dragOffset / rowHeight))
        let toIndex = max(0, min(allItems.count - 1, fromIndex + moveBy))

        if toIndex != fromIndex {
            withAnimation(.easeInOut(duration: 0.2)) {
                let moved = allItems.remove(at: fromIndex)
                allItems.insert(moved, at: toIndex)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @State private var showDeleteSectionConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            if isReorderMode {
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
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
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
            } else {
                // Normal mode header — tap to expand/collapse
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                            Text(storeName.uppercased())
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .tracking(0.8)
                        }
                        .foregroundStyle(headerColor)

                        Spacer()

                        // Item count badge
                        Text("\(allItems.count) \(allItems.count == 1 ? "Item" : "Items")")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(badgeText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(badgeBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(badgeText.opacity(0.2), lineWidth: 1)
                            )
                            
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(headerColor)
                            .padding(.leading, 8)
                    }
                }
                .buttonStyle(.plain)
                .padding(.bottom, isExpanded ? 14 : 0)
            }

            if isExpanded && !isReorderMode {
                // Existing items
                ForEach(allItems, id: \.objectID) { item in
                    VStack(spacing: 0) {
                        SwipeToDeleteRow(
                            onDelete: { deleteItem(item) },
                            accentColor: accentColor
                        ) {
                            ShopListEntryRow(
                                item: item,
                                isChecked: item.isChecked,
                                checkBorder: checkBorder,
                                checkFill: checkFill,
                                accentColor: accentColor,
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        dataManager.toggleShoppingItem(item)
                                        loadItems()
                                    }
                                },
                                onTap: {
                                    editingItem = item
                                }
                            )
                        }

                        Divider()
                            .background(dividerColor)
                            .padding(.vertical, 2)
                    }
                    // Drag reorder — item follows finger, reorder on drop
                    .offset(y: draggedItemID == item.objectID ? dragOffset : 0)
                    .zIndex(draggedItemID == item.objectID ? 100 : 0)
                    .scaleEffect(draggedItemID == item.objectID ? 1.03 : 1)
                    .shadow(
                        color: draggedItemID == item.objectID ? .black.opacity(0.1) : .clear,
                        radius: 4, y: 2
                    )
                    .gesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .sequenced(before: DragGesture())
                            .onChanged { value in
                                switch value {
                                case .second(true, let drag):
                                    if let drag = drag {
                                        if draggedItemID == nil {
                                            draggedItemID = item.objectID
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        }
                                        dragOffset = drag.translation.height
                                    }
                                default: break
                                }
                            }
                            .onEnded { _ in
                                moveItem(item, dragOffset: dragOffset)
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    dragOffset = 0
                                    draggedItemID = nil
                                }
                            }
                    )
                }

                // Inline add-item rows
                ForEach(addRowIDs, id: \.self) { rowID in
                    InlineAddItemRow(
                        text: Binding(
                            get: { newItemTexts[rowID] ?? "" },
                            set: { newItemTexts[rowID] = $0 }
                        ),
                        checkBorder: checkBorder,
                        accentColor: accentColor,
                        isFocused: focusedAddRowID == rowID,
                        onFocus: { focusedAddRowID = rowID },
                        onSubmit: { commitRow(rowID) }
                    )
                    .focused($focusedAddRowID, equals: rowID)
                }
            }
        }
        .padding(20)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(borderColor, lineWidth: 2)
        )
        .boldShadow(shadowColor)
        .onAppear {
            loadItems()
            ensureOneAddRow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CloudKitDataDidChange"))) { _ in
            loadItems()
        }
        .sheet(item: $editingItem) { item in
            EditItemSheet(
                item: item,
                accentColor: accentColor,
                borderColor: borderColor,
                onSave: { name, quantity in
                    item.name = name
                    item.quantity = quantity
                    dataManager.save()
                    loadItems()
                },
                onDelete: { 
                    dataManager.delete(item)
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

// MARK: - Swipe To Delete Row
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var showDeleteButton = false
    private let deleteThreshold: CGFloat = -70
    private let fullSwipeThreshold: CGFloat = -180

    var body: some View {
        ZStack(alignment: .trailing) {
            // Red delete background
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        onDelete()
                        offset = 0
                        showDeleteButton = false
                    }
                }) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 60)
                        .frame(maxHeight: .infinity)
                        .background(Color(red: 0.90, green: 0.22, blue: 0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .opacity(offset < -10 ? 1 : 0)

            // Content
            content()
                .background(Color.cardWhite)
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let translation = value.translation.width
                            // Only allow left swipe
                            if translation < 0 {
                                offset = translation * 0.7  // dampened
                            } else if showDeleteButton {
                                offset = deleteThreshold + translation * 0.3
                            } else {
                                offset = translation * 0.1
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if offset < fullSwipeThreshold {
                                    // Full swipe — delete immediately
                                    offset = -500
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        onDelete()
                                        offset = 0
                                        showDeleteButton = false
                                    }
                                } else if offset < deleteThreshold {
                                    // Partial swipe — reveal button
                                    offset = deleteThreshold
                                    showDeleteButton = true
                                } else {
                                    // Not enough — snap back
                                    offset = 0
                                    showDeleteButton = false
                                }
                            }
                        }
                )
                .onTapGesture {
                    if showDeleteButton {
                        withAnimation(.spring(response: 0.3)) {
                            offset = 0
                            showDeleteButton = false
                        }
                    }
                }
        }
        .clipped()
    }
}

// MARK: - Inline Add Item Row
struct InlineAddItemRow: View {
    @Binding var text: String
    let checkBorder: Color
    let accentColor: Color
    let isFocused: Bool
    let onFocus: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Empty circle (unchecked style)
            Circle()
                .stroke(checkBorder.opacity(0.4), lineWidth: 1.5)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(checkBorder.opacity(0.5))
                )

            TextField("Add item...", text: $text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .submitLabel(.return)
                .onSubmit(onSubmit)
                .onTapGesture { onFocus() }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 32)
        .opacity(text.isEmpty && !isFocused ? 0.5 : 1.0)
    }
}

// MARK: - Edit Item Sheet
struct EditItemSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ShoppingItem
    let accentColor: Color
    let borderColor: Color
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
                    Text("Edit Item")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("UPDATE DETAILS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(accentColor)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            // Item name field
            VStack(alignment: .leading, spacing: 8) {
                Text("ITEM NAME")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))

                TextField("Item name", text: $editName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(16)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            // Quantity field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("QUANTITY")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                    Spacer()
                    Text("OPTIONAL")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.5)
                        .foregroundStyle(.gray.opacity(0.3))
                }

                HStack {
                    TextField("e.g. 5 tomatoes, 2 lbs...", text: $editQuantity)
                        .font(.system(size: 16, weight: .bold, design: .rounded))

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
                        .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                // Save button
                Button(action: {
                    let cleanName = editName.trimmingCharacters(in: .whitespaces)
                    let cleanQty = editQuantity.trimmingCharacters(in: .whitespaces)
                    onSave(cleanName, cleanQty)
                    dismiss()
                }) {
                    Text("SAVE CHANGES")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(editName.isEmpty ? Color.gray.opacity(0.3) : accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.black.opacity(0.2), lineWidth: 2)
                        )
                        .boldShadow(editName.isEmpty ? Color.gray.opacity(0.2) : borderColor, size: 4)
                }
                .disabled(editName.isEmpty)

                // Delete button
                Button(action: { showDeleteConfirm = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .semibold))
                        Text("DELETE ITEM")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
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
            editName = item.name ?? ""
            editQuantity = item.quantity ?? ""
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
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Circular checkbox
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(isChecked ? checkFill : checkBorder, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if isChecked {
                        Circle()
                            .fill(checkFill)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            // Tappable item content
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unknown")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(isChecked ? .gray.opacity(0.5) : .primary)
                        .strikethrough(isChecked, color: .gray.opacity(0.5))
                    
                    if let quantity = item.quantity, !quantity.isEmpty {
                        Text(quantity)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isChecked ? .gray.opacity(0.3) : .gray)
                            .strikethrough(isChecked, color: .gray.opacity(0.3))
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Edit icon hint
            Button(action: onTap) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.gray.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 32)
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
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("CHOOSE SORT ORDER")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
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
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
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
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Spacer()
                            if selectedSort == option {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color(red: 0.03, green: 0.45, blue: 0.70))
                            } else {
                                Circle()
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
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
                                .stroke(selectedSort == option ? Color.sky400 : Color.gray.opacity(0.15), lineWidth: 2)
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
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.03, green: 0.45, blue: 0.70))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.black.opacity(0.2), lineWidth: 2)
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
                    Text("Add Section")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("NEW STORE OR CATEGORY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(red: 0.26, green: 0.53, blue: 0.09))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)

            // Section name text field
            VStack(alignment: .leading, spacing: 8) {
                Text("SECTION NAME")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))

                TextField("e.g. Whole Foods, Target...", text: $sectionName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(16)
                    .background(Color.cardWhite)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                    )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            // Color picker
            VStack(alignment: .leading, spacing: 12) {
                Text("ACCENT COLOR")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray.opacity(0.5))

                HStack(spacing: 14) {
                    ForEach(colorOptions, id: \.name) { option in
                        Button(action: { selectedColor = option.color }) {
                            Circle()
                                .fill(option.color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle().stroke(option.border, lineWidth: 2)
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

            Spacer()

            // Add button
            Button(action: {
                let name = sectionName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                _ = dataManager.createShoppingList(name: name)
                onAdd()
                dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                    Text("ADD SECTION")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
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
                        .stroke(Color.black.opacity(0.2), lineWidth: 2)
                )
                .boldShadow(
                    sectionName.isEmpty ? Color.gray.opacity(0.2) : Color.lime500,
                    size: 4
                )
            }
            .disabled(sectionName.isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.bgBase)
    }
}

// MARK: - Edit List Modal
struct EditListModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
    @Binding var shoppingLists: [ShoppingList]
    var onListsChanged: () -> Void = {}
    @State private var showDeleteConfirm = false
    @State private var checkedDeleted = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Edit List")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("MANAGE YOUR ITEMS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.terra600)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
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
                            for list in shoppingLists {
                                if let items = list.items as? Set<ShoppingItem> {
                                    for item in items where item.isChecked {
                                        dataManager.delete(item)
                                    }
                                }
                            }
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
                                accentColor: checkedDeleted ? Color.lime500 : Color.terra500
                            )
                        }
                        .buttonStyle(.plain)

                        Button(action: { showDeleteConfirm = true }) {
                            EditActionRow(
                                icon: "xmark.circle",
                                title: "Clear All Sections",
                                subtitle: "Remove all items from every section — can't be undone",
                                accentColor: Color(red: 0.85, green: 0.20, blue: 0.20)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, 8)

                    // Sections Editor
                    ForEach(shoppingLists, id: \.objectID) { list in
                        EditSectionCard(list: list, onListsChanged: onListsChanged)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Color.bgBase)
        .alert("Clear All Sections?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                for list in shoppingLists {
                    if let items = list.items as? Set<ShoppingItem> {
                        for item in items {
                            dataManager.delete(item)
                        }
                    }
                }
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

    @State private var editName: String = ""
    @State private var showClearConfirm = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header: Edit name and clear button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SECTION NAME")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                    
                    TextField("Store or Section", text: $editName)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .padding(12)
                        .background(Color.bgBase)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .onChange(of: editName) { _, newValue in
                            list.name = newValue
                            dataManager.save()
                            onListsChanged()
                        }
                }
                
                Spacer()
                
                Button(action: { showClearConfirm = true }) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 14, weight: .bold))
                        Text("CLEAR")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color(red: 0.85, green: 0.20, blue: 0.20))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.85, green: 0.20, blue: 0.20).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            // List of items
            if let items = list.items as? Set<ShoppingItem>, !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items).sorted { ($0.name ?? "") < ($1.name ?? "") }, id: \.objectID) { item in
                        EditItemRow(item: item)
                        if item != Array(items).sorted(by: { ($0.name ?? "") < ($1.name ?? "") }).last {
                            Divider().background(Color.gray.opacity(0.1))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.1), lineWidth: 1))
            } else {
                Text("No items in this section.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.5))
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.12), lineWidth: 2))
        .onAppear {
            editName = list.name ?? ""
        }
        .alert("Clear Section?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                if let items = list.items as? Set<ShoppingItem> {
                    for item in items {
                        dataManager.delete(item)
                    }
                }
                dataManager.save()
                NotificationCenter.default.post(name: NSNotification.Name("CloudKitDataDidChange"), object: nil)
                onListsChanged()
            }
        } message: {
            Text("This will remove all items from \(list.name ?? "this section"). Cannot be undone.")
        }
    }
}

// MARK: - Edit Item Row
struct EditItemRow: View {
    @ObservedObject var item: ShoppingItem
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
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            
            Spacer()
            
            Button(action: {
                dataManager.delete(item)
                dataManager.save()
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 40, height: 40)
                .background(accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.6))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.gray.opacity(0.3))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.12), lineWidth: 2)
        )
    }
}

// MARK: - Sync Modal
struct SyncModal: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager
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
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("MEAL PLAN INTEGRATION")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.lilac600)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            // Sync status card
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(syncComplete ? Color.lime100 : Color.lilac100)
                        .frame(width: 64, height: 64)

                    if isSyncing {
                        ProgressView()
                            .scaleEffect(1.3)
                            .tint(Color.lilac600)
                    } else {
                        Image(systemName: syncComplete ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(syncComplete ? Color.lime500 : Color.lilac600)
                    }
                }

                Text(isSyncing ? "Syncing..." : (syncComplete ? "All Synced!" : "Ready to Sync"))
                    .font(.system(size: 16, weight: .heavy, design: .rounded))

                Text("Last synced: Today, 2:30 PM")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.5))
                    .tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.lilac200, lineWidth: 2)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Toggle options
            VStack(spacing: 10) {
                SyncToggleRow(icon: "clock.arrow.2.circlepath", title: "Auto-Sync",
                              subtitle: "Sync when meal plan changes", isOn: $autoSync)
                SyncToggleRow(icon: "book", title: "Include Recipes",
                              subtitle: "Add recipe ingredients automatically", isOn: $syncRecipes)
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
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .bold))
                    Text("SYNC NOW")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.lilac500, Color.lilac600],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.black.opacity(0.2), lineWidth: 2)
                )
                .boldShadow(Color.lilac400, size: 4)
            }
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

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.lilac600)
                .frame(width: 36, height: 36)
                .background(Color.lilac100)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.5))
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.lilac500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.gray.opacity(0.12), lineWidth: 2)
        )
    }
}

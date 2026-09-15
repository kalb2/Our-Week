import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreData

// MARK: - Recipe Library View (Meals Tab Main)

struct RecipeLibraryView: View {
    @Binding var showSharingSettings: Bool
    @Environment(DataManager.self) private var dataManager

    @State private var recipes: [Recipe] = []
    @State private var searchText: String = ""
    @State private var selectedSort: DataManager.RecipeSortOption = .recentlyAdded
    @State private var showFilterSheet = false
    @State private var showAddRecipe = false
    @State private var selectedRecipe: Recipe?
    @State private var filterCategory: String? = nil
    @State private var filterDifficulty: String? = nil
    @State private var filterFavoritesOnly = false

    // URL Import
    @State private var showURLImport = false
    @State private var scrapedRecipe: ScrapedRecipe?
    @State private var previewRecipe: ScrapedRecipe?

    // Paste Import
    @State private var showPasteImport = false
    @State private var pastedRecipe: ScrapedRecipe?

    // Recipe pack (JSON) import
    @State private var showPackFilePicker = false
    @State private var loadedPack: LoadedRecipePack?
    @State private var packLoadError: String?

    @State private var showProfileMenu = false

    // Bulk select
    @State private var isSelectMode = false
    @State private var selectedRecipeIDs: Set<NSManagedObjectID> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkCategories = false
    @State private var showBulkTags = false

    @AppStorage("profileImageData") private var profileImageData: Data?

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                recipeHeader

                // Search Bar
                searchBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                // Sort & Filter Toolbar
                filterToolbar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)

                // Content
                if recipes.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(recipes, id: \.objectID) { recipe in
                            RecipeCard(
                                recipe: recipe,
                                onTap: {
                                    if isSelectMode {
                                        toggleSelection(recipe)
                                    } else {
                                        selectedRecipe = recipe
                                    }
                                },
                                onFavoriteToggle: {
                                    dataManager.toggleRecipeFavorite(recipe)
                                    loadRecipes()
                                },
                                onDelete: {
                                    dataManager.deleteRecipe(recipe)
                                    loadRecipes()
                                },
                                isSelectMode: isSelectMode,
                                isSelected: selectedRecipeIDs.contains(recipe.objectID)
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 120)
            }
        }
        .background(Color.bgBase)
        .onAppear { loadRecipes() }
        .sheet(isPresented: $showAddRecipe, onDismiss: { loadRecipes() }) {
            AddRecipeView(recipe: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedRecipe, onDismiss: { loadRecipes() }) { recipe in
            RecipeDetailView(recipe: recipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFilterSheet) {
            filterSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: searchText) { _, _ in loadRecipes() }
        .onChange(of: selectedSort) { _, _ in loadRecipes() }
        .sheet(isPresented: $showURLImport, onDismiss: {
            // Present preview sheet AFTER import sheet fully dismisses to avoid blank screen
            if let recipe = scrapedRecipe {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    previewRecipe = recipe
                    scrapedRecipe = nil // reset for next import
                }
            }
        }) {
            URLImportView(scrapedRecipe: $scrapedRecipe, showPreview: .constant(false))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPasteImport, onDismiss: {
            // Present preview sheet AFTER paste sheet fully dismisses
            if let recipe = pastedRecipe {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    previewRecipe = recipe
                    pastedRecipe = nil
                }
            }
        }) {
            PasteImportView(scrapedRecipe: $pastedRecipe)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .background(
            EmptyView()
                .sheet(item: $previewRecipe, onDismiss: { loadRecipes() }) { recipe in
                    ImportPreviewView(scrapedRecipe: recipe)
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                }
        )
        .sheet(isPresented: $showProfileMenu) {
            ProfileMenuSheet(
                onSharingTapped: { showSharingSettings = true }
            )
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showPackFilePicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handlePickedPackFile(result)
        }
        .sheet(item: $loadedPack, onDismiss: { loadRecipes() }) { pack in
            RecipePackImportView(loaded: pack)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert("Couldn't Import Pack", isPresented: Binding(
            get: { packLoadError != nil },
            set: { if !$0 { packLoadError = nil } }
        )) {
            Button("OK", role: .cancel) { packLoadError = nil }
        } message: {
            Text(packLoadError ?? "")
        }
        .alert(
            selectedRecipeIDs.count == 1
                ? "Delete 1 recipe?"
                : "Delete \(selectedRecipeIDs.count) recipes?",
            isPresented: $showBulkDeleteConfirm
        ) {
            Button("Delete", role: .destructive) { performBulkDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selectedRecipeIDs.count == 1
                 ? "This recipe will be permanently deleted."
                 : "These recipes will be permanently deleted.")
        }
        .sheet(isPresented: $showBulkCategories) {
            BulkCategoriesSheet(
                recipeCount: selectedRecipeIDs.count,
                initialCategories: sharedCategoriesAmongSelection(),
                onApply: { performBulkSetCategories($0) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBulkTags) {
            BulkTagsSheet(
                recipeCount: selectedRecipeIDs.count,
                onReplace: { performBulkReplaceTags($0) },
                onAdd: { performBulkAddTags($0) }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectMode {
                bulkActionBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 88)
                    .background(Color.bgBase.opacity(0.96))
            }
        }
        .onAppear { consumeIncomingPackIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: RecipePackOpenHandler.notification)) { _ in
            consumeIncomingPackIfNeeded()
        }
    }

    // MARK: - Header

    private var recipeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let hh = dataManager.currentHousehold, dataManager.persistenceController.isShared(object: hh) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.sky500)
                        
                    }
                    Text("Recipes")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .tracking(-0.5)
                }
                Text(isSelectMode
                     ? "\(selectedRecipeIDs.count) SELECTED"
                     : "\(recipes.count) IN YOUR LIBRARY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(isSelectMode ? Color.terra500 : .gray.opacity(0.5))
                    .padding(.top, 4)
            }
            Spacer()

            if isSelectMode {
                Button(action: exitSelectMode) {
                    Text("Done")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                }
                .buttonStyle(.plain)
            } else {
                // Add button menu
                Menu {
                    Button(action: { showAddRecipe = true }) {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }
                    Button(action: { showURLImport = true }) {
                        Label("Import from URL", systemImage: "link")
                    }
                    Button(action: { showPasteImport = true }) {
                        Label("Paste Recipe Text", systemImage: "doc.on.clipboard.fill")
                    }
                    Button(action: { showPackFilePicker = true }) {
                        Label("Import Recipe Pack", systemImage: "square.stack.3d.up.fill")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 44, height: 44)
                            .offset(x: 3, y: 3)

                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.terra400, Color.peach500],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Color.black, lineWidth: 2))

                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            // Profile avatar
            Button(action: { showProfileMenu = true }) {
                AvatarButton(imageData: profileImageData)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.terra400)

            TextField("Search recipes...", text: $searchText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.cardWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(Color.terra300, size: 3, radius: 14)
    }

    // MARK: - Filter Toolbar

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            // Filter button
            Button(action: { showFilterSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12, weight: .bold))
                    Text("Filter")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(hasActiveFilters ? .white : Color.terra600)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(hasActiveFilters ? Color.terra500 : Color.terra100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(hasActiveFilters ? Color.terra600 : Color.terra200, lineWidth: 1.5))
            }
            .buttonStyle(.plain)

            if isSelectMode {
                Button(action: selectAllVisible) {
                    Text(allVisibleSelected ? "Deselect All" : "Select All")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.terra600)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.terra100)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.terra200, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(recipes.isEmpty)
            } else {
                Button(action: enterSelectMode) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12, weight: .bold))
                        Text("Select")
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(Color.terra600)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.terra100)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(recipes.isEmpty)
            }

            Spacer()

            // Sort picker
            Menu {
                ForEach(DataManager.RecipeSortOption.allCases, id: \.self) { option in
                    Button(action: { selectedSort = option }) {
                        HStack {
                            Text(option.rawValue)
                            if selectedSort == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .bold))
                    Text(selectedSort.rawValue)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Color.terra600)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.terra100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.terra200, lineWidth: 1.5))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            // Food emoji circle
            ZStack {
                Circle()
                    .fill(Color.terra100)
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(Color.terra200, lineWidth: 2))

                Text("🍳")
                    .font(.system(size: 48))
            }

            VStack(spacing: 8) {
                if !searchText.isEmpty || hasActiveFilters {
                    Text("No recipes found")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("Try adjusting your search or filters")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.6))
                } else {
                    Text("Your recipe library")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                    Text("is waiting to be filled!")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.terra500)

                    Text("Add your first recipe and start building\nyour family cookbook")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }

            if searchText.isEmpty && !hasActiveFilters {
                Button(action: { showAddRecipe = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                        Text("ADD YOUR FIRST RECIPE")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.terra400, Color.peach500],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                    .shadow(color: Color.terra500.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Filter Sheet

    private var filterSheet: some View {
        VStack(spacing: 24) {
            Text("FILTER RECIPES")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(Color.terra500)
                .padding(.top, 8)

            // Category filter
            VStack(alignment: .leading, spacing: 12) {
                Text("CATEGORY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray)

                let categoryOptions = RecipeConstants.categories
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All", isSelected: filterCategory == nil) {
                            filterCategory = nil
                        }
                        ForEach(categoryOptions, id: \.self) { cat in
                            filterChip(cat, isSelected: filterCategory == cat) {
                                filterCategory = filterCategory == cat ? nil : cat
                            }
                        }
                    }
                }
            }

            // Difficulty filter
            VStack(alignment: .leading, spacing: 12) {
                Text("DIFFICULTY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.gray)

                HStack(spacing: 8) {
                    filterChip("All", isSelected: filterDifficulty == nil) {
                        filterDifficulty = nil
                    }
                    ForEach(RecipeConstants.difficulties, id: \.self) { diff in
                        filterChip(diff, isSelected: filterDifficulty == diff) {
                            filterDifficulty = filterDifficulty == diff ? nil : diff
                        }
                    }
                }
            }

            // Favorites toggle
            Toggle(isOn: $filterFavoritesOnly) {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Color.terra500)
                    Text("Favorites Only")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .tint(Color.terra500)

            Spacer()

            // Apply / Reset
            HStack(spacing: 12) {
                Button(action: {
                    filterCategory = nil
                    filterDifficulty = nil
                    filterFavoritesOnly = false
                    loadRecipes()
                    showFilterSheet = false
                }) {
                    Text("RESET")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)

                Button(action: {
                    loadRecipes()
                    showFilterSheet = false
                }) {
                    Text("APPLY")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.terra500)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.terra600, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isSelected ? .white : Color.terra600)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Color.terra500 : Color.terra100)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.terra600 : Color.terra200, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bulk Action Bar

    private var bulkActionBar: some View {
        let hasSelection = !selectedRecipeIDs.isEmpty
        return HStack(spacing: 10) {
            Button(action: { showBulkDeleteConfirm = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                    Text("Delete")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(hasSelection ? .white : .gray.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasSelection ? Color.red.opacity(0.85) : Color.gray.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(hasSelection ? Color.black : Color.gray.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)

            Button(action: { showBulkCategories = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .bold))
                    Text("Categories")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(hasSelection ? Color.terra600 : .gray.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasSelection ? Color.terra100 : Color.gray.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(hasSelection ? Color.terra200 : Color.gray.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)

            Button(action: { showBulkTags = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "tag")
                        .font(.system(size: 12, weight: .bold))
                    Text("Tags")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(hasSelection ? Color.sky500 : .gray.opacity(0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasSelection ? Color.sky100 : Color.gray.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(hasSelection ? Color.sky200 : Color.gray.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .disabled(!hasSelection)
        }
    }

    // MARK: - Helpers

    private var hasActiveFilters: Bool {
        filterCategory != nil || filterDifficulty != nil || filterFavoritesOnly
    }

    private var allVisibleSelected: Bool {
        !recipes.isEmpty && recipes.allSatisfy { selectedRecipeIDs.contains($0.objectID) }
    }

    private var selectedRecipes: [Recipe] {
        recipes.filter { selectedRecipeIDs.contains($0.objectID) }
    }

    private func loadRecipes() {
        recipes = dataManager.fetchRecipes(
            searchText: searchText,
            categories: filterCategory,
            difficulty: filterDifficulty,
            favoritesOnly: filterFavoritesOnly,
            sortBy: selectedSort
        )
        let visibleIDs = Set(recipes.map(\.objectID))
        selectedRecipeIDs.formIntersection(visibleIDs)
    }

    private func enterSelectMode() {
        isSelectMode = true
        selectedRecipeIDs.removeAll()
    }

    private func exitSelectMode() {
        isSelectMode = false
        selectedRecipeIDs.removeAll()
    }

    private func toggleSelection(_ recipe: Recipe) {
        if selectedRecipeIDs.contains(recipe.objectID) {
            selectedRecipeIDs.remove(recipe.objectID)
        } else {
            selectedRecipeIDs.insert(recipe.objectID)
        }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func selectAllVisible() {
        if allVisibleSelected {
            selectedRecipeIDs.removeAll()
        } else {
            selectedRecipeIDs = Set(recipes.map(\.objectID))
        }
    }

    private func sharedCategoriesAmongSelection() -> Set<String> {
        let selected = selectedRecipes
        guard let first = selected.first else { return [] }
        let firstSet = RecipeLabelFormatting.decodeCategories(first.categories)
        let allMatch = selected.allSatisfy {
            RecipeLabelFormatting.decodeCategories($0.categories) == firstSet
        }
        return allMatch ? firstSet : []
    }

    private func performBulkDelete() {
        let targets = selectedRecipes
        guard !targets.isEmpty else { return }
        dataManager.deleteRecipes(targets)
        loadRecipes()
        exitSelectMode()
    }

    private func performBulkSetCategories(_ categories: Set<String>) {
        let targets = selectedRecipes
        guard !targets.isEmpty else { return }
        dataManager.setRecipesCategories(targets, categories: RecipeLabelFormatting.encodeCategories(categories))
        loadRecipes()
        exitSelectMode()
    }

    private func performBulkReplaceTags(_ raw: String) {
        let targets = selectedRecipes
        guard !targets.isEmpty else { return }
        dataManager.setRecipesTags(targets, tags: RecipeLabelFormatting.encodeTags(raw))
        loadRecipes()
        exitSelectMode()
    }

    private func performBulkAddTags(_ raw: String) {
        let targets = selectedRecipes
        guard !targets.isEmpty else { return }
        dataManager.addTagsToRecipes(targets, tags: raw)
        loadRecipes()
        exitSelectMode()
    }

    // MARK: - Recipe Pack File

    private func consumeIncomingPackIfNeeded() {
        if let url = RecipePackOpenHandler.consumePendingURL() {
            loadPack(from: url)
        }
    }

    private func handlePickedPackFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            loadPack(from: url)
        case .failure(let error):
            if isUserCancellation(error) { return }
            packLoadError = error.localizedDescription
        }
    }

    private func isUserCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func loadPack(from url: URL) {
        do {
            let pack = try RecipePackParser.parse(url: url)
            let loaded = LoadedRecipePack(pack: pack, fileName: url.lastPathComponent)
            // Wait for the document picker (or any other sheet) to finish dismissing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                loadedPack = loaded
            }
        } catch {
            packLoadError = error.localizedDescription
        }
    }
}

// MARK: - Recipe Constants

struct RecipeConstants {
    static let categories = ["Breakfast", "Lunch", "Dinner", "Dessert", "Snack", "Side", "Appetizer", "Drink"]
    static let difficulties = ["Easy", "Medium", "Hard"]
    static let units = ["", "tsp", "tbsp", "cup", "oz", "lb", "g", "kg", "ml", "L", "pinch", "dash", "whole", "slice", "clove", "can", "pkg"]

    static let categoryEmojis: [String: String] = [
        "Breakfast": "🥞", "Lunch": "🥗", "Dinner": "🍝",
        "Dessert": "🍰", "Snack": "🍎", "Side": "🥦",
        "Appetizer": "🧆", "Drink": "🥤"
    ]

    static let foodEmojis = ["🍳", "🥘", "🍲", "🌮", "🍕", "🥙", "🍜", "🥗", "🍝", "🧁", "🥞", "🍔", "🌯", "🥩", "🍱"]
}

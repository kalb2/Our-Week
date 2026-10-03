import SwiftUI

// MARK: - Recipe Card

struct RecipeCard: View {
    let recipe: Recipe
    let onTap: () -> Void
    let onFavoriteToggle: () -> Void
    var onDelete: (() -> Void)? = nil
    var isSelectMode: Bool = false
    var isSelected: Bool = false

    @State private var showDeleteConfirm = false

    private var totalTime: Int16 { recipe.prepTime + recipe.cookTime }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.terra500 : Color.white)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(isSelected ? Color.clear : HomeQuiet.buttonStroke, lineWidth: 1))

            Image(systemName: isSelected ? "checkmark" : "circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(isSelected ? .white : HomeQuiet.quiet)
        }
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image / Placeholder
                ZStack(alignment: .topTrailing) {
                    // A clear frame owns the layout. scaledToFill images would
                    // otherwise expand the button's hit target over the toolbar.
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .overlay {
                            if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color(red: 0.98, green: 0.96, blue: 0.94)
                                .overlay(
                                    Image(systemName: "fork.knife")
                                        .font(.system(size: 22, weight: .regular))
                                        .foregroundStyle(HomeQuiet.quiet)
                                )
                            }
                        }
                        .clipped()
                        .contentShape(Rectangle())

                    if isSelectMode {
                        selectionBadge
                            .padding(8)
                    } else {
                        // Favorite star
                        Button(action: onFavoriteToggle) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(HomeQuiet.cardStroke, lineWidth: 1))

                                Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(recipe.isFavorite ? Color.terra600 : HomeQuiet.quiet)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }

                // Info section
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name ?? "Untitled")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .lineLimit(2)
                        .foregroundStyle(HomeQuiet.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if totalTime > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9, weight: .regular))
                                Text("\(totalTime) min")
                                    .font(.system(size: 11, weight: .regular))
                            }
                            .foregroundStyle(HomeQuiet.quiet)
                        }

                        if let diff = recipe.difficulty, !diff.isEmpty {
                            Text(diff.uppercased())
                                .font(.system(size: 10, weight: .regular))
                                .tracking(0.6)
                                .foregroundStyle(HomeQuiet.quiet)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .homeQuietCard()
            .contentShape(HomeQuiet.card)
            .overlay(
                HomeQuiet.card
                    .stroke(isSelected ? Color.terra500.opacity(0.7) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .if(!isSelectMode) { view in
            view.contextMenu {
                Button(action: onFavoriteToggle) {
                    Label(
                        recipe.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: recipe.isFavorite ? "heart.slash" : "heart.fill"
                    )
                }
                if onDelete != nil {
                    Button(role: .destructive, action: { showDeleteConfirm = true }) {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recipe will be permanently deleted.")
        }
    }
}

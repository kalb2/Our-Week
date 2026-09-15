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

    private var randomEmoji: String {
        let hash = abs((recipe.name ?? "").hashValue)
        let emojis = RecipeConstants.foodEmojis
        return emojis[hash % emojis.count]
    }

    private var categoryEmoji: String {
        guard let cats = recipe.categories, !cats.isEmpty else { return randomEmoji }
        let firstCat = cats.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return RecipeConstants.categoryEmojis[firstCat] ?? randomEmoji
    }

    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.terra500 : Color.cardWhite)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(isSelected ? Color.terra600 : Color.black, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

            Image(systemName: isSelected ? "checkmark" : "circle")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(isSelected ? .white : Color.gray.opacity(0.45))
        }
        .accessibilityLabel(isSelected ? "Selected" : "Not selected")
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // Image / Placeholder
                ZStack(alignment: .topTrailing) {
                    if let data = recipe.imageData, let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 120)
                            .clipped()
                    } else {
                        // Gradient placeholder with emoji
                        LinearGradient(
                            colors: [Color.terra100, Color.terra200],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(height: 120)
                        .overlay(
                            Text(categoryEmoji)
                                .font(.system(size: 40))
                        )
                    }

                    if isSelectMode {
                        selectionBadge
                            .padding(8)
                    } else {
                        // Favorite star
                        Button(action: onFavoriteToggle) {
                            ZStack {
                                Circle()
                                    .fill(Color.cardWhite)
                                    .frame(width: 32, height: 32)
                                    .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                                Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(recipe.isFavorite ? Color.terra500 : .gray.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                }

                // Info section
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name ?? "Untitled")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .lineLimit(2)
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        if totalTime > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9, weight: .bold))
                                Text("\(totalTime) min")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.terra500)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.terra100)
                            .clipShape(Capsule())
                        }

                        if let diff = recipe.difficulty, !diff.isEmpty {
                            Text(diff)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.gray.opacity(0.6))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.08))
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.cardWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.terra500 : Color.black, lineWidth: isSelected ? 3 : 2)
            )
            .boldShadow(isSelected ? Color.terra400 : .black, size: 3, radius: 16)
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

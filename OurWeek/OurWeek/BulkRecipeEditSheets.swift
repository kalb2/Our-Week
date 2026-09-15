import SwiftUI

// MARK: - Bulk Categories

struct BulkCategoriesSheet: View {
    let recipeCount: Int
    var initialCategories: Set<String> = []
    let onApply: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategories: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 6) {
                Text("SET CATEGORIES")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.terra500)
                    .frame(maxWidth: .infinity)

                Text("Replace categories on \(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)

            FlowLayout(spacing: 8) {
                ForEach(RecipeConstants.categories, id: \.self) { cat in
                    Button(action: { toggle(cat) }) {
                        HStack(spacing: 4) {
                            Text(RecipeConstants.categoryEmojis[cat] ?? "🍽️")
                                .font(.system(size: 12))
                            Text(cat)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(selectedCategories.contains(cat) ? .white : Color.terra600)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCategories.contains(cat) ? Color.terra500 : Color.terra100)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(selectedCategories.contains(cat) ? Color.terra600 : Color.terra200, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(selectedCategories.isEmpty
                 ? "No categories selected — this clears categories on the selected recipes."
                 : "These categories will replace whatever is already on the selected recipes.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.55))

            Spacer()

            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("CANCEL")
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
                    onApply(selectedCategories)
                    dismiss()
                }) {
                    Text("REPLACE")
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
        .onAppear { selectedCategories = initialCategories }
    }

    private func toggle(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
    }
}

// MARK: - Bulk Tags

struct BulkTagsSheet: View {
    let recipeCount: Int
    let onReplace: (String) -> Void
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tagsText: String = ""

    private var hasTags: Bool {
        RecipeLabelFormatting.encodeTags(tagsText) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 6) {
                Text("SET TAGS")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Color.terra500)
                    .frame(maxWidth: .infinity)

                Text("Apply tags to \(recipeCount) \(recipeCount == 1 ? "recipe" : "recipes")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Tags (comma-separated)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                TextField("e.g. quick, family-favorite, healthy", text: $tagsText)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1.5))
            }

            Text("Replace overwrites existing tags. Add keeps what’s already there and skips duplicates.")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.gray.opacity(0.55))

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: {
                        onReplace(tagsText)
                        dismiss()
                    }) {
                        Text("REPLACE")
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

                    Button(action: {
                        onAdd(tagsText)
                        dismiss()
                    }) {
                        Text("ADD")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(hasTags ? Color.terra600 : .gray.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(hasTags ? Color.terra100 : Color.gray.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(hasTags ? Color.terra200 : Color.gray.opacity(0.2), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasTags)
                }

                Button(action: { dismiss() }) {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
    }
}

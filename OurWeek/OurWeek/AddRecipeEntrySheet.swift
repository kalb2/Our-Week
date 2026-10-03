import SwiftUI

enum AddRecipeRoute {
    case link
    case paste
    case photo
    case manual
    case pack
}

/// One entry point for every way to add a recipe.
struct AddRecipeEntrySheet: View {
    var onSelect: (AddRecipeRoute) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add a recipe")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(HomeQuiet.ink)
                .frame(maxWidth: .infinity)

            LazyVGrid(columns: columns, spacing: 12) {
                tile("Link", icon: "link", route: .link)
                tile("Paste text", icon: "doc.on.clipboard", route: .paste)
                tile("Photo", icon: "camera", route: .photo)
                tile("Manual", icon: "square.and.pencil", route: .manual)
                tile("Pack", icon: "square.stack.3d.up", route: .pack)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgBase)
    }

    private func tile(_ title: String, icon: String, route: AddRecipeRoute) -> some View {
        Button {
            onSelect(route)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                Text(title)
                    .font(.system(size: 15, weight: .regular))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
            .boldShadow(Color.terra300, size: 3, radius: 16)
        }
        .buttonStyle(.plain)
    }
}

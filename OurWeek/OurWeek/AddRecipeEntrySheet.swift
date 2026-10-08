import SwiftUI
import UIKit

enum AddRecipeRoute {
    /// `url` is a clipboard link to drop into the existing importer. Empty opens it blank.
    case link(url: String)
    case paste
    case photo
    case manual
    case pack
}

/// One entry point for every way to add a recipe.
struct AddRecipeEntrySheet: View {
    var onSelect: (AddRecipeRoute) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasCopiedLink = false
    @State private var showPack = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add a recipe")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(HomeQuiet.ink)
                    .frame(maxWidth: .infinity)

                linkHero

                if hasCopiedLink {
                    copiedLinkRow
                }

                VStack(spacing: 0) {
                    option(
                        "Snap a photo",
                        subtitle: "A cookbook page or recipe card, read with AI.",
                        icon: "camera",
                        route: .photo
                    )
                    rowDivider
                    option(
                        "Paste recipe text",
                        subtitle: "From a note, a message, or a web page.",
                        icon: "doc.plaintext",
                        route: .paste
                    )
                    rowDivider
                    option(
                        "Write it yourself",
                        subtitle: "Type the title, ingredients, and steps.",
                        icon: "square.and.pencil",
                        route: .manual
                    )
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(HomeQuiet.buttonStroke, lineWidth: 1))

                if showPack {
                    option(
                        "Import a recipe pack",
                        subtitle: "A JSON file of recipes saved for Our Week.",
                        icon: "doc",
                        route: .pack
                    )
                    .padding(.horizontal, 4)
                } else {
                    Button {
                        if reduceMotion {
                            showPack = true
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                showPack = true
                            }
                        }
                    } label: {
                        Text("More")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(HomeQuiet.quiet)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("More ways to add a recipe")
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.bgBase)
        .task { await loadCopiedLink() }
    }

    private var linkHero: some View {
        Button {
            onSelect(.link(url: ""))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 18, weight: .regular))
                Text("Import from a link")
                    .font(.system(size: 22, weight: .regular, design: .serif))
                Text("Paste a TikTok, Instagram, YouTube, or recipe site link and we'll build the recipe.")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.terra500)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import from a link")
        .accessibilityHint("Paste a TikTok, Instagram, YouTube, or recipe site link and we'll build the recipe.")
    }

    private var copiedLinkRow: some View {
        Button {
            onSelect(.link(url: copiedLinkURL()))
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.terra500)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use copied link")
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Text("Import the link you just copied")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(HomeQuiet.buttonStroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use copied link. Import the link you just copied.")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(HomeQuiet.rule)
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func option(_ title: String, subtitle: String, icon: String, route: AddRecipeRoute) -> some View {
        Button {
            onSelect(route)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color.terra500)
                    .frame(width: 28, height: 22)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .regular, design: .serif))
                        .foregroundStyle(HomeQuiet.ink)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(HomeQuiet.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(subtitle)")
    }

    /// Pattern detection does not show the paste prompt. The string is read on tap.
    private func loadCopiedLink() async {
        let patterns = try? await UIPasteboard.general.detectedPatterns(for: [.probableWebURL])
        hasCopiedLink = patterns?.contains(.probableWebURL) == true
    }

    private func copiedLinkURL() -> String {
        let raw = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return ""
        }
        return raw
    }
}

import SwiftUI

// MARK: - Recipe Pack Preview + Import

struct RecipePackImportView: View {
    let loaded: LoadedRecipePack
    @Environment(\.dismiss) private var dismiss
    @Environment(DataManager.self) private var dataManager

    @State private var duplicateIDs: Set<UUID> = []
    @State private var isImporting = false
    @State private var progressCompleted = 0
    @State private var progressTitle = ""
    @State private var summary: RecipePackImportSummary?

    private var recipes: [RecipePackEntry] { loaded.pack.recipes }
    private var totalCount: Int { recipes.count }
    private var alreadyInLibraryCount: Int { duplicateIDs.count }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let summary {
                summaryView(summary)
            } else {
                previewList
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if summary == nil {
                importBar
            }
        }
        .overlay {
            if isImporting {
                importingOverlay
            }
        }
        .onAppear { markExistingDuplicates() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 2))
                    .background(Circle().fill(.black).offset(x: 2, y: 2))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 2) {
                Text("RECIPE PACK")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)

                Text(summary == nil ? "REVIEW · THEN IMPORT" : "IMPORT COMPLETE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.terra400)
                    .tracking(1)
            }

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Preview List

    private var previewList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                packMeta

                Text("RECIPES")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(.gray.opacity(0.6))

                VStack(spacing: 12) {
                    ForEach(recipes) { entry in
                        recipeRow(entry)
                    }
                }

                Spacer().frame(height: 140)
            }
            .padding(.horizontal, 24)
        }
    }

    private var packMeta: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.terra500)

            VStack(alignment: .leading, spacing: 2) {
                Text(loaded.fileName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.terra600)
                    .lineLimit(1)

                Text("\(totalCount) recipe\(totalCount == 1 ? "" : "s") in this pack")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)
            }

            Spacer()

            if alreadyInLibraryCount > 0 {
                Text("\(alreadyInLibraryCount) DUP")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.terra100)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1.5))
            }
        }
        .padding(14)
        .background(Color.terra100.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.terra200, lineWidth: 1.5))
    }

    private func recipeRow(_ entry: RecipePackEntry) -> some View {
        let isDup = duplicateIDs.contains(entry.id)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .lineLimit(2)

                    Text(entry.displaySource)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.terra500)
                        .lineLimit(1)
                }

                Spacer()

                if isDup {
                    Text("SKIP")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(Color.terra600)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.terra100)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                }
            }

            HStack(spacing: 8) {
                countChip("\(entry.ingredientCount) ingredients", color: Color.lime400, foreground: .black)
                countChip("\(entry.stepCount) steps", color: Color.lilac400, foreground: .white)
                if let cats = entry.categories, !cats.isEmpty {
                    countChip(cats, color: Color.terra100, foreground: Color.terra600)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(Color.black, size: 2, radius: 14)
        .opacity(isDup ? 0.7 : 1)
    }

    private func countChip(_ text: String, color: Color, foreground: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .black, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.black, lineWidth: 1.5))
            .lineLimit(1)
    }

    // MARK: - Import Bar

    private var importBar: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.bgBase.opacity(0), Color.bgBase], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)

            VStack(spacing: 8) {
                if alreadyInLibraryCount > 0 {
                    Text("\(alreadyInLibraryCount) already in your library will be skipped")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.gray)
                }

                Button(action: startImport) {
                    Text(importButtonTitle)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: [Color.terra400, Color.peach500],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                        .shadow(color: Color.peach500.opacity(0.4), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(isImporting || totalCount == 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.bgBase)
        }
    }

    private var importButtonTitle: String {
        let newCount = max(0, totalCount - alreadyInLibraryCount)
        if newCount == 0 {
            return "CONFIRM"
        }
        return "IMPORT \(newCount) RECIPE\(newCount == 1 ? "" : "S")"
    }

    // MARK: - Summary

    private func summaryView(_ summary: RecipePackImportSummary) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                Image(systemName: summary.imported > 0 ? "checkmark.circle.fill" : "tray")
                    .font(.system(size: 56))
                    .foregroundStyle(summary.imported > 0 ? Color.lime500 : Color.terra400)

                Text(summary.imported > 0 ? "Pack imported" : "Nothing new to add")
                    .font(.system(size: 22, weight: .black, design: .rounded))

                VStack(spacing: 10) {
                    summaryRow(label: "Imported", value: summary.imported, color: Color.lime500)
                    summaryRow(label: "Skipped duplicates", value: summary.skippedDuplicates, color: Color.terra500)
                    summaryRow(label: "Failed", value: summary.failed, color: Color.red)
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(Color.black, size: 3, radius: 14)

                if !summary.failedTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("COULDN'T IMPORT")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.gray.opacity(0.6))

                        ForEach(Array(summary.failedTitles.enumerated()), id: \.offset) { _, title in
                            Text(title)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: { dismiss() }) {
                    Text("DONE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: [Color.terra400, Color.peach500],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.black, lineWidth: 2))
                        .shadow(color: Color.peach500.opacity(0.4), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)

                Spacer().frame(height: 40)
            }
            .padding(.horizontal, 24)
        }
    }

    private func summaryRow(label: String, value: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Spacer()
            Text("\(value)")
                .font(.system(size: 18, weight: .black, design: .rounded))
        }
    }

    // MARK: - Progress Overlay

    private var importingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView(value: Double(progressCompleted), total: Double(max(totalCount, 1)))
                    .tint(Color.terra500)
                    .padding(.horizontal, 8)

                Text("Importing recipes…")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("\(progressCompleted) of \(totalCount)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))

                if !progressTitle.isEmpty {
                    Text(progressTitle)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func markExistingDuplicates() {
        var found = Set<UUID>()
        var seenURLs = Set<String>()
        var seenNameAndURL = Set<String>()

        for entry in recipes {
            let url = entry.sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let nameKey = "\(name.lowercased())|\(url.lowercased())"

            let inLibrary = dataManager.hasDuplicateRecipe(sourceURL: url, name: name)
            let inPack = (!url.isEmpty && seenURLs.contains(url.lowercased()))
                || seenNameAndURL.contains(nameKey)

            if inLibrary || inPack {
                found.insert(entry.id)
            }

            if !url.isEmpty {
                seenURLs.insert(url.lowercased())
            }
            seenNameAndURL.insert(nameKey)
        }
        duplicateIDs = found
    }

    private func startImport() {
        guard !isImporting else { return }
        isImporting = true
        progressCompleted = 0
        progressTitle = ""

        Task {
            let result = await RecipePackImporter.importPack(loaded.pack, dataManager: dataManager) { completed, _, title in
                progressCompleted = completed
                progressTitle = title
            }

            // Let the last progress tick paint before swapping to the summary.
            await Task.yield()

            isImporting = false
            summary = result
        }
    }
}

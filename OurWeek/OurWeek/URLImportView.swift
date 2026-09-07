import SwiftUI

// MARK: - URL Import View

struct URLImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var scrapedRecipe: ScrapedRecipe?
    @Binding var showPreview: Bool

    @State private var urlText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadingMessage = "Fetching recipe..."
    @State private var showSuccess = false
    @State private var showAIErrorOption = false
    @State private var failedHTMLContent: String?

    private var isValidURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil else {
            return false
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    // URL Input Section
                    urlInputSection

                    // Example Sites
                    exampleSites

                    // Error State
                    if let error = errorMessage {
                        errorView(error)
                    }

                    Spacer().frame(height: 80)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color.bgBase.ignoresSafeArea())
        .overlay(alignment: .bottom) { importButton }
        .overlay {
            if isLoading {
                loadingOverlay
            }
        }
        .overlay {
            if showSuccess {
                successOverlay
            }
        }
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
                Text("IMPORT RECIPE")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .textCase(.uppercase)
                    .tracking(-0.5)

                Text("FROM URL")
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

    // MARK: - URL Input

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("RECIPE URL")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.gray.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste a link from any recipe website")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.gray)

                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.terra400)

                    TextField("https://example.com/recipe/...", text: $urlText)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: urlText) { _, _ in
                            errorMessage = nil
                        }

                    if !urlText.isEmpty {
                        Button(action: { urlText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.gray.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
                .boldShadow(.black, size: 3, radius: 14)

                // Paste from clipboard button
                Button(action: pasteFromClipboard) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 12, weight: .bold))
                        Text("Paste from clipboard")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(Color.terra500)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.terra100.opacity(0.5))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Example Sites

    private var exampleSites: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUPPORTED SITES")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(.gray.opacity(0.6))

            Text("Works with most recipe websites that use structured data")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.gray)

            FlowLayout(spacing: 8) {
                ForEach(["AllRecipes", "Food Network", "Bon Appétit", "Serious Eats",
                         "BBC Good Food", "Budget Bytes", "Tasty", "Smitten Kitchen"], id: \.self) { site in
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.lime500)
                        Text(site)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.terra600)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.terra100.opacity(0.4))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.terra200, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Error View

    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                Text("Error")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(4)
                
            if showAIErrorOption && KeychainManager.hasGeminiAPIKey() {
                Button(action: {
                    if let html = failedHTMLContent {
                        startAIImport(html: html)
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("Try AI Parsing")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
                }
                .padding(.top, 4)
            } else {
                Text("Make sure it's a valid recipe page and try again. Some sites block automated access.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black, lineWidth: 2))
        .boldShadow(.black, size: 3, radius: 14)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Import Button

    private var importButton: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color.bgBase.opacity(0), Color.bgBase], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)

            VStack {
                Button(action: startImport) {
                    Text("IMPORT RECIPE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(
                            LinearGradient(
                                colors: isValidURL ? [Color.terra400, Color.peach500] : [Color.gray.opacity(0.3), Color.gray.opacity(0.3)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isValidURL ? Color.black : Color.gray.opacity(0.3), lineWidth: 2))
                        .shadow(color: isValidURL ? Color.peach500.opacity(0.4) : .clear, radius: 10, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .disabled(!isValidURL || isLoading)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(Color.bgBase)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Color.terra500)

                Text(loadingMessage)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)

                Text("This usually takes 3-5 seconds")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .transition(.opacity)
    }

    // MARK: - Success Overlay

    private var successOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.lime500)
                    .symbolEffect(.bounce, value: showSuccess)

                Text("Recipe Found!")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(40)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func pasteFromClipboard() {
        if let clipboardString = UIPasteboard.general.string {
            urlText = clipboardString
        }
    }

    private func startImport() {
        guard isValidURL else { return }
        errorMessage = nil
        showAIErrorOption = false
        failedHTMLContent = nil
        isLoading = true
        loadingMessage = "Fetching recipe..."

        Task {
            // Show progress update after delay
            let progressTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if isLoading { loadingMessage = "Still working..." }
                }
            }

            do {
                let recipe = try await RecipeScraperService.importRecipe(from: urlText)
                progressTask.cancel()

                await MainActor.run {
                    isLoading = false
                    scrapedRecipe = recipe
                    showSuccess = true
                }

                // Brief success animation then transition to preview
                try? await Task.sleep(nanoseconds: 800_000_000)

                await MainActor.run {
                    showSuccess = false
                    dismiss()
                }
            } catch let error as ScraperError {
                progressTask.cancel()
                
                // If it's a parsing error, we might have the HTML and can try AI fallback
                if case .noRecipeFound(let html) = error {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = "Standard recipe parsing failed."
                        failedHTMLContent = html
                        showAIErrorOption = true
                    }
                } else {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                        showAIErrorOption = false
                    }
                }
            } catch {
                progressTask.cancel()
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Something went wrong. Please try again."
                    showAIErrorOption = false
                }
            }
        }
    }
    
    private func startAIImport(html: String) {
        errorMessage = nil
        showAIErrorOption = false
        isLoading = true
        loadingMessage = "AI parsing recipe..."
        
        Task {
            // Show progress update after delay
            let progressTask = Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run {
                    if isLoading { loadingMessage = "AI is thinking..." }
                }
            }
            
            do {
                let recipe = try await GeminiService.shared.parseRecipeFromHTML(html: html, sourceUrl: urlText)
                progressTask.cancel()
                
                await MainActor.run {
                    isLoading = false
                    scrapedRecipe = recipe
                    showSuccess = true
                }
                
                // Brief success animation then transition to preview
                try? await Task.sleep(nanoseconds: 800_000_000)
                
                await MainActor.run {
                    showSuccess = false
                    dismiss()
                }
            } catch {
                progressTask.cancel()
                await MainActor.run {
                    isLoading = false
                    errorMessage = "AI parsing failed: \(error.localizedDescription)"
                    showAIErrorOption = false
                }
            }
        }
    }
}

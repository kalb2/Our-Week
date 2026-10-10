//
//  GeminiService.swift
//  OurWeek
//
//  Main AI service for text and image generation via Google Gemini API.
//  Uses the free tier: 1,500 req/day, 15 req/min.
//

import Foundation
import UIKit

@Observable
class GeminiService {
    static let shared = GeminiService()

    // MARK: - Configuration

    private let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    private let textModel = "gemini-3.8-flash"
    /// Lighter model tried once when textModel stays overloaded (ai.google.dev/gemini-api/docs/models).
    private let fallbackTextModel = "gemini-3.5-flash-lite"
    /// Waits before each retry of an overloaded request.
    private let retryDelays: [UInt64] = [2, 5]
    private let imageModel = "gemini-2.5-flash-image"

    private let rateLimiter = RateLimiter.shared
    private let cache = AIResponseCache.shared

    private init() {}

    // MARK: - Text Generation

    /// Generate text from a prompt using Gemini.
    func generateText(prompt: String, systemInstructions: String? = nil) async throws -> String {
        try await generateText(prompt: prompt, imageJPEG: nil, systemInstructions: systemInstructions)
    }

    private func generateText(
        prompt: String,
        imageJPEG: Data?,
        systemInstructions: String?
    ) async throws -> String {
        let cacheKey = (systemInstructions ?? "") + prompt
        if imageJPEG == nil, let cached = cache.getCachedTextResponse(prompt: cacheKey) {
            return cached
        }

        let apiKey = try getAPIKey()
        _ = try rateLimiter.canMakeRequest()

        var parts: [[String: Any]] = [["text": prompt]]
        if let imageJPEG {
            parts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": imageJPEG.base64EncodedString()
                ]
            ])
        }

        var body: [String: Any] = [
            "contents": [
                ["parts": parts]
            ],
            "generationConfig": [
                "temperature": imageJPEG == nil ? 0.7 : 0.2,
                "maxOutputTokens": 4096,
                "thinkingConfig": ["thinkingLevel": "low"]
            ]
        ]

        if let systemInstructions = systemInstructions {
            body["systemInstruction"] = [
                "parts": [["text": systemInstructions]]
            ]
        }

        // Vision: 45s per attempt, ~90s overall. Text: 30s per attempt, ~75s overall.
        let data = try await generateWithRetry(
            apiKey: apiKey,
            body: body,
            attemptTimeout: imageJPEG == nil ? 30 : 45,
            totalBudget: imageJPEG == nil ? 75 : 90
        )
        let text = try extractText(from: data)

        rateLimiter.recordRequest()
        if imageJPEG == nil {
            cache.cacheTextResponse(prompt: cacheKey, response: text)
        }

        return text
    }

    private func jpegData(from image: UIImage, maxDimension: CGFloat = 1600) -> Data? {
        let size = image.size
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension && longest > 0 ? maxDimension / longest : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }

    // MARK: - Image Generation

    /// Generate an image from a text prompt using Gemini.
    func generateImage(prompt: String) async throws -> UIImage {
        let apiKey = try getAPIKey()
        _ = try rateLimiter.canMakeRequest()

        let url = URL(string: "\(baseURL)/models/\(imageModel):generateContent?key=\(apiKey)")!
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseModalities": ["IMAGE", "TEXT"],
                "temperature": 0.8
            ]
        ]

        let data = try await makeRequest(url: url, body: body, timeout: 60)
        let image = try extractImage(from: data)

        rateLimiter.recordRequest()

        return image
    }

    /// Generate a food photography image for a recipe.
    func generateRecipeImage(
        recipeName: String,
        description: String,
        ingredients: [String],
        style: ImageStyle
    ) async throws -> UIImage {
        // Check cache
        // We'll use a deterministic "recipe ID" from the name for caching
        let cacheId = UUID(uuidString: "00000000-0000-0000-0000-000000000000") ?? UUID()
        if let cached = cache.getCachedImage(recipeId: cacheId, style: style) {
            return cached
        }

        let prompt = AIPromptTemplates.foodImagePrompt(
            recipeName: recipeName,
            description: description,
            ingredients: ingredients,
            style: style
        )

        let image = try await generateImage(prompt: prompt)

        // Cache with the deterministic ID
        cache.cacheImage(recipeId: cacheId, style: style, image: image)

        return image
    }

    // MARK: - Recipe Parsing

    /// Parse a recipe from HTML content using AI (fallback when Schema.org fails).
    func parseRecipeFromHTML(html: String, sourceUrl: String) async throws -> ScrapedRecipe {
        let prompt = AIPromptTemplates.recipeParsingPrompt(html: html, url: sourceUrl)
        let responseText = try await generateText(
            prompt: prompt,
            systemInstructions: "You are a recipe extraction assistant. Return only valid JSON, no explanation."
        )

        return try parseRecipeJSON(responseText, sourceURL: sourceUrl)
    }

    /// Read a recipe photo or screenshot. Requires a Gemini key.
    func parseRecipeFromImage(_ image: UIImage) async throws -> ScrapedRecipe {
        guard let jpeg = jpegData(from: image) else {
            throw GeminiError.imageDecodingFailed
        }
        let prompt = AIPromptTemplates.recipeImageParsingPrompt()
        let responseText = try await generateText(
            prompt: prompt,
            imageJPEG: jpeg,
            systemInstructions: "You are a recipe extraction assistant. Return only valid JSON, no explanation."
        )
        var recipe = try parseRecipeJSON(responseText, sourceURL: "")
        recipe.sourceDomain = "Photo"
        recipe.inlineImageData = jpeg
        return recipe
    }

    // MARK: - Connection Test

    /// Quick test to verify the API key works.
    func testConnection() async throws -> Bool {
        let apiKey = try getAPIKey()
        _ = try rateLimiter.canMakeRequest()

        let url = URL(string: "\(baseURL)/models/\(textModel):generateContent?key=\(apiKey)")!
        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": "Say hello in exactly one word."]]]
            ],
            "generationConfig": [
                "temperature": 0.0,
                "maxOutputTokens": 1024,
                "thinkingConfig": ["thinkingLevel": "low"]
            ]
        ]

        let data = try await makeRequest(url: url, body: body, timeout: 15)
        let text = try extractText(from: data)

        rateLimiter.recordRequest()

        return !text.isEmpty
    }

    // MARK: - Network Layer

    /// Calls textModel, retrying overloaded responses (2s, then 5s), then tries the
    /// lighter fallback model once. Never runs past `totalBudget` seconds.
    private func generateWithRetry(
        apiKey: String,
        body: [String: Any],
        attemptTimeout: TimeInterval,
        totalBudget: TimeInterval
    ) async throws -> Data {
        let deadline = Date().addingTimeInterval(totalBudget)
        var attempts: [(model: String, delay: UInt64)] = [(textModel, 0)]
        attempts += retryDelays.map { (textModel, $0) }
        attempts.append((fallbackTextModel, 0))

        var lastError: Error = GeminiError.modelBusy
        for attempt in attempts {
            if attempt.delay > 0 {
                guard Date().addingTimeInterval(TimeInterval(attempt.delay) + 5) < deadline else { break }
                try await Task.sleep(nanoseconds: attempt.delay * 1_000_000_000)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 5 else { break }
            let url = URL(string: "\(baseURL)/models/\(attempt.model):generateContent?key=\(apiKey)")!
            do {
                return try await makeRequest(url: url, body: body, timeout: min(attemptTimeout, remaining))
            } catch GeminiError.modelBusy {
                lastError = GeminiError.modelBusy
                print("[GeminiService] \(attempt.model) busy, retrying")
            }
        }
        throw lastError
    }

    private func makeRequest(url: URL, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // timeoutInterval alone is an idle timeout; the resource timeout caps the whole request.
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw GeminiError.timeout
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GeminiError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return data
        case 400:
            // Check if it's an invalid API key error
            if let errorInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorInfo["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("[GeminiService] API Error 400: \(message)")
                if message.lowercased().contains("api key") {
                    throw GeminiError.invalidAPIKey
                }
                throw GeminiError.parsingError(message: message)
            }
            throw GeminiError.invalidResponse
        case 401, 403:
            throw GeminiError.invalidAPIKey
        case 404:
            // Model not found
            if let errorInfo = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorInfo["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("[GeminiService] API Error 404: \(message)")
                throw GeminiError.parsingError(message: "Model not found: \(message)")
            }
            throw GeminiError.parsingError(message: "The AI model could not be found. Please try again later.")
        case 429:
            print("[GeminiService] API rate limited (429)")
            if Self.isOverloaded(data) {
                throw GeminiError.modelBusy
            }
            throw GeminiError.rateLimitExceeded(resetTime: Date().addingTimeInterval(60))
        case 500, 503:
            if let body = String(data: data, encoding: .utf8) {
                print("[GeminiService] Server busy \(httpResponse.statusCode): \(body.prefix(300))")
            }
            throw GeminiError.modelBusy
        case 500...599:
            if let body = String(data: data, encoding: .utf8) {
                print("[GeminiService] Server error \(httpResponse.statusCode): \(body.prefix(300))")
            }
            if let message = Self.apiErrorMessage(from: data) {
                throw GeminiError.parsingError(message: message)
            }
            throw GeminiError.invalidResponse
        default:
            if let body = String(data: data, encoding: .utf8) {
                print("[GeminiService] Unexpected status \(httpResponse.statusCode): \(body.prefix(300))")
            }
            if let message = Self.apiErrorMessage(from: data) {
                throw GeminiError.parsingError(message: message)
            }
            throw GeminiError.invalidResponse
        }
    }

    /// True when a 429 body says the model is overloaded rather than the user's quota being hit.
    private static func isOverloaded(_ data: Data) -> Bool {
        let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = info?["error"] as? [String: Any]
        let status = (error?["status"] as? String ?? "").uppercased()
        let message = (error?["message"] as? String ?? "").lowercased()
        return status == "UNAVAILABLE" || message.contains("high demand") || message.contains("overloaded")
    }

    private static func apiErrorMessage(from data: Data) -> String? {
        guard let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = info["error"] as? [String: Any],
              let message = error["message"] as? String,
              !message.isEmpty else { return nil }
        return message
    }

    // MARK: - Response Parsing

    private func extractText(from data: Data) throws -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GeminiError.invalidResponse
        }
        guard let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first else {
            if let feedback = json["promptFeedback"] as? [String: Any],
               let blockReason = feedback["blockReason"] as? String {
                throw GeminiError.parsingError(message: "Request blocked: \(blockReason)")
            }
            throw GeminiError.parsingError(message: "AI returned no candidates")
        }
        guard let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              !parts.isEmpty else {
            let reason = firstCandidate["finishReason"] as? String ?? "UNKNOWN"
            throw GeminiError.parsingError(message: "Response stopped: \(reason)")
        }

        // Find the text part
        for part in parts {
            if let text = part["text"] as? String {
                return cleanMarkdown(text)
            }
        }

        throw GeminiError.noContent
    }

    private func extractImage(from data: Data) throws -> UIImage {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            // Log the actual response for debugging
            if let responseStr = String(data: data, encoding: .utf8) {
                print("[GeminiService] Image response: \(responseStr.prefix(500))")
            }
            throw GeminiError.invalidResponse
        }

        // Find the inline data part (image) — handle both camelCase and snake_case keys
        for part in parts {
            let inlineData = part["inlineData"] as? [String: Any]
                ?? part["inline_data"] as? [String: Any]
            
            if let inlineData = inlineData,
               let base64String = inlineData["data"] as? String {
                guard let imageData = Data(base64Encoded: base64String),
                      let image = UIImage(data: imageData) else {
                    throw GeminiError.imageDecodingFailed
                }
                return image
            }
        }

        // Log what we received if no image found
        if let responseStr = String(data: data, encoding: .utf8) {
            print("[GeminiService] No image in parts. Response: \(responseStr.prefix(500))")
        }
        throw GeminiError.noContent
    }

    // MARK: - Helpers

    private func getAPIKey() throws -> String {
        do {
            return try KeychainManager.getGeminiAPIKey()
        } catch {
            throw GeminiError.noAPIKey
        }
    }

    /// Strip markdown code fences from AI response text.
    private func cleanMarkdown(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove ```json ... ``` or ``` ... ```
        if cleaned.hasPrefix("```") {
            // Remove opening fence (possibly with language identifier)
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            // Remove closing fence
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned
    }

    /// Parse AI-generated recipe JSON into a ScrapedRecipe.
    /// Accepts the prompt's object shape and the looser shapes models actually return
    /// (integer amounts, string amounts, ingredient strings, step objects, label arrays).
    private func parseRecipeJSON(_ jsonString: String, sourceURL: String) throws -> ScrapedRecipe {
        guard let json = jsonObject(from: jsonString) else {
            throw GeminiError.parsingError(message: "Invalid JSON in AI response")
        }

        let title = firstText(json, keys: ["title", "name"])
        let description = firstText(json, keys: ["description"])
        var prepTime = RecipeScraperService.flexibleMinutes(json["prepTime"] ?? json["prep_time"])
        var cookTime = RecipeScraperService.flexibleMinutes(json["cookTime"] ?? json["cook_time"])
        if cookTime == 0 {
            cookTime = RecipeScraperService.flexibleMinutes(json["performTime"])
        }
        if prepTime == 0 && cookTime == 0 {
            cookTime = RecipeScraperService.flexibleMinutes(json["totalTime"] ?? json["total_time"])
        }
        let servings = RecipeScraperService.flexibleServings(
            json["servings"] ?? json["recipeYield"] ?? json["yield"],
            fallback: 4
        )
        let ingredients = RecipeScraperService.scrapedIngredients(
            from: json["ingredients"] ?? json["recipeIngredient"]
        )
        let instructions = RecipeScraperService.instructionTexts(
            from: json["instructions"] ?? json["recipeInstructions"] ?? json["steps"]
        )
        let categories = RecipeScraperService.joinedLabels(
            json["categories"] ?? json["category"] ?? json["recipeCategory"]
        )
        let tags = RecipeScraperService.joinedLabels(json["tags"] ?? json["keywords"])
        let difficulty = RecipeScraperService.joinedLabels(json["difficulty"])
        let imageURL = firstImageURL(json["imageURL"] ?? json["image"])
        let domain = URL(string: sourceURL)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""

        return ScrapedRecipe(
            title: title,
            description: description,
            ingredients: ingredients,
            instructions: instructions,
            prepTimeMinutes: prepTime,
            cookTimeMinutes: cookTime,
            servings: servings,
            imageURL: imageURL,
            sourceURL: sourceURL,
            sourceDomain: domain,
            categories: categories,
            tags: tags,
            difficulty: difficulty
        )
    }

    private func jsonObject(from text: String) -> [String: Any]? {
        let candidates = [text, jsonSlice(from: text)]
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let dict = object as? [String: Any] { return dict }
            if let list = object as? [Any], let first = list.first as? [String: Any] { return first }
        }
        return nil
    }

    private func jsonSlice(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end else { return text }
        return String(text[start...end])
    }

    private func firstText(_ json: [String: Any], keys: [String]) -> String {
        for key in keys {
            let text = RecipeScraperService.joinedLabels(json[key])
            if !text.isEmpty { return text }
        }
        return ""
    }

    private func firstImageURL(_ value: Any?) -> String? {
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let dict = value as? [String: Any] {
            return firstImageURL(dict["url"] ?? dict["contentUrl"])
        }
        if let list = value as? [Any] {
            for item in list {
                if let url = firstImageURL(item) { return url }
            }
        }
        return nil
    }
}

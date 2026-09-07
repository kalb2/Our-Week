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
    private let textModel = "gemini-2.5-flash"
    private let imageModel = "gemini-2.5-flash-image"

    private let rateLimiter = RateLimiter.shared
    private let cache = AIResponseCache.shared

    private init() {}

    // MARK: - Text Generation

    /// Generate text from a prompt using Gemini.
    func generateText(prompt: String, systemInstructions: String? = nil) async throws -> String {
        // Check cache first
        let cacheKey = (systemInstructions ?? "") + prompt
        if let cached = cache.getCachedTextResponse(prompt: cacheKey) {
            return cached
        }

        let apiKey = try getAPIKey()
        _ = try rateLimiter.canMakeRequest()

        let url = URL(string: "\(baseURL)/models/\(textModel):generateContent?key=\(apiKey)")!
        var body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": 0.7,
                "maxOutputTokens": 4096
            ]
        ]

        if let systemInstructions = systemInstructions {
            body["systemInstruction"] = [
                "parts": [["text": systemInstructions]]
            ]
        }

        let data = try await makeRequest(url: url, body: body, timeout: 30)
        let text = try extractText(from: data)

        rateLimiter.recordRequest()
        cache.cacheTextResponse(prompt: cacheKey, response: text)

        return text
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
                "maxOutputTokens": 10
            ]
        ]

        let data = try await makeRequest(url: url, body: body, timeout: 15)
        let text = try extractText(from: data)

        rateLimiter.recordRequest()

        return !text.isEmpty
    }

    // MARK: - Network Layer

    private func makeRequest(url: URL, body: [String: Any], timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw GeminiError.timeout
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
            throw GeminiError.rateLimitExceeded(resetTime: Date().addingTimeInterval(60))
        case 500...599:
            if let body = String(data: data, encoding: .utf8) {
                print("[GeminiService] Server error \(httpResponse.statusCode): \(body.prefix(300))")
            }
            throw GeminiError.invalidResponse
        default:
            if let body = String(data: data, encoding: .utf8) {
                print("[GeminiService] Unexpected status \(httpResponse.statusCode): \(body.prefix(300))")
            }
            throw GeminiError.invalidResponse
        }
    }

    // MARK: - Response Parsing

    private func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GeminiError.invalidResponse
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
    private func parseRecipeJSON(_ jsonString: String, sourceURL: String) throws -> ScrapedRecipe {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.parsingError(message: "Invalid JSON in AI response")
        }

        let title = json["title"] as? String ?? "AI-Parsed Recipe"
        let description = json["description"] as? String ?? ""
        let prepTime = json["prepTime"] as? Int ?? 0
        let cookTime = json["cookTime"] as? Int ?? 0
        let servings = json["servings"] as? Int ?? 4
        let imageURL = json["imageURL"] as? String

        // Parse ingredients
        var ingredients: [ScrapedIngredient] = []
        if let ingredientArray = json["ingredients"] as? [[String: Any]] {
            for ing in ingredientArray {
                let amount = ing["amount"] as? Double ?? 0
                let unit = ing["unit"] as? String ?? ""
                let name = ing["name"] as? String ?? ""
                let notes = ing["notes"] as? String ?? ""
                ingredients.append(ScrapedIngredient(
                    amount: amount,
                    unit: unit,
                    name: name,
                    notes: notes
                ))
            }
        }

        // Parse instructions
        var instructions: [String] = []
        if let instrArray = json["instructions"] as? [String] {
            instructions = instrArray
        }

        // Parse source domain
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
            sourceDomain: domain
        )
    }
}

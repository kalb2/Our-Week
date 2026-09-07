//
//  AIPromptTemplates.swift
//  OurWeek
//
//  Reusable, optimized prompts for Gemini AI operations.
//

import Foundation

// MARK: - Image Style

enum ImageStyle: String, CaseIterable, Identifiable {
    case realistic = "Realistic"
    case minimalist = "Minimalist"
    case rustic = "Rustic"
    case magazine = "Magazine"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .realistic: return "camera"
        case .minimalist: return "square.grid.2x2"
        case .rustic: return "leaf"
        case .magazine: return "book"
        }
    }
}

// MARK: - Prompt Templates

struct AIPromptTemplates {

    // MARK: - Recipe Parsing

    static func recipeParsingPrompt(html: String, url: String) -> String {
        // Truncate HTML to avoid hitting token limits
        let maxChars = 15000
        let truncatedHTML = html.count > maxChars ? String(html.prefix(maxChars)) : html

        return """
        You are a recipe parser. Extract recipe information from this webpage content.

        Webpage HTML (may be truncated):
        \(truncatedHTML)

        Source URL: \(url)

        Parse and return ONLY valid JSON (no markdown, no explanation, no code fences):
        {
          "title": "Recipe Name",
          "description": "Brief description",
          "prepTime": 15,
          "cookTime": 30,
          "servings": 4,
          "difficulty": "easy",
          "ingredients": [
            {
              "amount": 1.5,
              "unit": "cups",
              "name": "flour",
              "notes": "all-purpose"
            }
          ],
          "instructions": [
            "Step 1 description",
            "Step 2 description"
          ],
          "categories": "dinner",
          "tags": "quick, easy",
          "imageURL": "https://..."
        }

        Rules:
        - Return ONLY the JSON object, nothing else
        - If prep/cook time not found, estimate based on recipe complexity
        - Default servings to 4 if not specified
        - Parse ingredients carefully: extract amount (as number), unit, name, and notes
        - If amount is not a number (e.g. "a pinch"), set amount to 0 and put it in notes
        - Split instructions into clear separate steps
        - Estimate difficulty: "easy" (< 5 steps), "medium" (5-10), "hard" (> 10)
        - For categories use a single string like "dinner", "dessert", "snack", etc.
        - For tags use a comma-separated string
        - Include imageURL if found in the HTML (look for og:image or recipe image)
        """
    }

    // MARK: - Food Photography Image Generation

    static func foodImagePrompt(
        recipeName: String,
        description: String,
        ingredients: [String],
        style: ImageStyle
    ) -> String {
        let styleDescription = getStyleDescription(style)
        let keyIngredients = ingredients.prefix(5).joined(separator: ", ")

        return """
        Generate a \(styleDescription) professional food photography image of \(recipeName).

        Description: \(description)

        Key ingredients visible: \(keyIngredients)

        Style guidelines:
        - Professional food photography
        - Natural lighting from 45-degree angle
        - \(getSurfaceType(style))
        - Beautiful plating and garnish
        - Shallow depth of field (blurred background)
        - Warm, inviting colors
        - Restaurant-quality presentation
        - No text or labels on the image
        - Family-friendly and appetizing

        The dish should look delicious and make someone want to cook it immediately.
        """
    }

    // MARK: - Style Helpers

    private static func getStyleDescription(_ style: ImageStyle) -> String {
        switch style {
        case .realistic: return "photorealistic, professional food photography"
        case .minimalist: return "clean, minimalist"
        case .rustic: return "rustic, homestyle"
        case .magazine: return "editorial magazine-quality"
        }
    }

    private static func getSurfaceType(_ style: ImageStyle) -> String {
        switch style {
        case .realistic, .magazine: return "Modern marble or slate surface"
        case .minimalist: return "Clean white marble background"
        case .rustic: return "Rustic wooden table"
        }
    }
}

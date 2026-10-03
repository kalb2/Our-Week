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
          "difficulty": "Easy",
          "ingredients": [
            {
              "amount": 0.5,
              "unit": "cup",
              "name": "frozen corn",
              "notes": ""
            }
          ],
          "instructions": [
            "Step 1 description",
            "Step 2 description"
          ],
          "categories": "Dinner",
          "tags": "quick, easy",
          "imageURL": "https://..."
        }

        Rules:
        - Return ONLY the JSON object, nothing else
        - Copy the recipe on the page. Do not invent a different dish or leave out lines you can see
        - title, every ingredient, and every step are required when they appear in the page
        - prepTime and cookTime are integers in minutes. Use 0 only when the page does not state that time
        - If the page gives one total time and not prep/cook, put that number in cookTime
        - servings is an integer. Use 4 only when the page does not state a yield
        - ingredients is an array of objects. amount is a JSON number for the full quantity (0.5 for 1/2, 0.25 for 1/4, 1.5 for 1 1/2), never a string and never split so the name starts with /2
        - unit is only the measure (cup, tsp, tbsp, can, lb, package). Leave it "" when there is no measure. Do not put the unit in the name
        - name is the full ingredient after the amount and unit, including adjectives and parentheticals. "1 lb boneless, skinless chicken breasts" is amount 1, unit lb, name "boneless, skinless chicken breasts". Never shorten the name to the first word
        - notes stays "" unless the line is only an aside such as "to taste"
        - If an amount is not numeric (a pinch, to taste), set amount to 0 and put those words in notes
        - instructions is an array of strings, one step per item, in order. Do not wrap steps in objects
        - difficulty is "Easy", "Medium", or "Hard" when the page says so, otherwise ""
        - categories is one of: Main, Full meal, Breakfast, Lunch, Dinner, Dessert, Snack, Side, Appetizer, Drink
        - Use Main or Dinner for a savory meal, and Dessert, Side, Snack, Appetizer, or Drink when that is what the page shows
        - tags is a comma-separated string of extra labels, or ""
        - Include imageURL when the HTML has an og:image or recipe image
        """
    }

    /// Read a photographed or screenshotted recipe into the same JSON shape as HTML parsing.
    static func recipeImageParsingPrompt() -> String {
        """
        You are a recipe parser. Read the recipe in the attached photo or screenshot.

        Return ONLY valid JSON (no markdown, no explanation, no code fences):
        {
          "title": "Recipe Name",
          "description": "Brief description",
          "prepTime": 15,
          "cookTime": 30,
          "servings": 4,
          "ingredients": [
            {
              "amount": 0.5,
              "unit": "tsp",
              "name": "kosher salt",
              "notes": ""
            }
          ],
          "instructions": [
            "Step 1 description",
            "Step 2 description"
          ],
          "categories": "Dinner",
          "tags": ""
        }

        Rules:
        - Return ONLY the JSON object
        - Transcribe the recipe you can see. Do not invent a different dish or skip lines that are visible
        - title, every ingredient, and every step must be copied when they are in the photo
        - prepTime and cookTime are integers in minutes. Use 0 when that time is not visible
        - If only one total time is shown, put it in cookTime and use 0 for prepTime
        - servings is an integer. Use 4 only when no yield is visible
        - ingredients is an array of objects. amount is a JSON number for the full quantity (0.5 for 1/2, 0.25 for 1/4, 1.5 for 1 1/2), never a string and never split so the name starts with /2
        - unit is only the measure (cup, tsp, tbsp, can, lb, package). Leave it "" when there is no measure
        - name is the full ingredient after the amount and unit, including adjectives and parentheticals. Never shorten "boneless, skinless chicken breasts" to "boneless"
        - notes stays "" unless the line is only an aside such as "to taste"
        - If an amount is not numeric, set amount to 0 and put the words in notes
        - instructions is an array of strings, one visible step per item, in order. Do not wrap steps in objects
        - categories is one of: Main, Full meal, Breakfast, Lunch, Dinner, Dessert, Snack, Side, Appetizer, Drink
        - Use Main or Dinner for a savory meal, and Dessert, Side, Snack, Appetizer, or Drink when that is what the photo shows
        - tags is a comma-separated string, or ""
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

//
//  GeminiError.swift
//  OurWeek
//
//  Error types for Gemini AI service, Keychain, and rate limiting.
//

import Foundation

// MARK: - Gemini API Errors

enum GeminiError: Error, LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case rateLimitExceeded(resetTime: Date?)
    case networkError(underlying: Error)
    case invalidResponse
    case noContent
    case parsingError(message: String)
    case timeout
    case quotaExceeded
    case imageDecodingFailed

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "AI features require an API key. Add one in Settings."
        case .invalidAPIKey:
            return "Your API key appears to be invalid. Please check it in Settings."
        case .rateLimitExceeded(let resetTime):
            if let reset = resetTime {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relative = formatter.localizedString(for: reset, relativeTo: Date())
                return "You've hit the AI rate limit. Try again \(relative)."
            }
            return "You've hit the AI rate limit. Please wait a moment and try again."
        case .networkError:
            return "Couldn't connect to AI service. Check your internet connection."
        case .invalidResponse:
            return "AI returned an unexpected response. Please try again."
        case .noContent:
            return "AI didn't generate any content. Please try again."
        case .parsingError(let message):
            return "AI response couldn't be processed: \(message)"
        case .timeout:
            return "AI request timed out. Please try again."
        case .quotaExceeded:
            return "You've used your daily AI quota. It resets at midnight."
        case .imageDecodingFailed:
            return "Couldn't process the generated image. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noAPIKey:
            return "Go to Settings → AI Features and enter your free Gemini API key from ai.google.dev."
        case .invalidAPIKey:
            return "Double-check your API key in Settings → AI Features. You can get a new one at ai.google.dev."
        case .rateLimitExceeded:
            return "Wait a moment before making another request. The free tier allows 15 requests per minute."
        case .networkError:
            return "Make sure you have an active internet connection and try again."
        case .quotaExceeded:
            return "The free tier allows 1,500 requests per day. Try again tomorrow or reduce usage with caching."
        default:
            return "Please try again. If the problem persists, check your API key in Settings."
        }
    }
}

// MARK: - Keychain Errors

enum KeychainError: Error, LocalizedError {
    case unableToSave
    case notFound
    case unableToDelete
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unableToSave: return "Unable to save API key to Keychain."
        case .notFound: return "API key not found in Keychain."
        case .unableToDelete: return "Unable to delete API key from Keychain."
        case .invalidData: return "API key data is invalid."
        }
    }
}

// MARK: - Rate Limit Errors

enum RateLimitError: Error, LocalizedError {
    case minuteLimitExceeded
    case dailyLimitExceeded

    var errorDescription: String? {
        switch self {
        case .minuteLimitExceeded:
            return "Too many requests. Please wait a moment (15 per minute limit)."
        case .dailyLimitExceeded:
            return "Daily AI quota reached (1,500 per day). Resets at midnight."
        }
    }
}

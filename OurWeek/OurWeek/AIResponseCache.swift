//
//  AIResponseCache.swift
//  OurWeek
//
//  In-memory cache for Gemini AI responses with expiry tracking.
//

import Foundation
import UIKit
import CryptoKit

// MARK: - Cache Entry Wrapper

private class CacheEntry<T> {
    let value: T
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }

    init(value: T, ttl: TimeInterval) {
        self.value = value
        self.expiresAt = Date().addingTimeInterval(ttl)
    }
}

// MARK: - AI Response Cache

class AIResponseCache {
    static let shared = AIResponseCache()

    // MARK: - Configuration

    private static let textTTL: TimeInterval = 3600        // 1 hour
    private static let imageTTL: TimeInterval = 86400       // 24 hours
    private static let maxTextEntries = 100
    private static let maxImageEntries = 50

    // MARK: - Storage

    private let textCache = NSCache<NSString, CacheEntry<String>>()
    private let imageCache = NSCache<NSString, CacheEntry<UIImage>>()

    /// Track keys for manual expiry cleanup
    private var textKeys: Set<String> = []
    private var imageKeys: Set<String> = []
    private let lock = NSLock()

    // MARK: - Init

    private init() {
        textCache.countLimit = Self.maxTextEntries
        imageCache.countLimit = Self.maxImageEntries
        // ~100MB total for images
        imageCache.totalCostLimit = 100 * 1024 * 1024
    }

    // MARK: - Text Cache

    func cacheTextResponse(prompt: String, response: String) {
        let key = hashPrompt(prompt) as NSString
        let entry = CacheEntry(value: response, ttl: Self.textTTL)
        textCache.setObject(entry, forKey: key)
        lock.lock()
        textKeys.insert(key as String)
        lock.unlock()
    }

    func getCachedTextResponse(prompt: String) -> String? {
        let key = hashPrompt(prompt) as NSString
        guard let entry = textCache.object(forKey: key) else { return nil }
        if entry.isExpired {
            textCache.removeObject(forKey: key)
            lock.lock()
            textKeys.remove(key as String)
            lock.unlock()
            return nil
        }
        return entry.value
    }

    // MARK: - Image Cache

    func cacheImage(recipeId: UUID, style: ImageStyle, image: UIImage) {
        let key = "\(recipeId.uuidString)_\(style.rawValue)" as NSString
        let entry = CacheEntry(value: image, ttl: Self.imageTTL)
        let cost = image.pngData()?.count ?? 0
        imageCache.setObject(entry, forKey: key, cost: cost)
        lock.lock()
        imageKeys.insert(key as String)
        lock.unlock()
    }

    func getCachedImage(recipeId: UUID, style: ImageStyle) -> UIImage? {
        let key = "\(recipeId.uuidString)_\(style.rawValue)" as NSString
        guard let entry = imageCache.object(forKey: key) else { return nil }
        if entry.isExpired {
            imageCache.removeObject(forKey: key)
            lock.lock()
            imageKeys.remove(key as String)
            lock.unlock()
            return nil
        }
        return entry.value
    }

    // MARK: - Cache Management

    func clearCache() {
        textCache.removeAllObjects()
        imageCache.removeAllObjects()
        lock.lock()
        textKeys.removeAll()
        imageKeys.removeAll()
        lock.unlock()
    }

    func clearExpiredCache() {
        lock.lock()
        let currentTextKeys = textKeys
        let currentImageKeys = imageKeys
        lock.unlock()

        for key in currentTextKeys {
            if let entry = textCache.object(forKey: key as NSString), entry.isExpired {
                textCache.removeObject(forKey: key as NSString)
                lock.lock()
                textKeys.remove(key)
                lock.unlock()
            }
        }

        for key in currentImageKeys {
            if let entry = imageCache.object(forKey: key as NSString), entry.isExpired {
                imageCache.removeObject(forKey: key as NSString)
                lock.lock()
                imageKeys.remove(key)
                lock.unlock()
            }
        }
    }

    var cachedItemCount: Int {
        lock.lock()
        let count = textKeys.count + imageKeys.count
        lock.unlock()
        return count
    }

    // MARK: - Helpers

    private func hashPrompt(_ prompt: String) -> String {
        let data = Data(prompt.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

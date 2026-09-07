//
//  KeychainManager.swift
//  OurWeek
//
//  Secure API key storage using iOS Keychain.
//

import Foundation
import Security

struct KeychainManager {
    private static let serviceName = "com.ourweek.gemini"
    private static let accountName = "gemini-api-key"

    // MARK: - Save

    static func saveGeminiAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              let data = trimmedKey.data(using: .utf8) else {
            throw KeychainError.invalidData
        }

        // Delete existing key first (update pattern)
        try? deleteGeminiAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }

    // MARK: - Retrieve

    static func getGeminiAPIKey() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else {
            throw KeychainError.notFound
        }

        return key
    }

    // MARK: - Delete

    static func deleteGeminiAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete
        }
    }

    // MARK: - Check

    static func hasGeminiAPIKey() -> Bool {
        return (try? getGeminiAPIKey()) != nil
    }
}

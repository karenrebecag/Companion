import CompanionCore
import Foundation
import Security

public struct KeychainSecretStore: SecretStore, Sendable {
    public static let service = "Companion"

    public init() {}

    public func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try Self.check(status)
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw SecretStoreError.unexpected(Int(status))
        }
        return value
    }

    public func write(_ key: SecretKey, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SecretStoreError.emptyValue }
        let data = Data(trimmed.utf8)

        let query = baseQuery(for: key)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(
            query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        if updated != errSecItemNotFound {
            try Self.check(updated)
            return
        }

        var add = query
        add[kSecValueData as String] = data
        // Survive lock; never leave this Mac (no iCloud sync).
        add[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        add[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        try Self.check(SecItemAdd(add as CFDictionary, nil))
    }

    public func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        if status == errSecItemNotFound { return }
        try Self.check(status)
    }

    private func baseQuery(for key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }

    private static func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess:
            return
        case errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed:
            throw SecretStoreError.denied
        case errSecNotAvailable:
            throw SecretStoreError.notAvailable
        default:
            throw SecretStoreError.unexpected(Int(status))
        }
    }
}
